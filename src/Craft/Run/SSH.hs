module Craft.Run.SSH where

import           Control.Exception.Lifted  (bracket)
import           Control.Lens
import           Control.Monad.Logger      (LoggingT)
import           Control.Monad.Reader
import qualified Control.Monad.Trans       as Trans
import qualified Data.ByteString.Char8     as B8
import           Data.List                 (intersperse)
import qualified Data.Map.Strict           as Map
import           Data.Maybe                (fromMaybe)
import           Data.String.Utils         (replace)
import           System.Directory
import           System.Process            (ProcessHandle)
import qualified System.Process            as Process
import qualified System.Process.ByteString as Proc.BS
import           System.Random             hiding (next)

import           Craft.Helpers
import           Craft.Run.Internal
import           Craft.Types


data SSHEnv
  = SSHEnv
    { _sshKey         :: FilePath
    , _sshAddr        :: String
    , _sshPort        :: Int
    , _sshUser        :: String
    , _sshSudo        :: Bool
    , _sshControlPath :: Maybe FilePath
    , _sshOptions     :: [String]
    }
makeLenses ''SSHEnv


connStr :: Optic' (->) (Const String) SSHEnv String
connStr = to (\env -> concat [env ^. sshUser, "@", env ^. sshAddr])


sshEnv :: String -> FilePath -> SSHEnv
sshEnv addr key =
  SSHEnv
  { _sshAddr        = addr
  , _sshPort        = 22
  , _sshKey         = key
  , _sshUser        = "root"
  , _sshSudo        = True
  , _sshControlPath = Nothing
  , _sshOptions     = sshDefaultOptions
  }


sshDefaultOptions :: [String]
sshDefaultOptions =
  [ "UserKnownHostsFile=/dev/null"
  , "StrictHostKeyChecking=no"
  , "LogLevel=ERROR"
  ]


data Session
 = Session
   { _sessionMasterProcHandle :: ProcessHandle
   , _sessionMasterProc       :: Process.CreateProcess
   , _sessionControlPath      :: FilePath
   , _sessionEnv              :: SSHEnv
   , _sessionArgs             :: Args
   }
makeLenses ''Session


prependEachWith :: String -> [String] -> [String]
prependEachWith _    []   = []
prependEachWith flag opts = flag:(intersperse flag opts)


newSession :: SSHEnv -> IO Session
newSession env = do
  defaultControlPath <- (".craft-ssh-session-" ++) . show . abs
                        <$> (randomIO :: IO Int)
  let controlPath = fromMaybe defaultControlPath $ env ^. sshControlPath
  let args =    [ "-p", show $ env ^. sshPort ] -- port
             ++ [ "-i", env ^. sshKey ] -- private key
             ++ prependEachWith "-o"
                  ((env ^. sshOptions)
                   ++ [ "ControlPath=" ++ controlPath
                      , "BatchMode=yes" -- never prompt for a password
                      ])
  let masterProc = (Process.proc "ssh"
                      (args
                       ++ (prependEachWith "-o" [ "ControlMaster=yes"
                                                , "ControlPersist=yes" ])
                       ++ [env ^. connStr]))
                    { Process.std_in  = Process.NoStream
                    , Process.std_out = Process.NoStream
                    , Process.std_err = Process.NoStream
                    }
  (_, _, _, ph) <- Process.createProcess masterProc
  return Session { _sessionEnv = env
                 , _sessionMasterProc = masterProc
                 , _sessionMasterProcHandle = ph
                 , _sessionControlPath = controlPath
                 , _sessionArgs = args
                 }


closeSession :: Session -> IO ()
closeSession Session{..} = do
  Process.terminateProcess _sessionMasterProcHandle
  whenM (doesFileExist _sessionControlPath) $
    removeFile _sessionControlPath


withSession :: SSHEnv -> (Session -> LoggingT IO a) -> LoggingT IO a
withSession env =
  bracket (Trans.lift $ newSession env)
          (Trans.lift . closeSession)


runSSHSession :: Session -> CraftRunner
runSSHSession session =
  CraftRunner
  { runExec =
      \ce command args ->
        execProc $ sshProc session ce command args
  , runExec_ =
      \ce command args ->
        let p = sshProc session ce command args
        in execProc_ (unwords (command:args)) p
  , runFileRead =
      \fp -> do
        let p = sshProc session craftEnvOverride "cat" [fp]
        (ec, content, stderr') <-
          Trans.lift $ Proc.BS.readCreateProcessWithExitCode p ""
        unless (isSuccessCode ec) $
          $craftError $ "Failed to read file '"++ fp ++"': " ++ B8.unpack stderr'
        return content
  , runFileWrite =
      \fp content -> do
        let p = sshProc session craftEnvOverride "tee" [fp]
        (ec, _, stderr') <-
          Trans.lift $ Proc.BS.readCreateProcessWithExitCode p content
        unless (isSuccessCode ec) $
          $craftError $ "Failed to write file '" ++ fp ++ "': " ++ B8.unpack stderr'
  , runSourceFile =
      \src dest ->
        let p = Process.proc "rsync"
                  (   [ "--quiet" -- suppress non-error messages
                      , "--checksum" -- skip based on checksum, not mod-time & size
                      , "--compress" -- compress file data during the transfer
                        -- specify the remote shell to use
                      , "--rsh=ssh " ++ unwords (session ^. sessionArgs)]
                  ++ (if session ^. sessionEnv . sshSudo
                          then ["--super", "--rsync-path=sudo rsync"]
                          else [])
                  ++ [ src , (session ^. sessionEnv . connStr) ++ ":" ++ dest ])
        in execProc_ (showProc p) p
  }

craftEnvOverride :: CraftEnv
craftEnvOverride =
  craftEnv noPackageManager
  & craftExecEnv .~ Map.empty
  & craftExecCWD .~ "/"


sshProc :: Session -> CraftEnv -> Command -> Args
        -> Process.CreateProcess
sshProc session ce command args =
  Process.proc "ssh" $ session ^. sessionArgs
                    ++ (prependEachWith "-o" [ "ControlMaster=auto"
                                             , "ControlPersist=no"
                                             ])
                    ++ [ session ^. sessionEnv . connStr
                       , fullExecStr
                       ]
 where
  fullExecStr :: String
  fullExecStr = unwords (sudoArgs ++ ["sh", "-c", "'", shellStr, "'"])

  sudoArgs :: [String]
  sudoArgs = if session ^. sessionEnv . sshSudo
              then ["sudo", "-n", "-H"]
              else []

  shellStr :: String
  shellStr = unwords (cdArgs ++ execEnvArgs ++ (command : map (escape specialChars) args))

  specialChars :: [String]
  specialChars = [" ", "*", "$", "'"]

  execEnvArgs :: [String]
  execEnvArgs = map (escape specialChars) . renderEnv $ ce ^. craftExecEnv

  cdArgs :: [String]
  cdArgs = ["cd", ce ^. craftExecCWD, ";"]

  escape :: [String] -> String -> String
  escape = recur backslash

  recur _ []     s = s
  recur f (a:as) s = recur f as $ f a s

  backslash x = replace x ('\\':x)


renderEnv :: ExecEnv -> [String]
renderEnv = map (\(k, v) -> k++"="++v) . Map.toList
