module Craft.Upstart where

import           Craft

import           Control.Lens    hiding (noneOf)
import           Text.Megaparsec

type ServiceName = String

data Service
  = Service
    { _name   :: String
    , _status :: String
    }

makeLenses ''Service


get :: ServiceName -> Craft (Maybe Service)
get sn =
  exec "/sbin/status" [sn] >>= \case
    ExecFail _ -> return Nothing
    ExecSucc r -> Just . Service sn <$> parseExecResult (ExecSucc r) (statusParser sn) (r ^. stdout)


statusParser :: String -> Parsec String String
statusParser sn = do
  void $ string sn >> space >> some (noneOf "/") >> char '/'
  some $ noneOf ","


start :: Service -> Craft ()
start Service{..} = when (_status /= "running") $ exec_ "/sbin/start" [_name]


restart :: Service -> Craft ()
restart Service{..} = exec_ "/sbin/restart" [_name]
