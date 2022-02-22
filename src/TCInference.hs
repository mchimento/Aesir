module TCInference where

import BRT
import Control.Lens hiding(Context,pre,children)
import Types

tcInference :: BRT -> IO ()
tcInference t =
  do putStrLn "Trace condition inference... [DONE]\n"
     putStrLn (show (flattenBRT t))

flattenBRT :: BRT -> [[(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]]
flattenBRT brt =
  let node = brt2elem brt
  in addNode_lift node False (map flattenBRT (brt ^. children))

addNode_lift node False []   = [[node]]
addNode_lift node True []    = []
addNode_lift node _ (xs:xss) = addNode node xs ++ addNode_lift node True xss

addNode :: a -> [[a]] -> [[a]]
addNode node []       = []
addNode node (xs:xss) = (xs++[node]) : addNode node xss

brt2elem :: BRT -> (NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))
brt2elem brt = (brt ^. current, brt ^. prop, brt ^. method)
