module Network.GRPC.Util.TimeManager (
    -- * Timeouts
  TimeManager,
  withTimeManager,
  disableTimeout,
  clientIdleTimeoutMicros,
) where

import System.TimeManager qualified as TimeManager

{-------------------------------------------------------------------------------
  Timeouts
-------------------------------------------------------------------------------}

type TimeManager = TimeManager.Manager

-- | Allocate time manager (without any actual timeouts)
--
-- The @http2@ ecosystem relies on a time manager for timeouts; we don't use
-- those timeouts (see disableTimeout), but must still provide a time manager
-- for insecure connections. For secure connections the time manager is
-- allocated in 'Network.Run.Timeout.runTCPServerWithSocket' from @network-run@.
-- In that package it allocates a single manager for the entire server (it
-- allocates the manager before calling accept), so we should do the same in the
-- insecure case for better consistency between the two setups; this also avoids
-- the possibility of leaking managers.
withTimeManager :: (TimeManager -> IO a) -> IO a
withTimeManager = TimeManager.withManager (disableTimeout * 1_000_000)

-- | Disable timeouts in http2/http2-tls
--
-- A value of 0 (or lower) disables timeouts as of @time-manager-0.2.2@.
disableTimeout :: Int
disableTimeout = 0

-- | How long a client connection may sit idle before @http2@ reaps it.
--
-- PULSE FORK. This one is not disabled, because a client that never notices a
-- dead peer never reconnects. It is raised, because @http2@'s own value is too
-- tight for a long-lived stream.
--
-- The timer lives in @http2@'s frame receiver and is tickled on receipt only
-- (@Network.HTTP2.H2.Receiver@), so it measures INBOUND silence: writing to a
-- connection does not hold it open. On expiry the receiver is thrown
-- @ConnectionIsTimeout@, which takes down the whole connection -- and with it
-- every stream multiplexed on it, since a connection's exception is
-- republished to all in-flight calls.
--
-- @http2@ installs 30s ('Network.HTTP2.Client.allocSimpleConfig'). That is
-- only 1.5x Pulse's 20s collector heartbeat, which is the inbound traffic
-- holding an otherwise quiet collector connection open: one late heartbeat
-- and the appliance loses its alarm subscription and its sampling stream.
-- 90s absorbs a few consecutive missed heartbeats while still declaring a
-- genuinely dead peer dead in bounded time.
--
-- Nothing else bounds this on the reverse-gRPC link: Warp's reaper on the
-- hijacked connection tickles on send as well as receive, so the appliance's
-- own writes keep that one quiet indefinitely.
clientIdleTimeoutMicros :: Int
clientIdleTimeoutMicros = 90 * 1_000_000
