module TCInference where

import BRT
import Control.Lens hiding(Context,pre,children)
import Types

tcInference :: BRT -> IO ()
tcInference t =
  if null (t ^. children)
  then do putStrLn "Trace condition inference... \n"
          putStrLn "Amount of trace conditions generated: 1"
          putStrLn (show (TC "true" []))
          putStrLn "Trace condition inference... [DONE]\n"
  else do putStrLn "Trace condition inference... \n"
          let ret = seq2TraceConds $ flattenBRT t
          putStrLn $ "Amount of trace conditions generated: " ++ show (length ret)
          putStrLn (show ret)
          putStrLn "Trace condition inference... [DONE]\n"

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

seq2TraceConds :: [[(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))]] -> TraceConditions
seq2TraceConds []       = []
seq2TraceConds (xs:xss) =
  if null xs
  then seq2TraceConds xss
  else seq2TraceCond xs : seq2TraceConds xss

seq2TraceCond :: [(NameState,JMLExp,Maybe (MethodName, [Bind],ClassInfo))] -> TraceCondition
seq2TraceCond [] = TC "true" []
seq2TraceCond xs =
  let si    = head xs in
  let trace = map (\(_,_,z) -> z) $ init xs in
  let phi   = (\(_,x,_) -> x) si
  in TC phi trace
