module Restyled.Prelude
    (
    -- * Errors
      fromJustNoteM
    , fromLeftM
    , untryIO

    -- * Persist
    , SqlEntity
    , overEntity
    , replaceEntity
    , selectFirstT
    , getT
    , getEntityT
    , getByT

    -- * ExceptT
    , bimapMExceptT

    -- * Bufunctor
    , both

    -- * IO
    , setLineBuffering

    -- * Formatting
    , pluralize
    , pluralize'

    -- * Text
    , decodeUtf8

    -- * Re-exports
    , module X
    )
where

import RIO as X hiding (Handler, first, second)

import Control.Error.Util as X
    (exceptT, hoistMaybe, hush, hushT, note, noteT, (??))
import Control.Monad.Except as X
import Control.Monad.Extra as X (fromMaybeM, partitionM)
import Control.Monad.Logger as X
    (logDebugN, logErrorN, logInfoN, logOtherN, logWarnN)
import Control.Monad.Trans.Maybe as X
import Data.Aeson as X hiding (Result(..))
import Data.Aeson.Casing as X
import Data.Bifunctor as X (Bifunctor, bimap, first, second)
import Data.Bitraversable as X (bimapM)
import Data.Char as X (isSpace, toLower)
import Data.Either as X (fromLeft, fromRight)
import Data.Functor.Syntax as X ((<$$>))
import Data.List.Extra as X (sortOn)
import Data.Proxy as X
import Data.Text as X (pack, unpack)
import Database.Persist as X
import Database.Persist.JSONB as X
import Database.Persist.Sql as X (SqlBackend)
import RIO.DB as X
import RIO.List as X (headMaybe, partition)
import RIO.Logger as X
import RIO.Process as X
import RIO.Process.Follow as X
import RIO.Redis as X
import RIO.Time as X
import SVCS.GitHub as X
import SVCS.Names as X
import SVCS.Payload as X
import Web.PathPieces as X

import qualified Data.Text.Lazy as TL
import Formatting (format, (%))
import Formatting.Formatters (int, plural)

fromJustNoteM :: MonadIO m => String -> Maybe a -> m a
fromJustNoteM msg = fromMaybeM (throwString msg) . pure

fromLeftM :: Monad m => (a -> m b) -> m (Either a b) -> m b
fromLeftM f me = either f pure =<< me

-- | Take an @'IO' ('Either' e a)@ and eliminate via @'throwIO'@
--
-- This effectively reverses @'try'@.
--
untryIO :: (MonadIO m, Exception e) => IO (Either e a) -> m a
untryIO = fromLeftM throwIO . liftIO

type SqlEntity a = (PersistEntity a, PersistEntityBackend a ~ SqlBackend)

overEntity :: Entity a -> (a -> a) -> Entity a
overEntity e f = e { entityVal = f $ entityVal e }

replaceEntity
    :: (MonadIO m, SqlEntity a) => Entity a -> SqlPersistT m (Entity a)
replaceEntity e@(Entity k v) = e <$ replace k v

selectFirstT
    :: (MonadIO m, SqlEntity a)
    => [Filter a]
    -> [SelectOpt a]
    -> MaybeT (SqlPersistT m) (Entity a)
selectFirstT x = MaybeT . selectFirst x

getT :: (MonadIO m, SqlEntity a) => Key a -> MaybeT (SqlPersistT m) a
getT = MaybeT . get

getEntityT
    :: (MonadIO m, SqlEntity a) => Key a -> MaybeT (SqlPersistT m) (Entity a)
getEntityT = MaybeT . getEntity

getByT
    :: (MonadIO m, SqlEntity a) => Unique a -> MaybeT (SqlPersistT m) (Entity a)
getByT = MaybeT . getBy

bimapMExceptT
    :: Monad m => (e -> m f) -> (a -> m b) -> ExceptT e m a -> ExceptT f m b
bimapMExceptT f g (ExceptT m) = ExceptT $ h =<< m
  where
    h (Left e) = Left <$> f e
    h (Right a) = Right <$> g a

both :: Bifunctor p => (a -> b) -> p a a -> p b b
both f = bimap f f

-- | Set output handles to line buffering
--
-- Required to ensure container logs are visible immediately.
--
setLineBuffering :: MonadIO m => m ()
setLineBuffering = do
    hSetBuffering stdout LineBuffering
    hSetBuffering stderr LineBuffering

pluralize
    :: TL.Text -- ^ Singular
    -> TL.Text -- ^ Plural
    -> Int -- ^ Amount
    -> TL.Text
pluralize s p n = format (int % " " % plural s p) n n

-- | @'pluralize'@ for strict @'Text'@
pluralize'
    :: Text -- ^ Singular
    -> Text -- ^ Plural
    -> Int -- ^ Amount
    -> Text
pluralize' s p = TL.toStrict . pluralize (TL.fromStrict s) (TL.fromStrict p)

decodeUtf8 :: ByteString -> Text
decodeUtf8 = decodeUtf8With lenientDecode
