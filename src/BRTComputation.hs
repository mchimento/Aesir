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
    let initial = (head $ getStarting $ pStates (model ^. modelGet ^. ctxtGet ^. property)) ^. getNS
    let root    = BRT Nothing [] initial st (getJMLEprop $ model ^. initpropGet) Nothing iter (getIdIprop $ model ^. initpropGet)
    createDirectoryIfMissing False toAnalyse_add
    copyFiles jpath toAnalyse_add
    injectJMLinitial cm jpath toAnalyse_add    
    brt root mp iter

-------------------------------------------------------
-- Backwards reachability tree computation iteration --
-------------------------------------------------------

brt :: BRT -> Map.Map NameState Transitions -> Integer -> IO BRT
brt t mp iter = 
 do let trs = Map.lookup (t ^. current) mp
    if isJust trs
    then do let hs = map mkHT $ fromJust trs
            putStrLn "Backwards reachability tree computation... [DONE]"
            return t
         else do putStrLn $ "Aesir: Error when computing reachability for the state " 
                            ++ show (t ^. current) ++ "."
                 return BNil
                         

---------------------------
-- Creates Hoare triples --
---------------------------

mkHT :: Transition -> HT
mkHT (Transition q (Arrow tr c _) q') = undefined

mkHT' :: IProp -> HT
mkHT' ip = 
 HT { _htName     = getIdIprop ip
    , _methodCN   = MCN "" "" OverNil
    , _pre        = "true"
    , _post       = getJMLEprop ip
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

