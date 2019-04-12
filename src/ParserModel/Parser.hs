module ParserModel.Parser(parse) where

import CommonFunctions
import Types
import System.IO ( stdin, hGetContents )
import System.Environment ( getArgs, getProgName )

import ParserModel.Lexaesir
import ParserModel.Paraesir
import ParserModel.Skelaesir
import ParserModel.Printaesir
import ParserModel.Absaesir
import ErrM

type ParseFun a = [Token] -> Err a

run :: (Print a, Show a) => ParseFun a -> String -> Err a
run p s = let ts = myLexer s 
          in case p ts of
                Bad s    -> fail s
                Ok  tree -> return tree

parse :: String -> Err AbsModel
parse = run pAbsModel
