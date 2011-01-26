{- git-annex internal data types
 -
 - Most things should not need this, using Types and/or Annex instead.
 -
 - Copyright 2010 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module TypeInternals where

import Control.Monad.State (StateT)
import Data.String.Utils
import qualified Data.Map as M
import Test.QuickCheck

import qualified GitRepo as Git
import qualified GitQueue

-- command-line flags
type FlagName = String
data Flag =
	FlagBool Bool |
	FlagString String
		deriving (Eq, Read, Show)

-- git-annex's runtime state type doesn't really belong here,
-- but it uses Backend, so has to be here to avoid a depends loop.
data AnnexState = AnnexState {
	repo :: Git.Repo,
	backends :: [Backend Annex],
	supportedBackends :: [Backend Annex],
	flags :: M.Map FlagName Flag,
	repoqueue :: GitQueue.Queue,
	quiet :: Bool
} deriving (Show)

-- git-annex's monad
type Annex = StateT AnnexState IO

-- annexed filenames are mapped through a backend into keys
type KeyName = String
type BackendName = String
data Key = Key (BackendName, KeyName) deriving (Eq, Ord)

-- constructs a key in a backend
genKey :: Backend a -> KeyName -> Key
genKey b f = Key (name b,f)

-- show a key to convert it to a string; the string includes the
-- name of the backend to avoid collisions between key strings
instance Show Key where
	show (Key (b, k)) = b ++ ":" ++ k

instance Read Key where
	readsPrec _ s = [(Key (b,k), "")]
		where
			l = split ":" s
			b = if null l then "" else head l
			k = join ":" $ drop 1 l

-- for quickcheck
instance Arbitrary Key where
	arbitrary = do
		backendname <- arbitrary
		keyname <- arbitrary
		return $ Key (backendname, keyname)

prop_idempotent_key_read_show :: Key -> Bool
prop_idempotent_key_read_show k
	-- backend names will never contain colons
	| elem ':' (backendName k) = True
	| otherwise = k == (read $ show k)

backendName :: Key -> BackendName
backendName (Key (b,_)) = b
keyName :: Key -> KeyName
keyName (Key (_,k)) = k

-- this structure represents a key-value backend
data Backend a = Backend {
	-- name of this backend
	name :: String,
	-- converts a filename to a key
	getKey :: FilePath -> a (Maybe Key),
	-- stores a file's contents to a key
	storeFileKey :: FilePath -> Key -> a Bool,
	-- retrieves a key's contents to a file
	retrieveKeyFile :: Key -> FilePath -> a Bool,
	-- removes a key, optionally checking that enough copies are stored
	-- elsewhere
	removeKey :: Key -> Maybe Int -> a Bool,
	-- checks if a backend is storing the content of a key
	hasKey :: Key -> a Bool,
	-- called during fsck to check a key
	-- (second parameter may be the number of copies that there should
	-- be of the key)
	fsckKey :: Key -> Maybe Int -> a Bool
}

instance Show (Backend a) where
	show backend = "Backend { name =\"" ++ name backend ++ "\" }"

instance Eq (Backend a) where
	a == b = name a == name b
