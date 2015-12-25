module Craft.Config.Yaml where

import Craft
import Craft.File (File)
import qualified Craft.File as File
import Craft.File.Mode
import Craft.User (UserID)
import Craft.Group (GroupID)
import qualified Data.ByteString.Char8 as B8

import Control.Lens
import Data.Yaml


data Config cfgs
  = Config
    { path    :: FilePath
    , mode    :: Mode
    , ownerID :: UserID
    , groupID :: GroupID
    , configs :: cfgs
    }
    deriving (Eq)


instance ToJSON cfg => Show (Config cfg) where
  show f = "Yaml.Config " ++
           "{ path = " ++ show (path f) ++
           ", mode = " ++ show (mode f) ++
           ", ownerID = " ++ show (ownerID f) ++
           ", groupID = " ++ show (groupID f) ++
           ", configs = \"" ++ B8.unpack (encode (configs f)) ++ "\"" ++
           "}"


config :: FilePath -> cfgs -> Config cfgs
config fp cfgs = let f = File.file fp
                 in Config { path = f ^. File.path
                           , mode = f ^. File.mode
                           , ownerID = f ^. File.ownerID
                           , groupID = f ^. File.groupID
                           , configs = cfgs
                           }


configFromFile :: FromJSON cfgs => File -> Config cfgs
configFromFile f =
  Config { path    = f ^. File.path
         , mode    = f ^. File.mode
         , ownerID = f ^. File.ownerID
         , groupID = f ^. File.groupID
         , configs =
             case f ^. File.content of
               Nothing -> error $ "Unmanaged Yaml config: " ++ f ^. File.path
               Just bs -> case decodeEither bs of
                            Left err -> error $ "Failed to parse "
                                              ++ f ^. File.path ++ " : " ++ err
                            Right x  -> x
         }


fileFromConfig :: ToJSON cfgs => Config cfgs -> File
fileFromConfig cfg =
  File.file (path cfg) & File.mode    .~ mode cfg
                       & File.ownerID .~ ownerID cfg
                       & File.groupID .~ groupID cfg
                       & File.content ?~ encode (configs cfg)


get :: (FromJSON cfgs) => FilePath -> Craft (Maybe (Config cfgs))
get fp = fmap configFromFile <$> File.get fp


instance (Eq cfg, ToJSON cfg, FromJSON cfg) => Craftable (Config cfg) where
  watchCraft cfg = do
    w <- watchCraft_ $ fileFromConfig cfg
    return (w, cfg)
