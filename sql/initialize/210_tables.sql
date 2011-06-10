-- env PGDATABASE=skeleton PGUSER=skeleton_root

-- Centralize the list of all timezones
CREATE TABLE public.timezone (
  id SERIAL,
  name TEXT NOT NULL,
  PRIMARY KEY(id)
);


-- BEGIN: aaa's schema
-- A table housing user-related information where there is no-harm if "a
-- SELECT *'s worth of information" is accessed or updated by a web user.
CREATE TABLE aaa.user_info (
  user_id INT NOT NULL,
  timezone_id INT
);


CREATE TABLE shadow.aaa_email (
  id SERIAL,
  email TEXT NOT NULL,
  user_id INT NOT NULL,
  PRIMARY KEY(id)
);


CREATE TABLE shadow.aaa_email_confirmation_log (
  id SERIAL NOT NULL,
  email_id INT NOT NULL,
  timestamp_sent TIMESTAMP WITH TIME ZONE NOT NULL,
  ttl INTERVAL NOT NULL DEFAULT '8 hours'::INTERVAL,
  confirmation_code UUID NOT NULL,
  confirmed BOOL NOT NULL DEFAULT FALSE,
  ip_address INET,
  timestamp_confirmed TIMESTAMP WITH TIME ZONE,
  CHECK(confirmed = FALSE OR (confirmed = TRUE AND ip_address IS NOT NULL AND timestamp_confirmed IS NOT NULL)),
  CHECK(EXTRACT(TIMEZONE FROM timestamp_sent) = 0.0),
  -- If timestamp_confirmed IS NULL, the CHECK should pass, otherwise make
  -- sure that we stored the data in UTC.
  CHECK(timestamp_confirmed IS NULL OR EXTRACT(TIMEZONE FROM timestamp_confirmed) = 0.0),
  PRIMARY KEY(id)
);


CREATE TABLE shadow.aaa_user (
  id SERIAL,
  hashpass TEXT NOT NULL,
  active BOOL NOT NULL,
  primary_email_id INT NOT NULL,
  registration_utc TIMESTAMP WITH TIME ZONE NOT NULL,
  registration_ip INET NOT NULL,
  max_concurrent_sessions INT NOT NULL DEFAULT 1,
  default_ipv4_mask INT NOT NULL DEFAULT 32,
  default_ipv6_mask INT NOT NULL DEFAULT 128,
  PRIMARY KEY(id),
  CHECK(max_concurrent_sessions >= 0),
  CHECK(EXTRACT(TIMEZONE FROM registration_utc) = 0.0)
);


-- The login attempts table needs a bit of explanation compared to the
-- shadow.aaa_session table. This table is meant to be a pseudo-transient
-- record of user activity (the person). Compare that with aaa_session, which
-- is geared toward the actual session and behavior of sessions.
CREATE TABLE shadow.aaa_login_attempts (
  user_id INT NOT NULL,
  login_utc TIMESTAMP WITH TIME ZONE NOT NULL,
  ip_address INET NOT NULL,
  success BOOL NOT NULL,
  notes TEXT,
  CHECK(success OR (NOT success AND notes IS NOT NULL)),
  CHECK(EXTRACT(TIMEZONE FROM login_utc) = 0.0)
);


-- Backing storage mechanism for session information. Column notes:

-- ip_mask is used to constrain which IP addresses are allowed to use this
-- session id. In IPv4 land, this defaults to 32 (the specific IP address),
-- and in IPv6 land, we default to a 128 bit mask. This is configurable on a
-- per-user basis in the shadow.aaa_user table. If someone requests to rekey
-- a session from an IP address outside of their session_ip_mask, the session
-- will be marked invalid. This is set on a per-user basis for now, however
-- it would be preferrable if there were "network profiles" setup for each
-- user and this setting could be adjusted on a per-profile basis (work vs
-- mobile). The value of moving this setting to a per-network profile basis
-- is that mobile devices have their IP address change, corporate networks,
-- etc. Using sane defaults for each profile would be preferred. For example,
-- a home IP profile is a /32, a corporate profile should also be a /32
-- unless the company has a screwed up network in which case they could use a
-- /24, and nearly all mobile devices connect from the rediculously huge /9
-- network from WDSPCo (i.e. NETBLK-CDPD-B) that can probably be assumed to
-- be only /24's without much harm. A larger problem that I'd rather not
-- re-tackle at this point in time.

-- secure: the session ID is to be transmitted via HTTPS only.

-- valid: marked FALSE when the session expires

-- start_utc is when the session was created and end_utc is the planned
-- expiration date of the session. A particular session_id can not be renewed
-- or have its expiration time extended, however an expired session (within
-- reason), can be used as an authentication source and renew a
-- session_id.

-- end_utc: When a user logs out, end_utc is reset to NOW() and valid is set
-- to FALSE. If end_utc is moved backwards (e.g. to NOW()), the session ID
-- must be invalidated from cache.

-- session_id is generated by skeleton/aaa/__init__.py:gen_session_id()
CREATE TABLE shadow.aaa_session (
  user_id INT NOT NULL,
  ip_mask CIDR NOT NULL,
  secure BOOL NOT NULL DEFAULT TRUE,
  valid BOOL NOT NULL,
  start_utc TIMESTAMP WITH TIME ZONE NOT NULL,
  end_utc TIMESTAMP WITH TIME ZONE NOT NULL,
  session_id TEXT NOT NULL,
  CHECK(start_utc < end_utc),
  CHECK(EXTRACT(TIMEZONE FROM start_utc) = 0.0 AND EXTRACT(TIMEZONE FROM end_utc) = 0.0)
);
