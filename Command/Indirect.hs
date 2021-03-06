{- git-annex command
 -
 - Copyright 2012 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Command.Indirect where

import System.PosixCompat.Files

import Common.Annex
import Command
import qualified Git
import qualified Git.Command
import qualified Git.LsFiles
import Config
import qualified Annex
import Annex.Direct
import Annex.Content
import Annex.CatFile
import Annex.Version
import Annex.Perms
import Init

def :: [Command]
def = [notBareRepo $ noDaemonRunning $
	command "indirect" paramNothing seek
		SectionSetup "switch repository to indirect mode"]

seek :: [CommandSeek]
seek = [withNothing start]

start :: CommandStart
start = ifM isDirect
	( do
		unlessM (coreSymlinks <$> Annex.getGitConfig) $
			error "Git is configured to not use symlinks, so you must use direct mode."
		whenM probeCrippledFileSystem $
			error "This repository seems to be on a crippled filesystem, you must use direct mode."
		next perform
	, stop
	)

perform :: CommandPerform
perform = do
	showStart "commit" ""
	whenM (stageDirect) $ do
		showOutput
		void $ inRepo $ Git.Command.runBool
			[ Param "commit"
			, Param "-m"
			, Param "commit before switching to indirect mode"
			]
	showEndOk

	-- Note that we set indirect mode early, so that we can use
	-- moveAnnex in indirect mode.
	setDirect False

	top <- fromRepo Git.repoPath
	(l, clean) <- inRepo $ Git.LsFiles.stagedOthersDetails [top]
	forM_ l go
	void $ liftIO clean
	next cleanup
  where
	{- Walk tree from top and move all present direct mode files into
	 - the annex, replacing with symlinks. Also delete direct mode
	 - caches and mappings. -}
	go (_, Nothing) = noop
	go (f, Just sha) = do
		r <- liftIO $ catchMaybeIO $ getSymbolicLinkStatus f
		case r of
			Just s
				| isSymbolicLink s -> void $ flip whenAnnexed f $
					\_ (k, _) -> do
						cleandirect k
						return Nothing
				| otherwise -> 
					maybe noop (fromdirect f)
						=<< catKey sha
			_ -> noop

	fromdirect f k = do
		showStart "indirect" f
		thawContentDir =<< calcRepo (gitAnnexLocation k)
		cleandirect k -- clean before content directory gets frozen
		whenM (liftIO $ not . isSymbolicLink <$> getSymbolicLinkStatus f) $ do
			moveAnnex k f
			l <- inRepo $ gitAnnexLink f k
			liftIO $ createSymbolicLink l f
		showEndOk

	cleandirect k = do
		liftIO . nukeFile =<< calcRepo (gitAnnexInodeCache k)
		liftIO . nukeFile =<< calcRepo (gitAnnexMapping k)

cleanup :: CommandCleanup
cleanup = do
	setVersion defaultVersion
	showStart "indirect" ""
	showEndOk
	return True
