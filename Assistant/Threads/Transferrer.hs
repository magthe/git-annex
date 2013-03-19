{- git-annex assistant data transferrer thread
 -
 - Copyright 2012 Joey Hess <joey@kitenet.net>
 -
 - Licensed under the GNU GPL version 3 or higher.
 -}

module Assistant.Threads.Transferrer where

import Assistant.Common
import Assistant.DaemonStatus
import Assistant.TransferQueue
import Assistant.TransferSlots
import Assistant.Alert
import Assistant.Commits
import Assistant.Drop
import Logs.Transfer
import Logs.Location
import Annex.Content
import qualified Remote
import qualified Types.Remote as Remote
import qualified Git
import Types.Key
import Locations.UserConfig
import Assistant.Threads.TransferWatcher
import Annex.Wanted

import System.Process (create_group)

{- Dispatches transfers from the queue. -}
transfererThread :: NamedThread
transfererThread = namedThread "Transferrer" $ do
	program <- liftIO readProgramFile
	forever $ inTransferSlot $
		maybe (return Nothing) (uncurry $ startTransfer program)
			=<< getNextTransfer notrunning
  where
	{- Skip transfers that are already running. -}
	notrunning = isNothing . startedTime

{- By the time this is called, the daemonstatus's currentTransfers map should
 - already have been updated to include the transfer. -}
startTransfer
	:: FilePath
	-> Transfer
	-> TransferInfo
	-> Assistant (Maybe (Transfer, TransferInfo, Assistant ()))
startTransfer program t info = case (transferRemote info, associatedFile info) of
	(Just remote, Just file) 
		| Git.repoIsLocalUnknown (Remote.repo remote) -> do
			-- optimisation for removable drives not plugged in
			liftAnnex $ recordFailedTransfer t info
			void $ removeTransfer t
			return Nothing
		| otherwise -> ifM (liftAnnex $ shouldTransfer t info)
			( do
				debug [ "Transferring:" , describeTransfer t info ]
				notifyTransfer
				return $ Just (t, info, transferprocess remote file)
			, do
				debug [ "Skipping unnecessary transfer:",
					describeTransfer t info ]
				void $ removeTransfer t
				finishedTransfer t (Just info)
				return Nothing
			)
	_ -> return Nothing
  where
	direction = transferDirection t
	isdownload = direction == Download

	transferprocess remote file = void $ do
		(_, _, _, pid)
			<- liftIO $ createProcess
				(proc program $ toCommand params)
					{ create_group = True }
		{- Alerts are only shown for successful transfers.
		 - Transfers can temporarily fail for many reasons,
		 - so there's no point in bothering the user about
		 - those. The assistant should recover.
		 -
		 - After a successful upload, handle dropping it from
		 - here, if desired. In this case, the remote it was
		 - uploaded to is known to have it.
		 -
		 - Also, after a successful transfer, the location
		 - log has changed. Indicate that a commit has been
		 - made, in order to queue a push of the git-annex
		 - branch out to remotes that did not participate
		 - in the transfer.
		 -}
		whenM (liftIO $ (==) ExitSuccess <$> waitForProcess pid) $ do
			void $ addAlert $ makeAlertFiller True $
				transferFileAlert direction True file
			unless isdownload $
				handleDrops
					("object uploaded to " ++ show remote)
					True (transferKey t)
					(associatedFile info)
					(Just remote)
			recordCommit
	  where
		params =
			[ Param "transferkey"
			, Param "--quiet"
			, Param $ key2file $ transferKey t
			, Param $ if isdownload
				then "--from"
				else "--to"
			, Param $ Remote.name remote
			, Param "--file"
			, File file
			]

{- Called right before a transfer begins, this is a last chance to avoid
 - unnecessary transfers.
 -
 - For downloads, we obviously don't need to download if the already
 - have the object.
 -
 - Smilarly, for uploads, check if the remote is known to already have
 - the object.
 -
 - Also, uploads get queued to all remotes, in order of cost.
 - This may mean, for example, that an object is uploaded over the LAN
 - to a locally paired client, and once that upload is done, a more
 - expensive transfer remote no longer wants the object. (Since
 - all the clients have it already.) So do one last check if this is still
 - preferred content.
 -
 - We'll also do one last preferred content check for downloads. An
 - example of a case where this could be needed is if a download is queued
 - for a file that gets moved out of an archive directory -- but before
 - that download can happen, the file is put back in the archive.
 -}
shouldTransfer :: Transfer -> TransferInfo -> Annex Bool
shouldTransfer t info
	| transferDirection t == Download =
		(not <$> inAnnex key) <&&> wantGet True file
	| transferDirection t == Upload = case transferRemote info of
		Nothing -> return False
		Just r -> notinremote r
			<&&> wantSend True file (Remote.uuid r)
	| otherwise = return False
  where
	key = transferKey t
	file = associatedFile info

	{- Trust the location log to check if the remote already has
	 - the key. This avoids a roundtrip to the remote. -}
	notinremote r = notElem (Remote.uuid r) <$> loggedLocations key