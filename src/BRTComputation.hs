{-# LANGUAGE TemplateHaskell #-}

module BRTComputation where

import qualified Data.Map.Strict as Map
import Control.Lens
import Types
import UpgradeAesir
import BRT


computeBRT :: UpgradeModel CModel -> Map.Map NameState Transitions -> Integer -> NameState -> IO BRT
computeBRT cm mp iter st = 
 do let model   = getValue cm
    let initial = (head $ getStarting $ pStates (model ^. modelGet ^. ctxtGet ^. property)) ^. getNS
    let root    = BRT Nothing [] initial st (getJMLEprop $ model ^. initpropGet) Nothing iter
    putStrLn "Backwards reachability tree computation... [DONE]\n"
    return root
