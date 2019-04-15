module Main where

import System.Directory
import System.Environment as SE
import System.Console.GetOpt
import Control.Monad.Writer
import Types
import CommonFunctions
import ParserModel.Parser
import ParserModel.Absaesir
import ErrM
import UpgradeAesir

-------------
-- Version --
-------------

version :: String
version = "Aesir 0.0"

-- version meaning   +--------- version ID
--                   | +------- version ID
--                   | | +----- mayor changes or (mayor) bugs fixed in API
--                   | | | + -- minor changes or (minor) bugs fixed in API
-- version           A.B.C.D 

----------
-- Main --
----------

main :: IO ()
main =
 do args <- SE.getArgs    
    case getOpt Permute options args of
      ([Help],xs,[]) -> 
        do name <- getProgName
           if (not.null) xs 
           then do putStrLn ("\nError: Invalid usage of option -h.\n")
                   putStrLn ("Usage: " ++ name ++ " -h\n")
           else do putStrLn $ usageInfo "" options 
                   putStrLn ("Usage: " ++ name ++ " [-OPTIONS] <java_source_files> <model_file> <output>")
      ([Version],xs,[]) -> 
        do name <- getProgName
           if (not.null) xs 
           then do putStrLn ("\nError: Invalid usage of option -v.\n")
                   putStrLn ("Usage: " ++ name ++ " -v\n")
           else do putStrLn version
      ([OnlyParse],xs,[]) -> 
        if length xs /= 1
        then do name <- getProgName
                putStrLn ("\nError: Invalid usage of option -p.\n")
                putStrLn ("Usage: " ++ name ++ " -p <model_file>\n")
        else 
          do let model_fn = head xs
             ws <- argsExist Nothing (Just model_fn) Nothing
             let (b,s) = runWriter ws
             if b
             then do model_txt <- readFile model_fn
                     putStrLn $ "\nWelcome to Aesir\n"
                     case parse model_txt of
                          Bad s       -> putStrLn $ "The parsing has failed.\n\n" ++ s ++ "\n"
                          Ok absmodel -> do let model = upgradeModel absmodel 
                                            case runStateT model emptyEnv of
                                                Bad s -> putStrLn $ "The parsing has failed.\n\n" ++ s ++ "\n"
                                                Ok _  -> putStrLn "The parsing was successful.\n"
             else putStrLn s
      (flags,[java_fn_add, model_fn, output_add],[]) -> 
          if checkOptions flags
          then run flags java_fn_add model_fn output_add
          else putStrLn ("\nError: Invalid usage of options.\n")
      (_,_,[]) -> do name <- getProgName
                     putStrLn ("Usage: " ++ name ++ " [-OPTIONS] <java_source_files> <model_file> <output>\n")
      (_,_,errs) -> sequence_ $ map putStrLn errs

----------------
-- Runs Aesir --
----------------

run :: [Flag] -> FilePath -> FilePath -> FilePath -> IO ()
run flags java_fn_add model_fn output_add =  
 do putStrLn $ "\nWelcome to Aesir\n"
    ws <- argsExist (Just java_fn_add) (Just model_fn) (Just output_add)
    case runWriter ws of
     (b,s) ->
      if not b 
      then putStrLn s
      else do let java_fn_add' = setAddress java_fn_add
              ppdateP <- fmap parse $ readFile model_fn
              case ppdateP of
                   Bad s        -> do putStrLn $ "\nThe parsing has failed: " ++ s
                   Ok absmodel -> 
                      do let output_addr = setAddress output_add
                         let output_add' = output_addr ++ "out/"
                         checkOutputDirectory output_add'
                         createDirectoryIfMissing False output_add'      
                         createDirectoryIfMissing False (output_add' ++ "/workspace")
                         let model = upgradeModel absmodel
                         case runStateT model emptyEnv of
                              Bad s -> putStrLn s
                              Ok _  -> do if null (wellFormedActions model)
                                          then do putStrLn "Aesir has finished successfully.\n"
                                          else putStrLn (wellFormedActions model)

-------------------------
-- Auxiliary Functions --
-------------------------

wellFormedActions :: UpgradeModel CModel -> String
wellFormedActions _ = ""

--Method used to check if the provided arguments exist
argsExist :: Maybe FilePath -> Maybe FilePath -> Maybe FilePath -> IO (Writer String Bool)
argsExist java_fn_add model_fn output_add = 
 do source <- checkDirectory java_fn_add
    ppd    <- isModelFile model_fn
    out    <- checkDirectory output_add
    return $ appendWriter (appendWriter source ppd) out

--Checks if a given directory exists
checkDirectory :: Maybe FilePath -> IO (Writer String Bool)
checkDirectory Nothing    = return $ writer (True,"")
checkDirectory (Just add) = 
 do b <- doesDirectoryExist add
    if b 
    then return $ writer (b,"") 
    else return $ writer (False,"Error: Directory " ++ add ++ " does not exist.\n")

--Checks if the the file in FilePath has .model extension (i.e., is a model file) and if it exists
isModelFile :: Maybe FilePath -> IO (Writer String Bool)
isModelFile Nothing          = return $ writer (True,"")
isModelFile (Just model_fn) = 
 do b1 <- doesFileExist model_fn
    if (not b1)
    then return $ writer (False,"Error: model file " ++ model_fn ++ " does not exist.\n")
    else let (ext,_) = break ('.' ==) $ reverse model_fn
         in if (ext == "ledom")
            then return $ writer (True,"")
            else return $ writer (False,"Error: file " ++ model_fn ++ " is not a model file.\n")

appendWriter :: Writer String Bool -> Writer String Bool -> Writer String Bool
appendWriter wr wr' =
 case (runWriter wr,runWriter wr') of 
      ((b,s),(b',s')) -> writer (b&&b',s++s')

--Method used to check wrong combination of options
checkOptions :: [Flag] -> Bool
checkOptions []               = True
checkOptions (Version:xs)     = False
checkOptions (OnlyParse:xs)   = False
checkOptions (Help:xs)        = False
--checkOptions (_:xs)           = checkOptions xs

checkOutputDirectory :: FilePath -> IO ()
checkOutputDirectory file = 
 do b <- doesDirectoryExist file
    if b then removeDirectoryRecursive file
         else return ()

setAddress :: FilePath -> FilePath
setAddress add = 
 if ((last $ trim add) == '/') 
 then add 
 else add ++ "/"
