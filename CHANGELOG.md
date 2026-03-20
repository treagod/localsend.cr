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

Verified against the official LocalSend app: discovery in both directions,
sending a file to it, and receiving one from it.
