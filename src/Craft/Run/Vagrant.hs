module Craft.Run.Vagrant where

import           Control.Lens
import           Control.Monad.IO.Class (liftIO)
import           Control.Monad.Logger   (LoggingT)
import qualified Control.Monad.Trans    as Trans
import qualified Data.Map.Strict        as Map
import           Data.Maybe             (fromMaybe)
import qualified System.Directory
import qualified System.Environment
import           System.Posix.User      (getRealUserID)

import           Craft
import           Craft.Config.SSH       (SSHConfig (..), cfgLookup, parser)


data VagrantSettings
  = VagrantSettings
    { vagrantUp  :: Bool
    , vagrantBox :: String
    }


vagrantSettings :: VagrantSettings
vagrantSettings =
  VagrantSettings
  { vagrantUp = False
  , vagrantBox = "default"
  }


runCraftVagrant :: VagrantSettings -> CraftEnv -> Craft a -> LoggingT IO a
runCraftVagrant settings env configs = do
  uid' <- liftIO getRealUserID
  let box = vagrantBox settings
  sysEnvVars <- Trans.lift System.Environment.getEnvironment
  cwd <- parseAbsDir =<< Trans.lift System.Directory.getCurrentDirectory
  -- vagrant ssh-config
  sshcfg <-
    runCraft
      runLocal
      (craftEnv (env ^. craftPackageManager)
       & craftExecEnvVars .~ Map.fromList sysEnvVars
       & craftCWD     .~ cwd
       & craftUserID  .~ UserID (fromIntegral uid'))
      $ do
        when (vagrantUp settings) $ exec_ "vagrant" ["up", box]
        SSHConfig <$> parseExecStdout parser "vagrant" ["ssh-config", box]
  let addr = cfgLookupOrError box "hostname" sshcfg
  let port = read $ cfgLookupOrError box "port" sshcfg
  let user = cfgLookupOrError box "user" sshcfg
  key <- parseAbsFile $ cfgLookupOrError box "identityfile" sshcfg
  -- vagrant ssh
  withSession
    (sshEnv user addr key
     & sshPort .~ port)
    $ \session ->
        runCraft
          (runSSHSession session)
          env
          configs


cfgLookupOrError :: String -> String -> SSHConfig -> String
cfgLookupOrError box name sshcfg =
  fromMaybe
    (error $ "'"++name++"' not found in output of 'vagrant ssh-config "++box++"'")
    (cfgLookup box name sshcfg)
