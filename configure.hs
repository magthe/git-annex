{- Checks system configuration and generates SysConfig.hs. -}

import System.IO
import System.Cmd
import System.Exit
import System.Directory

type Test = IO Bool
data TestCase = TestCase String String Test
data Config = Config String Bool

instance Show Config where
        show (Config key value) = unlines [
			  key ++ " :: Bool"
			, key ++ " = " ++ show value
		]

tests :: [TestCase]
tests = [
	  TestCase "cp -a" "cp_a" $ testCp "-a"
	, TestCase "cp -p" "cp_p" $ testCp "-p"
	, TestCase "cp --reflink=auto" "cp_reflink_auto" $ testCp "--reflink=auto"
	, TestCase "uuid" "uuid" $ requireCmd "uuid" "uuid"
	, TestCase "xargs -0" "xargs_0" $ requireCmd "xargs -0" "xargs -0 </dev/null"
	, TestCase "rsync" "rsync" $ testCmd "rsync --version >/dev/null"
	]

tmpDir :: String
tmpDir = "tmp"

testFile :: String
testFile = tmpDir ++ "/testfile"

quiet :: String -> String
quiet s = s ++ " >/dev/null 2>&1"

requireCmd :: String -> String -> Test
requireCmd c cmdline = do
	ret <- testCmd $ quiet cmdline
	if ret
		then return True
		else do
			testEnd False
			error $ "** the " ++ c ++ " command is required to use git-annex"

testCp :: String -> Test
testCp option = testCmd $ quiet $ "cp " ++ option ++ " " ++ testFile ++ 
			" " ++ testFile ++ ".new"

testCmd :: String -> Test
testCmd c = do
	ret <- system c
	return $ ret == ExitSuccess

testStart :: String -> IO ()
testStart s = do
	putStr $ "  checking " ++ s ++ "..."
	hFlush stdout

testEnd :: Bool -> IO ()
testEnd r = putStrLn $ " " ++ show r

writeSysConfig :: [Config] -> IO ()
writeSysConfig config = writeFile "SysConfig.hs" body
	where
		body = unlines $ header ++ map show config ++ footer
		header = [
			  "{- Automatically generated by configure. -}"
			, "module SysConfig where"
			, ""
			]
		footer = []

runTests :: [TestCase] -> IO [Config]
runTests [] = return []
runTests ((TestCase tname key t):ts) = do
	testStart tname
	val <- t
	testEnd val
	rest <- runTests ts
	return $ (Config key val):rest

setup :: IO ()
setup = do
	createDirectoryIfMissing True tmpDir
	writeFile testFile "test file contents"

cleanup :: IO ()
cleanup = do
	removeDirectoryRecursive tmpDir

main :: IO ()
main = do
	setup
	config <- runTests tests
	writeSysConfig config
	cleanup
