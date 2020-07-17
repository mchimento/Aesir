{-# LANGUAGE TemplateHaskell #-}

module BRT where

import Control.Lens
import Types

----------------------------------
-- Backwards Reachability Trees --
----------------------------------

data BRT = BRT
 { _parent    :: BRT
 , _childrein :: [BRT]
 , _initial   :: State
 , _current   :: State
 , _property  :: JMLExp
 , _method    :: (Trigger, [Bind])
 , _iter      :: Integer
 } deriving (Eq,Read)


------------
-- Lenses --
------------

-- ^. is view, e.g. ppd ^. importsGet
-- %~ is over, e.g. importsGet %~ foo $ ppd
-- .~ is set, e.g. importsGet .~ imps $ ppd

makeLenses ''BRT
