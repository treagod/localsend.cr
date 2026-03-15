# Announces this device and prints discovery events.
#
#   crystal run examples/discover.cr -- --port 53318
require "option_parser"
require "../src/localsend"

port = LocalSend::DEFAULT_PORT
identity_dir = Path["./identity"]

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run examples/discover.cr -- [--port PORT]"
  parser.on("--port PORT", "HTTP port to announce (default: #{port})") { |v| port = v.to_i }
  parser.on("--identity DIR", "Where to keep the certificate (default: #{identity_dir})") { |v| identity_dir = Path[v] }
  parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
end

Log.setup_from_env(default_level: :info)

identity = LocalSend::Identity.load_or_create(identity_dir,
  alias: "Crystal Sailfish Test", device_model: "Crystal", device_type: :headless)

puts "Announcing as #{identity.alias} on port #{port}"
puts "Fingerprint: #{identity.fingerprint}"

discovery = LocalSend::Discovery.new(identity, port: port)
# LocalSend replies to announcements through `/register`, so this receiver must
# run even though the example rejects every transfer.
receiver = LocalSend::Receiver.new(identity, port: port) { |info, address| discovery.register info, address }
receiver.run
discovery.run

spawn do
  loop do
    transfer = receiver.incoming.receive
    transfer.reject
  end
end

loop do
  case event = discovery.events.receive
  when LocalSend::Discovery::Found
    device = event.device
    puts
    puts "Found device:"
    puts "  Alias:    #{device.alias}"
    puts "  Type:     #{device.device_type}"
    puts "  Model:    #{device.device_model}"
    puts "  Address:  #{device.address}:#{device.port}"
    puts "  Protocol: #{device.protocol}"
    puts "  Version:  #{device.version}"
  when LocalSend::Discovery::Updated
    puts "Updated: #{event.device}"
  when LocalSend::Discovery::Lost
    puts "Lost: #{event.device}"
  end
end
