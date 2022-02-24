{-# LANGUAGE TemplateHaskell #-}

module BRTComputation where

import qualified Data.Map.Strict as Map
import Control.Lens hiding(children)
import System.Exit
import System.Environment
import System.Process
import System.Directory
import Data.List
import Data.Maybe
import Types
import UpgradeAesir
import CommonFunctions
import BRT
import JML.JMLInjection
import ParserXMLKeYOut
import DL2JML

---------------------------------------------
-- Backwards reachability tree computation --
---------------------------------------------

computeBRT :: UpgradeModel CModel -> Map.Map NameState Transitions -> Integer -> NameState -> FilePath -> FilePath -> IO BRT
computeBRT cm mp iter st jpath out_add =
 do let toAnalyse_add = out_add ++ "workspace/files2analyse"
    let model   = getValue cm
    let trs     = allTriggers $ getEnvVal cm
    let initial = (head $ getStarting $ pStates (model ^. modelGet ^. ctxtGet ^. property)) ^. getNS
    let root = BRT Nothing [] initial st (getJMLEprop $ model ^. initpropGet)
                   Nothing iter (getIdIprop $ model ^. initpropGet) [] Map.empty []
    if initial == st
    then return root
    else do createDirectoryIfMissing False toAnalyse_add
            copyFiles jpath toAnalyse_add
            injectJMLinitial cm toAnalyse_add
            brt cm root mp iter trs out_add

--------------------------------------------------------
-- Backwards reachability tree computation iterations --
--------------------------------------------------------

--TODO: Cannot handle the use of model variables in the preconditions
--TODO: Cannot handle different methods with the same names, i.e., methods overriding
brt :: UpgradeModel CModel -> BRT -> Map.Map NameState Transitions -> Integer ->
       [TriggersInfo] -> FilePath -> IO BRT
brt cm node rt iter trs out_add =
 do let candidates = Map.lookup (node ^. current) rt
    if isJust candidates
    then do let reachable = filterNodes node (fromJust candidates)
            child  <- brt_iter cm node trs reachable out_add
            child' <- sequence $ map (\t -> brt cm t rt iter trs out_add) child
            return $ (children .~ child' $ node)
    else do putStrLn $ "Aesir: Error when computing reachability for the state "
                       ++ show (node ^. current) ++ "."
            return BNil

--Computes the children of a BRT
brt_iter :: UpgradeModel CModel -> BRT -> [TriggersInfo] -> [Transition] -> FilePath -> IO [BRT]
brt_iter cm _ trs [] out_add    = return []
brt_iter cm node trs ts out_add =
  do let toAnalyse_add = out_add ++ "workspace/files2analyse"
     let hinfo         = htInfo trs node ts
     let hts           = map fst hinfo
     injectJMLannotations cm toAnalyse_add hts
     runKeY toAnalyse_add (out_add++"workspace/")
     setDummyVarsFalse cm toAnalyse_add hts
     nodes <- newNodes node (out_add++"workspace/") hinfo trs
     return nodes

--Filter transitions which would violate the allowed amount of loop iterations
filterNodes :: BRT -> Transitions -> Transitions
filterNodes node []       = []
filterNodes node (tr:trs) =
 let si = fromState tr in
 let vs = node ^. visited
 in if (elem si vs)
    then let p = node ^. path
         in if checkLoop node si
            then filterNodes node trs
            else tr : filterNodes node trs
    else tr : filterNodes node trs

--Check if the allowed amount of loop iterations is violated
checkLoop :: BRT -> NameState -> Bool
checkLoop node nm =
  let (xs,ys) = splitAtState nm (node ^. path) in
  let ps = concat (nm:xs) in
  let mp = node ^. loops
  in case Map.lookup ps mp of
        Nothing -> False
        Just n  -> (_iter node) < (n+1)

splitAtState :: NameState -> [NameState] -> ([NameState],[NameState])
splitAtState _ []     = ([],[])
splitAtState s (x:xs) =
  if s == x
  then ([x],xs)
  else let (ys,zs) = splitAtState s xs
       in (x:ys,zs)

--Creates to new nodes to add to the computed BRT
newNodes :: BRT -> FilePath -> [(HT,Transition)] -> [TriggersInfo] -> IO [BRT]
newNodes node out_add hinfo trs =
  do let file = out_add ++ "out.xml"
     r <- readFile file
     let xml   = ParserXMLKeYOut.parse r
     let xml'  = removeNoneHTs xml (map ((^.htName).fst) hinfo)
     let child = makeNodes node trs (pairingProofHT xml' hinfo)
     return child

htInfo :: [TriggersInfo] -> BRT -> [Transition] -> [(HT,Transition)]
htInfo trs node ts =
 let hts = map (mkHT (node ^. prop) trs) ts
 in zip (nameHTS 0 (node ^. idBrt) hts) ts

pairingProofHT :: [Proof] -> [(HT,Transition)] -> [(Proof,HT,Transition)]
pairingProofHT [] _       = []
pairingProofHT (p:ps) cns =
 getHTforProof p cns : pairingProofHT ps cns

getHTforProof :: Proof -> [(HT,Transition)] -> (Proof,HT,Transition)
getHTforProof _ []          = undefined
getHTforProof p ((ht,t):ts) =
  let cn   = getHTNameErrConst (contractText p) (typee p) in
  let name = ht^.htName
  in if ((cn /= "") && cn == name)
     then (p,ht,t)
     else getHTforProof p ts

makeNodes :: BRT -> [TriggersInfo] -> [(Proof,HT,Transition)] -> [BRT]
makeNodes _ _ []                  = []
makeNodes node trs ((p,ht,tr):xs) = makeNodesEP node trs ht tr 0 (executionPath p) ++ makeNodes node trs xs

makeNodesEP :: BRT -> [TriggersInfo] -> HT -> Transition -> Int -> [EPath] -> [BRT]
makeNodesEP _ _ _ _ _ []              = []
makeNodesEP node trs ht tr n (ep:eps) =
  if (verified ep) == "false"
  then makeNodesEP node trs ht tr n eps
  else BRT (Just node) [] (node^.initial) (fromState tr) (makeCond ep) (makeMethod trs tr)
           (_iter node) (ht^.htName ++ show n) (fromState tr:(node ^. visited)) (makeLoop node (fromState tr)) (fromState tr:(node ^. path))
       : makeNodesEP node trs ht tr (n+1) eps

makeLoop :: BRT -> NameState -> Map.Map Loop Integer
makeLoop node nm =
  if elem nm (node ^. visited)
  then updLoop node nm
  else node ^. loops

updLoop :: BRT -> NameState -> Map.Map Loop Integer
updLoop node nm =
  let (xs,ys) = splitAtState nm (node ^. path) in
  let ps = concat (nm:xs) in
  let mp = node ^. loops
  in case Map.lookup ps mp of
       Nothing -> Map.insert ps 1 mp
       Just n  -> Map.insert ps (n+1) mp

makeCond :: EPath -> JMLExp
makeCond ep = removeDLstrContent $ addParenthesisNot $ removeSelf $ pathCondition ep

makeMethod :: [TriggersInfo] -> Transition -> Maybe (MethodName, [Bind], ClassInfo)
makeMethod trs t =
  let tr   = trigger $ arrow t in
  case getTrInfo tr trs of
    Nothing   -> Nothing
    Just tinf -> Just (tiMN tinf,tiBinds tinf,tiCI tinf)

---------------------------------
-- Adds names to Hoare triples --
---------------------------------

addNameHT :: Integer -> String -> HT -> HT
addNameHT n name ht =
 htName .~ (name ++ show n) $ ht

nameHTS :: Integer -> String -> HTriples -> HTriples
nameHTS _ _ []          = []
nameHTS n name (ht:hts) = addNameHT n name ht : nameHTS (n+1) name hts

---------------------------
-- Creates Hoare triples --
---------------------------

getTrInfo :: Trigger -> [TriggersInfo] -> Maybe TriggersInfo
getTrInfo _ []         = Nothing
getTrInfo tr (tinf:ts) =
 if (tr == tiTN tinf)
 then Just tinf
 else getTrInfo tr ts

mkMCN :: Trigger -> [TriggersInfo] -> MethodCN
mkMCN tr trs =
 case getTrInfo tr trs of
  Nothing   -> MCN "" "" OverNil
  Just tinf -> MCN (tiCI tinf) (tiMN tinf) OverNil

replaceClassVarWith :: Trigger -> [TriggersInfo] -> String -> String
replaceClassVarWith tr trs c =
  case getTrInfo tr trs of
   Nothing   -> "true"
   Just tinf -> let cv = tiCVar tinf in
                let xs = splitOnIdentifier cv c
                in head xs ++ concat (map ("this" ++) (tail xs))

--TODO:Update this function to refine properties using postconditions
mkHT :: JMLExp -> [TriggersInfo] -> Transition -> HT
mkHT jmlexp trs (Transition q (Arrow tr c _ _) q') =
 HT { _htName     = ""
    , _methodCN   = mkMCN tr trs
    , _pre        = replaceClassVarWith tr trs c
    , _post       = jmlexp
    , _assignable = "\\everything"
    , _newPRe     = []
    , _chGet      = 0
    , _path2it    = ""
    , _varThis    = ("","")
    }

-------------
-- Run KeY --
-------------

getExecutableDir :: IO FilePath
getExecutableDir =
 do expath <- getExecutablePath
    let xs = splitOnIdentifier "/" expath
    return (intercalate "/" $ init xs)

runKeY :: FilePath -> FilePath -> IO ExitCode
runKeY output_add' output_addr =
 do expath <- getExecutableDir
    rawSystem "java" ["-jar",expath++"/KeY/key.starvoors.jar","-starvoors",output_add', output_addr]
