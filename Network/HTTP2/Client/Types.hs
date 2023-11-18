{-# LANGUAGE RankNTypes #-}

module Network.HTTP2.Client.Types where

import Network.HTTP2.H2

----------------------------------------------------------------

-- | Client type.
type Client a = (forall b. Request -> (Response -> IO b) -> IO b) -> Aux -> IO a

-- | Request from client.
newtype Request = Request OutObj deriving (Show)

-- | Response from server.
newtype Response = Response InpObj deriving (Show)

-- | Additional information.
data Aux = Aux
    { auxPossibleClientStreams :: IO (Maybe Int)
    -- ^ How many streams can be created without blocking.
    -- 'Nothing' means infinity.
    , auxServerMaxStreams :: IO (Maybe Int)
    -- ^ Getting server's SETTINGS_MAX_CONCURRENT_STREAMS.
    --  'Nothing' means no limit.
    }
