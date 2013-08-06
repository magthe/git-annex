{- Simple Base64 access
 -
 - Copyright 2011 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Utility.Base64 (toB64, fromB64Maybe, fromB64) where

import Codec.Binary.Base64
import Data.ByteString.Char8
import Data.Maybe

toB64 :: String -> String		
toB64 = unpack . encode . pack

fromB64Maybe :: String -> Maybe String
fromB64Maybe s = either (const Nothing) (Just . unpack) (decode $ pack s)

fromB64 :: String -> String
fromB64 = fromMaybe bad . fromB64Maybe
  where
	bad = error "bad base64 encoded data"
