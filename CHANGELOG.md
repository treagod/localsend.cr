# Changelog

## [Unreleased]

### Added

- `Identity`: self-signed certificate, created on first use, with the SHA-256
  fingerprint the protocol identifies devices by.
- `Discovery`: multicast announcements with a subnet broadcast fallback, and
  `Found` / `Updated` / `Lost` events on a channel.
- `Client#send`: prepare-upload, per-file tokens, streaming upload, progress.
- `Receiver`: transfers arrive on a channel and wait for `accept` or `reject`.
- Mutual TLS with fingerprint verification in both directions, PIN support with
  a three attempt limit, path traversal protection and collision-safe names.
- Examples for discovering, sending and receiving.

Verified against the official LocalSend app on macOS 26 and iOS: discovery in
both directions, sending a file to it, and receiving a 217 KB PDF from it
byte-for-byte, twice in a row to confirm the session releases and the second
copy lands beside the first instead of on top of it.
