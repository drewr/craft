module Craft.File.Mode
( Mode(..)
, ModeSet(..)
, setMode
, toFileMode
, toMode
, toHuman
, fileModeFromString
, fromString
, testFileMode
)
where

import Craft.Internal

import Data.Bits ((.|.), (.&.))
import Data.Char (digitToInt)
import Data.List
import Data.Maybe
import System.Posix

data Mode
  = Mode ModeSet ModeSet ModeSet
  deriving (Eq, Show)

toHuman :: Mode -> String
toHuman (Mode u g o) =
  modeSetToHuman u ++ modeSetToHuman g ++ s2t (modeSetToHuman o)
 where
  s2t = map tr
  tr 's' = 't'
  tr 'S' = 'T'
  tr   c = c

data ModeSet
 = O
 | R
 | W
 | X
 | S
 | RW
 | RX
 | RS
 | WX
 | WS
 | XS
 | RWX
 | RWS
 | RXS
 | WXS
 | RWXS
 deriving (Eq, Enum, Show)

toOctalString :: Mode -> String
toOctalString (Mode u g o) =
  concatMap show $ stickies : map modeSetToOctal l
 where
  stickies = sum $ zipWith (\n m -> n * modeSetToOctalSticky m) [4,2,1] l
  l = [u,g,o]

modeSetToOctal :: ModeSet -> Int
modeSetToOctal O    = 0
modeSetToOctal R    = 4
modeSetToOctal W    = 2
modeSetToOctal X    = 1
modeSetToOctal S    = 0
modeSetToOctal RW   = 6
modeSetToOctal RX   = 5
modeSetToOctal RS   = 4
modeSetToOctal WX   = 3
modeSetToOctal WS   = 2
modeSetToOctal XS   = 1
modeSetToOctal RWX  = 7
modeSetToOctal RWS  = 6
modeSetToOctal RXS  = 5
modeSetToOctal WXS  = 3
modeSetToOctal RWXS = 7

modeSetToOctalSticky :: ModeSet -> Int
modeSetToOctalSticky O    = 0
modeSetToOctalSticky R    = 0
modeSetToOctalSticky W    = 0
modeSetToOctalSticky X    = 0
modeSetToOctalSticky S    = 1
modeSetToOctalSticky RW   = 0
modeSetToOctalSticky RX   = 0
modeSetToOctalSticky RS   = 1
modeSetToOctalSticky WX   = 0
modeSetToOctalSticky WS   = 1
modeSetToOctalSticky XS   = 1
modeSetToOctalSticky RWX  = 0
modeSetToOctalSticky RWS  = 1
modeSetToOctalSticky RXS  = 1
modeSetToOctalSticky WXS  = 1
modeSetToOctalSticky RWXS = 1

modeSetToHuman :: ModeSet -> String
modeSetToHuman O    = "---"
modeSetToHuman R    = "r--"
modeSetToHuman W    = "-w-"
modeSetToHuman X    = "--x"
modeSetToHuman S    = "--S"
modeSetToHuman RW   = "rw-"
modeSetToHuman RX   = "r-x"
modeSetToHuman RS   = "r-S"
modeSetToHuman WX   = "-wx"
modeSetToHuman WS   = "-wS"
modeSetToHuman XS   = "--s"
modeSetToHuman RWX  = "rwx"
modeSetToHuman RWS  = "rwS"
modeSetToHuman RXS  = "r-s"
modeSetToHuman WXS  = "-ws"
modeSetToHuman RWXS = "rws"

fromString :: String -> Mode
fromString = toMode . fileModeFromString . filter (`elem` ['0'..'7'])

fileModeFromString :: String -> FileMode
fileModeFromString [] = error "Cannot get Mode from empty string."
fileModeFromString s@[_] = error $ "Mode `" ++ s ++ "` not long enough."
fileModeFromString s@[_,_] = error $ "Mode `" ++ s ++ "` not long enough."
fileModeFromString [u,g,o] =
  fromIntegral $ digitToInt u * (8*8) .|. digitToInt g * 8 .|. digitToInt o
fileModeFromString [s,u,g,o] =
  fromIntegral $ digitToInt s * (8*8*8) .|. digitToInt u * (8*8) .|. digitToInt g * 8 .|. digitToInt o
fileModeFromString s = error $ "Mode `" ++ s ++ "` is too long"

setMode :: Mode -> FilePath -> Craft ()
setMode m fp = exec_ "/bin/chmod" [toOctalString m, fp]

toFileMode :: Mode -> FileMode
toFileMode (Mode u g o)
  = uFM u .|. gFM g .|. oFM o

toMode :: FileMode -> Mode
toMode fm = Mode ownerSet groupSet otherSet
  where
    convertSet f m =
      case find (\t -> m == f t) [O ..] of
        Nothing -> error $ "toMode: Unsupported mode: " ++ show m
        Just r -> r
    ownerSet = convertSet uFM (fm .&. (ownerModes .|. uS))
    groupSet = convertSet gFM (fm .&. (groupModes .|. gS))
    otherSet = convertSet oFM (fm .&. (otherModes .|. oT))


----------------------------------------
--   ____       _            _        --
--  |  _ \ _ __(_)_   ____ _| |_ ___  --
--  | |_) | '__| \ \ / / _` | __/ _ \ --
--  |  __/| |  | |\ V / (_| | ||  __/ --
--  |_|   |_|  |_| \_/ \__,_|\__\___| --
----------------------------------------

uR, uW, uX, uS :: FileMode
uR = ownerReadMode
uW = ownerWriteMode
uX = ownerExecuteMode
uS = setUserIDMode

uFM :: ModeSet -> FileMode
uFM O    = nullFileMode
uFM R    = uR
uFM W    = uW
uFM X    = uX
uFM S    = uS
uFM RW   = uR .|. uW
uFM RX   = uR .|.        uX
uFM RS   = uR .|.               uS
uFM WX   =        uW .|. uX
uFM WS   =        uW .|.        uS
uFM XS   =               uX .|. uS
uFM RWX  = uR .|. uW .|. uX
uFM RWS  = uR .|. uW .|.        uS
uFM RXS  = uR .|.        uX .|. uS
uFM WXS  =        uW .|. uX .|. uS
uFM RWXS = uR .|. uW .|. uX .|. uS


gR, gW, gX, gS :: FileMode
gR = groupReadMode
gW = groupWriteMode
gX = groupExecuteMode
gS = setGroupIDMode

gFM :: ModeSet -> FileMode
gFM O    = nullFileMode
gFM R    = gR
gFM W    = gW
gFM X    = gX
gFM S    = gS
gFM RW   = gR .|. gW
gFM RX   = gR .|.        gX
gFM RS   = gR .|.               gS
gFM WX   =        gW .|. gX
gFM WS   =        gW .|.        gS
gFM XS   =               gX .|. gS
gFM RWX  = gR .|. gW .|. gX
gFM RWS  = gR .|. gW .|.        gS
gFM RXS  = gR .|.        gX .|. gS
gFM WXS  =        gW .|. gX .|. gS
gFM RWXS = gR .|. gW .|. gX .|. gS


oR, oW, oX, oT :: FileMode
oR = otherReadMode
oW = otherWriteMode
oX = otherExecuteMode
oT = (512)

oFM :: ModeSet -> FileMode
oFM O    = nullFileMode
oFM R    = oR
oFM W    = oW
oFM X    = oX
oFM S    = oT
oFM RW   = oR .|. oW
oFM RX   = oR .|.        oX
oFM RS   = oR .|.               oT
oFM WX   =        oW .|. oX
oFM WS   =        oW .|.        oT
oFM XS   =               oX .|. oT
oFM RWX  = oR .|. oW .|. oX
oFM RWS  = oR .|. oW .|.        oT
oFM RXS  = oR .|.        oX .|. oT
oFM WXS  =        oW .|. oX .|. oT
oFM RWXS = oR .|. oW .|. oX .|. oT


testFileMode :: IO Bool
testFileMode = do
  rs <- mapM output list
  return . null $ catMaybes rs
 where
  list = [(s, u, g, o) | o <- range
                       , g <- range
                       , u <- range
                       , s <- range
                       ]
  range = [0..7]
  output (s, u, g, o) = do
    let x = s * (8*8*8) .|. u * (8*8) .|. g * 8 .|. o
    let str = concatMap show [s, u, g, o]
    let mode = toMode x
    let fmode = toFileMode mode
    if toFileMode mode /= x || toMode fmode /= mode then do
      putStrLn $ str ++ ": toMode " ++ show x ++ " == " ++ show mode ++ "| toFileMode . toMode == " ++ show (toMode fmode)
      return $ Just str
    else
      return Nothing
