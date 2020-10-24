{-# LANGUAGE TemplateHaskell #-}

module BRTComputation where

import qualified Data.Map.Strict as Map
import Control.Lens
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

---------------------------------------------
-- Backwards reachability tree computation --
---------------------------------------------

computeBRT :: UpgradeModel CModel -> Map.Map NameState Transitions -> Integer -> NameState -> FilePath -> FilePath -> IO BRT
computeBRT cm mp iter st jpath out_add = 
 do let toAnalyse_add = out_add ++ "workspace/files2analyse"
    let model   = getValue cm
    let trs     = allTriggers $ getEnvVal cm
    let initial = (head $ getStarting $ pStates (model ^. modelGet ^. ctxtGet ^. property)) ^. getNS
    let root    = BRT Nothing [] initial st (getJMLEprop $ model ^. initpropGet) Nothing iter (getIdIprop $ model ^. initpropGet)
    createDirectoryIfMissing False toAnalyse_add
    copyFiles jpath toAnalyse_add
    injectJMLinitial cm jpath toAnalyse_add    
    brt root mp iter trs

--------------------------------------------------------
-- Backwards reachability tree computation iterations --
--------------------------------------------------------

--TODO: Cannot handle the use of model variables in the preconditions
--TODO: Cannot handle different methods with the same names, i.e., methods overriding
brt :: BRT -> Map.Map NameState Transitions -> Integer -> [TriggersInfo] -> IO BRT
brt t mp iter trs = 
 do let ts = Map.lookup (t ^. current) mp
    if isJust ts
    then do let hts = nameHTS 0 (t ^. idBrt) $ map (mkHT (t ^. prop) trs) $ fromJust ts
            putStrLn "Backwards reachability tree computation... [DONE]"
            return t
         else do putStrLn $ "Aesir: Error when computing reachability for the state " 
                            ++ show (t ^. current) ++ "."
                 return BNil

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


mkHT :: JMLExp -> [TriggersInfo] -> Transition -> HT
mkHT jmlexp trs (Transition q (Arrow tr c _ _) q') = 
 HT { _htName     = ""
    , _methodCN   = mkMCN tr trs
    , _pre        = c
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

runKeY :: FilePath -> FilePath -> [Flag] -> IO ExitCode
runKeY output_add' output_addr flags = 
 do expath <- getExecutableDir         
    rawSystem "java" ["-jar",expath++"/key.starvoors.jar","-starvoors",output_add', output_addr]

