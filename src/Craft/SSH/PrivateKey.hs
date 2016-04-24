module Craft.SSH.PrivateKey where

import           Craft
import           Craft.SSH
import qualified Craft.Directory as Directory
import           Craft.File (file)
import qualified Craft.File as File
import           Craft.File.Mode
import           Craft.User (User)
import qualified Craft.User as User

import Control.Lens

data PrivateKey
  = PrivateKey
    { _user :: User
    , _name :: String
    , _content :: String
    }
  deriving (Eq, Show)
makeLenses ''PrivateKey

path :: PrivateKey -> FilePath
path pk = userDir (pk ^. user) ^. Directory.path </> (pk ^. name)

instance Craftable PrivateKey where
  watchCraft pk = do
    craft_ $ userDir $ pk ^. user
    w <- watchCraft_ $ file (path pk)
                         & File.mode       .~ Mode RW O O
                         & File.ownerID    .~ pk ^. user . User.uid
                         & File.groupID    .~ pk ^. user . User.gid
                         & File.strContent .~ pk ^. content
    return (w, pk)
