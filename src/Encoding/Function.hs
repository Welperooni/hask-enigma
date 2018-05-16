{-# LANGUAGE RecordWildCards, ViewPatterns #-}

module Encoding.Function where

import qualified Data.IntMap as M
import           Data.IntMap (IntMap)
import qualified Data.Vector as V
import           Data.Vector (Vector)
import           Data.Char (chr, ord, toUpper)
import           Data.Maybe (fromMaybe)
import           Data.Either (fromRight)

import           Encoding.Types
import           Encoding.Std
import           Encoding.Util (deconst)

encodeCharacter :: Char -> Vector Part -> Char
encodeCharacter c rotors = go (subtract 65 . ord $ toUpper c) F rotors
  where
    go :: Int -> From -> Vector Part -> Char
    -- if it reached the reflector, turn back
    go n F (deconst -> (Left Reflector{..}, _)) = go (stateR M.! n) B (V.init rotors)
    -- step forward
    go n F (deconst -> (Right Rotor{..}, xs)) = go (forward $ state V.! n) F xs
    -- if the rank is 1, means we hit the first rotor
    go n B (checkRank . V.last -> 1) = chr (n + 65)
    -- step backwards
    go n B xs@(V.last -> Right Rotor{..}) = go (backward $ state V.! n) B (V.init xs)


-- TODO: make it offset rotors to the starting position
buildEnigma :: Maybe Int -> Maybe (Vector Int) -> Maybe (IntMap Int)
      -> Maybe Reflector -> Enigma
buildEnigma amm offsets swaps refl = Enigma rotorsN 
  (fromMaybe stdOffsets offsets)
  (V.snoc (V.take (rotorsN) stdRotors) reflector)
  (fromMaybe stdSwaps swaps)
    where 
      rotorsN = fromMaybe stdAmm amm
      reflector :: Part
      reflector = Left $ fromMaybe stdRefl refl

buildStdEnigma :: Enigma
buildStdEnigma = buildEnigma Nothing Nothing Nothing Nothing

checkRank :: Part -> Int
checkRank (Left _) = 0
checkRank (Right Rotor{..}) = interval

-- N stands for the interval
-- also updates the next one's backward pointing,
-- checks for double-rotate and rotates if needed
-- (messy but it just werks)
rotateRotorN :: Int -> Vector Part -> Vector Part
rotateRotorN n rotors = 
  let rotor1@(Rotor inte clock state) = updateForward $ unPart (n-1)
      -- if the clock hits the new rotation, rotate the previous rotor
      accForClock = if inte > 2 && ((clock+1) `rem` 26 == 0) then
          rotateRotorN (n-1) $ reInsert (n-1) (V.singleton . Right $ moveClock rotor1) rotors
        else reInsert (n-1) (V.singleton . Right $ moveClock rotor1) rotors
      -- update the previous rotor's backward connection
      rotorsNew = if V.length rotors - n /= 1 then
          reInsert n (V.singleton $ Right (updateBackward $ unPart n)) accForClock
        else accForClock
  in rotorsNew
    where
      reInsert n parts vec = V.take (n-1) vec V.++ parts V.++ V.drop (V.length parts) vec
      unPart n = fromRight (error "unPart: hit reflector") (rotors V.! (n-1))

updateBackward :: Rotor -> Rotor
updateBackward rotor = rotor { state=(fmap f (state rotor)) } 
  where
    f (Connection f b) = Connection f $ (b-1) `mod` 26

moveClock :: Rotor -> Rotor
moveClock rotor = rotor { interval = ((interval rotor +1) `rem` 26)}

updateForward :: Rotor -> Rotor
updateForward rotor = rotor{ state=(fmap f (state rotor)) } 
  where
    f (Connection f b) = Connection ((f+1) `mod` 26) b