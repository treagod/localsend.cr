# Sends files to a LocalSend device found by alias or address.
#
#   crystal run examples/send.cr -- --device treagod test.txt
require "option_parser"
require "../src/localsend"

target = ""
port = LocalSend::DEFAULT_PORT
identity_dir = Path["./identity"]
device_alias = "Crystal LocalSend"
pin = nil.as(String?)
wait = 5.seconds

parser = OptionParser.parse do |p|
  p.banner = "Usage: crystal run examples/send.cr -- --device ALIAS|ADDRESS FILE..."
  p.on("--device NAME", "Target device alias or address") { |v| target = v }
  p.on("--port PORT", "Local HTTP port (default: #{port})") { |v| port = v.to_i }
  p.on("--alias NAME", "Alias advertised to other devices (default: #{device_alias})") { |v| device_alias = v }
  p.on("--identity DIR", "Where to keep the certificate (default: #{identity_dir})") { |v| identity_dir = Path[v] }
  p.on("--pin CODE", "PIN the receiver asks for") { |v| pin = v }
  p.on("--wait SECONDS", "How long to look for the device (default: 5)") { |v| wait = v.to_i.seconds }
  p.on("-h", "--help", "Show this help") { puts p; exit 0 }
end

paths = ARGV.map { |arg| Path[arg] }
if target.empty? || paths.empty?
  puts parser
  exit 1
end

Log.setup_from_env(default_level: :info)

identity = LocalSend::Identity.load_or_create(identity_dir,
  alias: device_alias, device_model: "Crystal", device_type: :headless)

# Discovery supplies the certificate fingerprint expected for the connection.
discovery = LocalSend::Discovery.new(identity, port: port)
receiver = LocalSend::Receiver.new(identity, port: port) { |info, address| discovery.register info, address }
receiver.run
discovery.run

puts "Looking for #{target}..."
device = discovery.wait_for(target, wait)
unless device
  STDERR.puts "Could not find #{target}. Is LocalSend open on it?"
  exit 1
end
puts "Found #{device}"

begin
  last = -1
  LocalSend::Client.new(identity, port: port).send(device, paths, pin) do |progress|
    next if progress.percent == last
    last = progress.percent
    print "\rUploading #{progress.file_name}... #{progress.percent}%"
    puts if progress.done?
  end
  puts "Done"
rescue ex : LocalSend::Error
  STDERR.puts "\nError: #{ex.message}"
  exit 1
end
