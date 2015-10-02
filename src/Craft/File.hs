module Craft.File
( module Craft.File
, setGroup
, setOwner
, getOwner
, getGroup
, getMode
)
where

import           Craft
import           Craft.File.Mode
import           Craft.User (User)
import qualified Craft.User as User
import           Craft.Group (Group)
import qualified Craft.Group as Group
import           Craft.Internal.FileDirectory

import           Control.Monad.Extra (unlessM)
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as B8
import           Data.Maybe (fromJust)

type Path = FilePath

data File
  = File
    { path  :: Path
    , mode  :: Mode
    , owner :: User
    , group :: Group
    , content :: Maybe ByteString
    }
   deriving (Eq, Show)

name :: File -> String
name f = takeFileName $ path f

strContent :: String -> Maybe ByteString
strContent = Just . B8.pack

contentAsString :: File -> String
contentAsString = B8.unpack . fromJust . content

file :: Path -> File
file fp =
  File
  { path  = fp
  , mode  = Mode RW R R
  , owner = User.root
  , group = Group.root
  , content = Nothing
  }

multiple :: [Path] -> Mode -> User -> Group -> Maybe ByteString -> [File]
multiple paths mode owner group content = map go paths
 where
  go path = File path mode owner group content


multipleRootOwned :: [Path] -> Mode -> Maybe ByteString -> [File]
multipleRootOwned paths mode content = map go paths
 where
  go path = (file path) { mode = mode
                        , content = content
                        }

instance Craftable File where
  checker = get . path
  remover = notImplemented "File.remover"
  crafter File{..} = do
    unlessM (exists path) $
      write path ""

    setMode mode path
    setOwner owner path
    setGroup group path

    case content of
      Nothing -> return ()
      Just c -> write path c

write :: Path -> ByteString -> Craft ()
write = fileWrite

exists :: Path -> Craft Bool
exists fp = isSuccess . exitcode <$> exec "/usr/bin/test" ["-f", fp]

get :: Path -> Craft (Maybe File)
get fp = do
  exists' <- exists fp
  if not exists' then
    return Nothing
  else do
    m <- getMode fp
    o <- getOwner fp
    g <- getGroup fp
    content <- fileRead fp
    return . Just $
      File { path    = fp
           , mode    = m
           , owner   = o
           , group   = g
           , content = Just content
           }

md5sum :: Path -> Craft String
md5sum fp = head . words . stdout <$> exec "/usr/bin/md5sum" [fp]
