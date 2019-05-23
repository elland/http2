module Network.HTTP2.Server.API where

import Data.ByteString.Builder (Builder)
import Data.IORef (IORef)
import qualified Network.HTTP.Types as H
import qualified System.TimeManager as T

import Imports
import Network.HPACK
import Network.HTTP2

-- | HTTP/2 server configuration.
data Config = Config {
      confWriteBuffer :: Buffer
    , confBufferSize  :: BufferSize
    , confSendAll     :: ByteString -> IO ()
    , confReadN       :: Int -> IO ByteString
    , confPositionReadMaker :: PositionReadMaker
    }

----------------------------------------------------------------

-- | HTTP\/2 server takes a HTTP request, should
--   generate a HTTP response and push promises, then
--   should give them to the sending function.
--   The sending function would throw exceptions so that
--   they can be logged.
type Server = Request -> Aux -> (Response -> [PushPromise] -> IO ()) -> IO ()

-- | HTTP request.
data Request = Request {
    requestHeaders   :: HeaderTable   -- ^ Accessor for request headers.
  , requestBodySize  :: Maybe Int     -- ^ Accessor for body length specified in content-length:.
  , requestBody      :: IO ByteString -- ^ Accessor for body.
  , requestTrailers_ :: IORef (Maybe HeaderTable)
  }

-- | Additional information.
data Aux = Aux {
    -- | Time handle for the worker processing this request and response.
    auxTimeHandle :: T.Handle
  }

-- | HTTP response.
data Response = Response {
    responseStatus   :: H.Status          -- ^ Accessor for response status.
  , responseHeaders  :: H.ResponseHeaders -- ^ Accessor for response header.
  , responseBody     :: ResponseBody      -- ^ Accessor for response body.
  , responseTrailers :: TrailersMaker     -- ^ Accessor for response trailers maker.
  }

-- | HTTP response body.
data ResponseBody = RspNoBody
                  -- | Streaming body takes a write action and a flush action.
                  | RspStreaming ((Builder -> IO ()) -> IO () -> IO ())
                  | RspBuilder Builder
                  | RspFile FileSpec

-- | Trailers maker. A chunks of the response body is passed
--   with 'Just'. The maker should update internal state
--   with the 'ByteString' and return the next trailers maker.
--   When response body reaches its end,
--   'Nothing' is passed and the maker should generate
--   trailers. An example:
--
--   > {-# LANGUAGE BangPatterns #-}
--   > import Data.ByteString (ByteString)
--   > import qualified Data.ByteString.Char8 as C8
--   > import Crypto.Hash (Context, SHA1) -- cryptonite
--   > import qualified Crypto.Hash as CH
--   >
--   > -- Strictness is important for Context.
--   > trailersMaker :: Context SHA1 -> Maybe ByteString -> IO NextTrailersMaker
--   > trailersMaker ctx Nothing = return $ Trailers [("X-SHA1", sha1)]
--   >   where
--   >     !sha1 = C8.pack $ show $ CH.hashFinalize ctx
--   > trailersMaker ctx (Just bs) = return $ NextTrailersMaker $ trailersMaker ctx'
--   >   where
--   >     !ctx' = CH.hashUpdate ctx bs
--
--   Usage example:
--
--   > let h2rsp = responseFile ...
--   >     maker = trailersMaker (CH.hashInit :: Context SHA1)
--   >     h2rsp' = setResponseTrailersMaker h2rsp maker
--
type TrailersMaker = Maybe ByteString -> IO NextTrailersMaker

-- | Either the next trailers maker or final trailers.
data NextTrailersMaker = NextTrailersMaker !TrailersMaker
                       | Trailers H.ResponseHeaders

-- | HTTP/2 push promise or sever push.
--   Pseudo REQUEST headers in push promise is automatically generated.
--   Then, a server push is sent according to 'promiseResponse'.
data PushPromise = PushPromise {
    -- | Accessor for a URL path in a push promise (a virtual request from a server).
    --   E.g. \"\/style\/default.css\".
      promiseRequestPath :: ByteString
    -- | Accessor for response actually pushed from a server.
    , promiseResponse    :: Response
    -- | Accessor for response weight.
    , promiseWeight      :: Weight
    }

----------------------------------------------------------------

-- | File specification.
data FileSpec = FileSpec FilePath FileOffset ByteCount deriving (Eq, Show)

-- | Offset for file.
type FileOffset = Int64
-- | How many bytes to read
type ByteCount = Int64

----------------------------------------------------------------

-- | Position read for files.
type PositionRead = FileOffset -> ByteCount -> Buffer -> IO ByteCount

-- | Manipulating a file resource.
data Sentinel =
    -- | Closing a file resource. Its refresher is automatiaclly generated by
    --   the internal timer.
    Closer (IO ())
    -- | Refreshing a file resource while reading.
    --   Closing the file must be done by its own timer or something.
  | Refresher (IO ())

-- | Making a position read and its closer.
type PositionReadMaker = FilePath -> IO (PositionRead, Sentinel)
