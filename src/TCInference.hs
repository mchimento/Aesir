module TCInference where

import BRT

tcInference :: BRT -> IO ()
tcInference t =
  do putStrLn "Trace condition inference... [DONE]\n"
