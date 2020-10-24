{-# LANGUAGE TemplateHaskell #-}

module BRT where

import Control.Lens
import Types

----------------------------------
-- Backwards Reachability Trees --
----------------------------------

data BRT = BRT
 { _parent    :: Maybe BRT --Points to the parent of the brt node
 , _childrein :: [BRT]     --List of children of the brt node
 , _initial   :: NameState --Initial state of the model
 , _current   :: NameState --Current (analysed) state 
 , _prop      :: JMLExp    --FOL formula in root, or backtracked condition
 , _method    :: Maybe (Trigger, [Bind])--(method_executed_to_reach_parent,methods_arguments)
 , _iter      :: Integer --allowed amount of iterations for the loops
 , _idBrt     :: String --Node identifier
 } | BNil deriving (Eq,Read)


------------
-- Lenses --
------------

-- ^. is view, e.g. ppd ^. importsGet
-- %~ is over, e.g. importsGet %~ foo $ ppd
-- .~ is set, e.g. importsGet .~ imps $ ppd

makeLenses ''BRT
