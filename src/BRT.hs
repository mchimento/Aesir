{-# LANGUAGE TemplateHaskell #-}

module BRT where

import Control.Lens
import Types
import qualified Data.Map.Strict as Map

----------------------------------
-- Backwards Reachability Trees --
----------------------------------

data BRT = BRT
 { _parent    :: Maybe BRT --Points to the parent of the brt node
 , _children :: [BRT]     --List of children of the brt node
 , _initial   :: NameState --Initial state of the model
 , _current   :: NameState --Current (analysed) state
 , _prop      :: JMLExp    --FOL formula in root, or backtracked condition
 , _method    :: Maybe (MethodName, [Bind],ClassInfo)--(method_executed_to_reach_parent,methods_arguments,class_type)
 , _iter      :: Integer --allowed amount of iterations for the loops
 , _idBrt     :: String --Node identifier
 , _visited   :: [NameState] -- List of visited states
 , _loops     :: Map.Map Loop Integer -- Map to keep track of the amounts of iterations a loop has performed
 , _path      :: [NameState] -- Path followed through the BRT (from current node to root)
 } | BNil deriving (Eq,Show)

type Loop = String

------------
-- Lenses --
------------

-- ^. is view, e.g. ppd ^. importsGet
-- %~ is over, e.g. importsGet %~ foo $ ppd
-- .~ is set, e.g. importsGet .~ imps $ ppd

makeLenses ''BRT
