# localsend.cr

The [LocalSend](https://localsend.org) protocol (v2) for Crystal: find devices on the
local network, send files to them and receive files from them, over mutual TLS.

Interoperable with the official LocalSend app — discovery, sending and receiving are
all verified against it, not just against itself.

## Installation

```yaml
dependencies:
  localsend:
    github: treagod/localsend.cr
```

Then `shards install`.

Requires Crystal >= 1.19.

## Usage

Everything starts with an identity. It holds the alias other devices see and the TLS
certificate that *is* this device's identity — LocalSend has no certificate authority,
so a device is recognised by the SHA-256 of its certificate. The certificate is created
on first use and reused afterwards; you choose where it lives.

```crystal
require "localsend"

identity = LocalSend::Identity.load_or_create(Path["~/.config/myapp/localsend"],
  alias: "Crystal App", device_model: "Crystal", device_type: :desktop)
```

### Finding devices

```crystal
discovery = LocalSend::Discovery.new(identity)
spawn discovery.run

loop do
  case event = discovery.events.receive
  when LocalSend::Discovery::Found   then puts "found #{event.device.alias}"
  when LocalSend::Discovery::Updated then puts "#{event.device.alias} moved"
  when LocalSend::Discovery::Lost    then puts "#{event.device.alias} is gone"
  end
end
```

`discovery.wait_for("treagod", 5.seconds)` blocks until a device with that alias (or
address) turns up, which is the usual way to get a `Device` for sending.

### Sending

```crystal
client = LocalSend::Client.new(identity)

client.send(device, Path["photo.jpg"]) do |progress|
  puts "#{progress.percent}%"
end
```

`#send` blocks until the transfer finishes and raises on failure — `RejectedError` if
the other side says no, `PinError` if it wants a PIN, `FingerprintMismatchError` if its
certificate is not the one it announced. Nothing is sent before that check passes.
Wrap it in `spawn` if you want it in the background; the library does not decide that
for you.

### Receiving

```crystal
receiver = LocalSend::Receiver.new(identity, pin: "123456")
spawn receiver.run

loop do
  transfer = receiver.incoming.receive
  puts "#{transfer.device.alias} wants to send #{transfer.files.size} file(s)"

  transfer.accept(Path["./received"])   # or transfer.reject
end
```

The request stays parked until you decide, so a UI can take its time asking. No
decision within five minutes counts as a rejection.

## What it does for you

- **Identity checking in both directions.** Every connection compares the certificate
  the peer presents against the fingerprint it announced. Hashes are normalized first —
  the official app spells them uppercase, OpenSSL lowercase.
- **Safe file names.** A sender cannot escape the destination directory with `../`, and
  existing files are never overwritten: `report.pdf` becomes `report (1).pdf`.
- **Truncated transfers are discarded**, not left half-written.
- **PIN with a limit.** Three wrong attempts and further tries are refused.
- **Multicast fallback.** If multicast announcements fail, discovery retries through
  subnet broadcast.

## Examples

```bash
crystal run examples/discover.cr -- --port 53318
crystal run examples/send.cr     -- --device treagod test.txt
crystal run examples/receive.cr  -- --out ./received --pin 123456
```

Use `--port` when the official app is running on the same machine: it holds 53317.

## Development

```bash
crystal spec                  # unit specs plus a real client-to-receiver transfer
crystal tool format --check src spec examples
```

## Contributing

1. Fork it (<https://github.com/treagod/localsend.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- Marvin Ahlgrimm - creator and maintainer

## License

MIT
