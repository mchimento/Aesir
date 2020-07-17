{-# LANGUAGE TemplateHaskell #-}

module BRTComputation where

import qualified Data.Map.Strict as Map
import Control.Lens
import Types
import UpgradeAesir
import BRT

brtAux :: BRT
brtAux = undefined

computeBRT :: UpgradeModel CModel -> Map.Map NameState Transitions -> Integer -> IO BRT
computeBRT cm mp iter = 
 do --root <- BRT Nothing [] 
    putStrLn "Backwards reachability tree computation... [DONE]\n"
    return brtAux
