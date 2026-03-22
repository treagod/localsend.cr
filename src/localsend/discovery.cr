require "socket"
require "./device"
require "./log"
require "./protocol/device_info"
require "./protocol/tls"

module LocalSend
  # Discovers LocalSend peers and announces this device.
  #
  # Events are buffered, so a slow consumer never blocks network fibers.
  class Discovery
    Log = LocalSend::Log.for("discovery")

    abstract struct Event
      getter device : Device

      def initialize(@device)
      end
    end

    # Newly discovered peer.
    struct Found < Event; end

    # Known peer with a new address or port.
    struct Updated < Event; end

    # Peer that stopped announcing itself.
    struct Lost < Event; end

    ANNOUNCE_INTERVAL = 30.seconds

    # Allow missed announcements before emitting `Lost`.
    FORGET_AFTER = 5.minutes

    getter events : Channel(Event)

    @peers = {} of String => {Device, Time::Instant}
    @multicast_warned = false
    @running = false

    def initialize(@identity : Identity, @port : Int32 = DEFAULT_PORT,
                   @interface : String? = nil, @broadcast : String? = nil,
                   buffer_size : Int32 = 64)
      @events = Channel(Event).new(buffer_size)
      @socket = UDPSocket.new
      @socket.reuse_address = true
      @socket.reuse_port = true
      @socket.broadcast = true
      @socket.bind "0.0.0.0", DEFAULT_PORT
      @socket.join_group Socket::IPAddress.new(MULTICAST_GROUP, DEFAULT_PORT)
      begin
        # Use the interface that routes to the multicast group.
        @socket.multicast_interface Socket::IPAddress.new(lan_address, 0)
      rescue ex : Socket::Error
        # The multicast route may be unavailable during startup.
        Log.debug { "cannot pin multicast interface: #{ex.message}" }
      end
    end

    # Starts announcements and peer discovery until `#stop`.
    def run : Nil
      @running = true
      spawn listen
      spawn announce_loop
      spawn forget_loop
    end

    def stop : Nil
      @running = false
      @socket.close rescue nil
    end

    # Peers seen so far.
    def peers : Array(Device)
      @peers.values.map(&.[0])
    end

    # Waits for a matching alias or address until `timeout` expires.
    def wait_for(target : String, timeout : Time::Span) : Device?
      deadline = Time.instant + timeout
      loop do
        found = peers.find do |device|
          device.alias.compare(target, case_insensitive: true) == 0 || device.address == target
        end
        return found if found
        return nil if Time.instant > deadline
        sleep 200.milliseconds
      end
    end

    # Records a peer that registered over HTTP.
    def register(info : Protocol::DeviceInfo, address : String) : Nil
      track Device.from_info(info, address)
    end

    private def listen
      while @running
        message, from = @socket.receive(8192)
        begin
          info = Protocol::DeviceInfo.from_json message
        rescue JSON::ParseException
          next
        end
        next if Identity.normalize(info.fingerprint) == @identity.fingerprint

        device = Device.from_info info, from.address
        track device
        reply_to device if info.announce
      end
    rescue ex : IO::Error | Socket::Error
      raise ex if @running
    end

    private def track(device : Device)
      previous = @peers[device.fingerprint]?
      @peers[device.fingerprint] = {device, Time.instant}

      if previous.nil?
        Log.info { "found #{device}" }
        publish Found.new(device)
      elsif previous[0] != device
        publish Updated.new(device)
      end
    end

    private def forget_loop
      while @running
        sleep FORGET_AFTER / 3
        sweep
      end
    end

    # Removes peers unseen for `FORGET_AFTER`.
    def sweep(now : Time::Instant = Time.instant) : Nil
      @peers.reject! do |_fingerprint, (device, last_seen)|
        next false if now - last_seen < FORGET_AFTER
        Log.info { "lost #{device}" }
        publish Lost.new(device)
        true
      end
    end

    # Drop events when the channel has no capacity.
    private def publish(event : Event)
      select
      when @events.send(event)
      else
        Log.debug { "event channel full, dropped #{event.class}" }
      end
    end

    # Respond to an announcement over HTTPS; retry through UDP if it fails.
    private def reply_to(device : Device)
      client = Protocol::TLS.connect(@identity, device.address, device.port,
        device.protocol, device.fingerprint, 3.seconds)
      begin
        client.post "/api/localsend/v2/register",
          headers: HTTP::Headers{"Content-Type" => "application/json"},
          body: own_info.to_json
      ensure
        client.close rescue nil
      end
    rescue ex : Error
      Log.debug { "register with #{device} failed: #{ex.message}, falling back to UDP" }
      send_announcement own_info(announce: false).to_json
    end

    private def own_info(announce : Bool? = nil)
      Protocol::DeviceInfo.of @identity, @port, announce
    end

    private def announce_loop
      payload = own_info(announce: true).to_json
      # Send the initial announcement three times to reduce packet loss.
      3.times do
        break unless @running
        send_announcement payload
        sleep 2.seconds
      end
      while @running
        send_announcement payload
        sleep ANNOUNCE_INTERVAL
      end
    end

    # Try multicast first, then subnet broadcast.
    private def send_announcement(payload : String)
      @socket.send payload, Socket::IPAddress.new(MULTICAST_GROUP, DEFAULT_PORT)
    rescue ex : Socket::Error
      unless @multicast_warned
        Log.info { "multicast blocked (#{ex.message}), falling back to broadcast" }
        @multicast_warned = true
      end
      @socket.send payload, Socket::IPAddress.new(broadcast_address, DEFAULT_PORT)
    rescue ex : Socket::Error
      Log.warn { "announcement failed: #{ex.message}" }
    end

    # Local address selected by multicast routing.
    # UDP connect selects a route without sending data.
    private def lan_address : String
      return @interface.not_nil! if @interface
      probe = UDPSocket.new
      probe.connect MULTICAST_GROUP, DEFAULT_PORT
      probe.local_address.address
    ensure
      probe.try &.close
    end

    # Assumes /24. Read the real netmask if wider LANs need broadcast fallback.
    private def broadcast_address : String
      @broadcast || lan_address.sub(/\.\d+$/, ".255")
    end
  end
end
