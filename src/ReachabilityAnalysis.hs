module ReachabilityAnalysis where

--import qualified Data.Map.Strict as Map
import Data.Map.Strict 
import Control.Lens hiding(Context,pre)
import Types
import UpgradeAesir

reachabilityAnalysis :: UpgradeModel CModel -> IO (Map (NameState,Scope) Transitions)
reachabilityAnalysis umodel = 
 let cmodel = getValue umodel
     model  = cmodel ^. modelGet
 in return empty
