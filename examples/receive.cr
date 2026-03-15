# Receives files from other LocalSend devices.
#
#   crystal run examples/receive.cr -- --out ./received --pin 123456
require "option_parser"
require "../src/localsend"

port = LocalSend::DEFAULT_PORT
out_dir = Path["./received"]
identity_dir = Path["./identity"]
pin = nil.as(String?)

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run examples/receive.cr -- [--out DIR] [--pin CODE]"
  parser.on("--out DIR", "Where to store received files (default: #{out_dir})") { |v| out_dir = Path[v] }
  parser.on("--port PORT", "Port to listen on (default: #{port})") { |v| port = v.to_i }
  parser.on("--identity DIR", "Where to keep the certificate (default: #{identity_dir})") { |v| identity_dir = Path[v] }
  parser.on("--pin CODE", "Require this PIN") { |v| pin = v }
  parser.on("-h", "--help", "Show this help") { puts parser; exit 0 }
end

Log.setup_from_env(default_level: :info)

identity = LocalSend::Identity.load_or_create(identity_dir,
  alias: "Crystal Sailfish Test", device_model: "Crystal", device_type: :headless)

discovery = LocalSend::Discovery.new(identity, port: port)
receiver = LocalSend::Receiver.new(identity, port: port, pin: pin) do |info, address|
  discovery.register info, address
end
receiver.run
discovery.run

puts "Listening as #{identity.alias} on port #{port}"
puts "Receiving into #{out_dir}"
puts "PIN required" if pin

loop do
  transfer = receiver.incoming.receive
  puts
  puts "#{transfer.device.alias} wants to send #{transfer.files.size} file(s):"
  transfer.files.each { |file| puts "  #{file.name} (#{file.size} B)" }
  transfer.accept out_dir
end
