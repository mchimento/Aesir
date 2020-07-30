{-# LANGUAGE TemplateHaskell #-}

module BRTComputation where

import qualified Data.Map.Strict as Map
import Control.Lens
import System.Exit
import System.Environment
import System.Process
import System.Directory
import Data.List
import Types
import UpgradeAesir
import CommonFunctions
import BRT
import JML.JMLInjection


computeBRT :: UpgradeModel CModel -> Map.Map NameState Transitions -> Integer -> NameState -> FilePath -> FilePath -> IO BRT
computeBRT cm mp iter st jpath out_add = 
 do let toAnalyse_add = out_add ++ "workspace/files2analyse"
    let model   = getValue cm
    let initial = (head $ getStarting $ pStates (model ^. modelGet ^. ctxtGet ^. property)) ^. getNS
    let root    = BRT Nothing [] initial st (getJMLEprop $ model ^. initpropGet) Nothing iter
    createDirectoryIfMissing False toAnalyse_add
    copyFiles jpath toAnalyse_add
    injectJMLannotations cm jpath out_add
    putStrLn "Backwards reachability tree computation... [DONE]"
    return root

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

