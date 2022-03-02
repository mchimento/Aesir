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
    let phi     = getJMLEprop $ model ^. initpropGet
    let root = BRT Nothing [] initial st phi
                   Nothing iter (getIdIprop $ model ^. initpropGet) [st] Map.empty [(st,Nothing)]
    if initial == st
    then return root
    else do createDirectoryIfMissing False toAnalyse_add
            copyFiles jpath toAnalyse_add
            injectJMLinitial cm toAnalyse_add
            let mp' = makeIDtrsMap $ removeDuplicates $ concatMap snd (Map.toList mp)
            case model ^. assignableGet of
               AssNil           -> brt cm root mp iter trs mp' out_add
               TAssignables ass -> do let hts = map mkHTass ass
                                      injectJMLannotations cm toAnalyse_add hts
                                      brt cm root mp iter trs mp' out_add

--------------------------------------------------------
-- Backwards reachability tree computation iterations --
--------------------------------------------------------

--TODO: Cannot handle the use of model variables in the preconditions
--TODO: Cannot handle different methods with the same names, i.e., methods overriding
brt :: UpgradeModel CModel -> BRT -> Map.Map NameState Transitions -> Integer ->
       [TriggersInfo] -> Map.Map Transition Bits -> FilePath -> IO BRT
brt cm node rt iter trs mp out_add =
 do putStrLn $ "\nAnalysing node " ++ node ^. idBrt ++ ":\n"
    let candidates = Map.lookup (node ^. current) rt
    if isJust candidates
    then do let reachable = filterNodes node mp (fromJust candidates)
            child  <- brt_iter cm node trs reachable mp out_add
            child' <- sequence $ map (\t -> brt cm t rt iter trs mp out_add) child
            return $ (children .~ child' $ node)
    else do putStrLn $ "Aesir: Error when computing reachability for the state "
                       ++ show (node ^. current) ++ "."
            return BNil

--Computes the children of a BRT
brt_iter :: UpgradeModel CModel -> BRT -> [TriggersInfo] -> [Transition]
            -> Map.Map Transition Bits -> FilePath -> IO [BRT]
brt_iter cm _ trs [] _ out_add     = return []
brt_iter cm node trs ts mp out_add =
  do let toAnalyse_add = out_add ++ "workspace/files2analyse"
     let hinfo         = htInfo trs node ts
     let hts           = map fst hinfo
     putStrLn "Generating Hoare triples... "
     injectJMLannotations cm toAnalyse_add hts
     runKeY toAnalyse_add (out_add++"workspace/")
     setDummyVarsFalse cm toAnalyse_add hts
     nodes <- newNodes node (out_add++"workspace/") hinfo mp trs
     return nodes

--Filter transitions which would violate the allowed amount of loop iterations
filterNodes :: BRT -> Map.Map Transition Bits -> Transitions -> Transitions
filterNodes _ _ []           = []
filterNodes node mp (tr:trs) =
 let si = fromState tr in
 let vs = node ^. visited
 in if (elem si vs)
    then if checkLoop node mp tr
         then filterNodes node mp trs
         else tr : filterNodes node mp trs
    else tr : filterNodes node mp trs

--Check if the allowed amount of loop iterations is violated
checkLoop :: BRT -> Map.Map Transition Bits -> Transition -> Bool
checkLoop node mp tr =
  let (xs,ys) = splitAtState (fromState tr) (node ^. path) in
  let id = makeIDtrs (tr:map (fromJust.snd) (init xs)) mp in
  let mp' = node ^. loops
  in case Map.lookup id mp' of
        Nothing -> False
        Just n  -> (_iter node) < (n+1)

splitAtState :: NameState -> [(NameState,Maybe Transition)]
                -> ([(NameState,Maybe Transition)],[(NameState,Maybe Transition)])
splitAtState _ []     = ([],[])
splitAtState s (x:xs) =
  if s == fst x
  then ([x],xs)
  else let (ys,zs) = splitAtState s xs
       in (x:ys,zs)

--Creates to new nodes to add to the computed BRT
newNodes :: BRT -> FilePath -> [(HT,Transition)] -> Map.Map Transition Bits -> [TriggersInfo] -> IO [BRT]
newNodes node out_add hinfo mp trs =
  do let file = out_add ++ "out.xml"
     r <- readFile file
     let xml   = ParserXMLKeYOut.parse r
     let xml'  = removeNoneHTs xml (map ((^.htName).fst) hinfo)
     let child = makeNodes node trs mp (pairingProofHT xml' hinfo)
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

makeNodes :: BRT -> [TriggersInfo] -> Map.Map Transition Bits -> [(Proof,HT,Transition)] -> [BRT]
makeNodes _ _ _ []                   = []
makeNodes node trs mp ((p,ht,tr):xs) = makeNodesEP node trs ht tr 0 mp (executionPath p) ++ makeNodes node trs mp xs

makeNodesEP :: BRT -> [TriggersInfo] -> HT -> Transition -> Int ->
               Map.Map Transition Bits -> [EPath] -> [BRT]
makeNodesEP _ _ _ _ _ _ []               = []
makeNodesEP node trs ht tr n mp (ep:eps) =
  if (verified ep) == "false"
  then makeNodesEP node trs ht tr n mp eps
  else BRT (Just node) [] (node^.initial) (fromState tr) (makeCond ep) (makeMethod trs tr)
           (_iter node) (ht^.htName ++ show n) (makeVisited tr node)
           (makeLoop node tr mp) (makePath tr node)
       : makeNodesEP node trs ht tr (n+1) mp eps

makeCond :: EPath -> JMLExp
makeCond ep = removeDLstrContent $ addParenthesisNot $ removeSelf $ pathCondition ep

makeVisited :: Transition -> BRT -> [NameState]
makeVisited tr node =
  let nm = fromState tr in
  let ps = (node ^. path)
  in if elem nm (node ^. visited)
     then let (xs,ys) = splitAtState nm ps in
          let xs'     = map fst xs
          in nm : [ s | s <- (node ^. visited), not (elem s xs')]
     else nm : (node ^. visited)

makePath :: Transition -> BRT -> [(NameState,Maybe Transition)]
makePath tr node =
  let nm = fromState tr in
  let ps = node ^. path
  in if elem nm (node ^. visited)
     then let (xs,ys) = splitAtState nm ps
          in (nm,Just tr):ys
     else (nm,Just tr):ps

makeLoop :: BRT -> Transition -> Map.Map Transition Bits -> Map.Map Loop Integer
makeLoop node tr mp =
  if elem (fromState tr) (node ^. visited)
  then updLoop node tr mp
  else node ^. loops

updLoop :: BRT -> Transition -> Map.Map Transition Bits -> Map.Map Loop Integer
updLoop node tr mp =
  let (xs,ys) = splitAtState (fromState tr) (node ^. path) in
  let mp' = node ^. loops in
  let id = makeIDtrs (tr:map (fromJust.snd) (init xs)) mp
  in case Map.lookup id mp' of
       Nothing -> Map.insert id 1 mp'
       Just n  -> Map.insert id (n+1) mp'

--TODO:When model variables can be handled replace 'ys' by 'tiBinds tinf'
makeMethod :: [TriggersInfo] -> Transition -> Maybe (MethodName, [Bind], ClassInfo)
makeMethod trs t =
  let tr   = trigger $ arrow t in
  case getTrInfo tr trs of
    Nothing   -> Nothing
    Just tinf -> case tiTrvar tinf of
                   EVExit xs -> let zs = map getIdBind xs in
                                let ys = [ y | y <- tiBinds tinf, not (elem (getIdBind y) zs) ]
                                in Just (tiMN tinf,ys,tiCI tinf)
                   _         -> Just (tiMN tinf,tiBinds tinf,tiCI tinf)

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

mkHTass :: Ass -> HT
mkHTass (Ass cl m ass) =
 HT { _htName     = "ass_"++m
    , _methodCN   = MCN cl m OverNil
    , _pre        = "true"
    , _post       = "true"
    , _assignable = intercalate "," ass
    , _newPRe     = []
    , _chGet      = 0
    , _path2it    = ""
    , _varThis    = ("","")
    }

------------------------------------------------------
-- Mapping associating transitions with a unique ID --
------------------------------------------------------

data Bit = One | Zero deriving(Eq)

instance Show Bit where
  show One  = "1"
  show Zero = "0"

addBit :: Bit -> Bit -> Bit
addBit One Zero  = One
addBit One One   = Zero
addBit Zero One  = One
addBit Zero Zero = Zero

type Bits = [Bit]

addBits :: Bits -> Bits -> Bits
addBits xs [] = xs
addBits xs ys = map (uncurry addBit) (zip xs ys)

makeIDtrs :: Transitions -> Map.Map Transition Bits -> String
makeIDtrs trs mp = concatMap show $ foldr (\x xs -> addBits x xs) [] (getBits trs mp)

getBits :: Transitions -> Map.Map Transition Bits -> [Bits]
getBits [] _        = []
getBits (tr:trs) mp =
  case Map.lookup tr mp of
    Nothing -> getBits trs mp
    Just x  -> x : getBits trs mp

makeIDtrsMap :: Transitions -> Map.Map Transition Bits
makeIDtrsMap [] = Map.empty
makeIDtrsMap xs =
  let ys = replicate (length xs) Zero in
  Map.fromList $ zip xs (generateIDs (length ys) ys)

generateIDs :: Int -> Bits -> [Bits]
generateIDs 0 _    = []
generateIDs n bits = makeIDtr (n-1) bits : generateIDs (n-1) bits

makeIDtr :: Int -> Bits -> Bits
makeIDtr n = modifyAt n (addBit One)

modifyAt :: Int -> (a -> a) -> [a] -> [a]
modifyAt i f ls
  | i < 0 = ls
  | otherwise = go i ls
  where
    go 0 (x:xs) = f x : xs
    go n (x:xs) = x : go (n-1) xs
    go _ []     = []

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
