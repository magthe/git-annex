{- QuickCheck with additional instances
 -
 - Copyright 2012 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Utility.QuickCheck
	( module X
	, module Utility.QuickCheck
	) where

import Test.QuickCheck as X
import Data.Time.Clock.POSIX
import System.Posix.Types
import qualified Data.Map as M
import Control.Applicative

instance (Arbitrary k, Arbitrary v, Eq k, Ord k) => Arbitrary (M.Map k v) where
	arbitrary = M.fromList <$> arbitrary

{- Times before the epoch are excluded. -}
instance Arbitrary POSIXTime where
	arbitrary = nonNegative arbitrarySizedIntegral

instance Arbitrary EpochTime where
	arbitrary = nonNegative arbitrarySizedIntegral

{- Pids are never negative, or 0. -}
instance Arbitrary ProcessID where
	arbitrary = arbitrarySizedBoundedIntegral `suchThat` (> 0)

{- Inodes are never negative. -}
instance Arbitrary FileID where
	arbitrary = nonNegative arbitrarySizedIntegral

{- File sizes are never negative. -}
instance Arbitrary FileOffset where
	arbitrary = nonNegative arbitrarySizedIntegral

nonNegative :: (Num a, Ord a) => Gen a -> Gen a
nonNegative g = g `suchThat` (>= 0)
