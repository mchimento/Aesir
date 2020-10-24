module TCInference where

import BRT

tcInference :: BRT -> IO ()
tcInference BNil = putStrLn "Trace condition inference... [Aborted]\n"
tcInference t    = 
 do putStrLn "Trace condition inference... [DONE]\n"        
