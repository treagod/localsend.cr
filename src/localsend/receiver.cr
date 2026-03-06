require "crypto/subtle"
require "http/request"
require "http/server/response"
require "uuid"
require "./device"
require "./identity"
require "./incoming_transfer"
require "./log"
require "./protocol/prepare_upload"
require "./protocol/tls"

module LocalSend
  # Receives LocalSend transfers over mutual TLS.
  #
  # It owns the TLS socket so the presented certificate can be checked against
  # the sender's announcement.
  class Receiver
    Log = LocalSend::Log.for("receiver")

    # Transfers waiting for the application to accept or reject them.
    getter incoming : Channel(IncomingTransfer)

    getter port : Int32

    @session : Session?
    @running = false
    @wrong_pins = 0

    def initialize(@identity : Identity, @port : Int32 = DEFAULT_PORT,
                   @pin : String? = nil, buffer_size : Int32 = 8,
                   &@on_register : Protocol::DeviceInfo, String ->)
      @incoming = Channel(IncomingTransfer).new(buffer_size)
    end

    def self.new(identity : Identity, port : Int32 = DEFAULT_PORT,
                 pin : String? = nil, buffer_size : Int32 = 8)
      new(identity, port, pin, buffer_size) { |_info, _address| }
    end

    def run : Nil
      @running = true
      server = TCPServer.new("0.0.0.0", @port)
      @server = server
      Log.info { "listening on #{@port}" }
      spawn do
        while socket = server.accept?
          connection = socket
          spawn handle_connection(connection)
        end
      end
    end

    def stop : Nil
      @running = false
      @server.try &.close rescue nil
    end

    # ponytail: relies on cooperative fibers; add a Mutex for preview_mt.
    private class Session
      getter id : String
      getter files : Hash(String, Pending)
      getter destination : Path
      getter received = Set(String).new
      getter started_at : Time::Instant

      # Release a session when its sender disappears.
      STALE_AFTER = 5.minutes

      def initialize(@id, @files, @destination, @started_at = Time.instant)
      end

      def stale?
        Time.instant - @started_at > STALE_AFTER
      end

      def complete?
        @received.size >= @files.size
      end
    end

    private record Pending, id : String, token : String, file_name : String, size : Int64

    private def handle_connection(socket : TCPSocket)
      ssl = OpenSSL::SSL::Socket::Server.new(socket, Protocol::TLS.server_context(@identity),
        sync_close: true)
      peer = Protocol::TLS.fingerprint_of ssl

      loop do
        request = HTTP::Request.from_io ssl
        break unless request.is_a?(HTTP::Request)

        response = HTTP::Server::Response.new ssl, request.version
        handle request, response, peer
        request.body.try { |body| body.skip_to_end rescue nil }
        response.close
        # Flush empty responses before waiting for the next request.
        ssl.flush
        break unless request.keep_alive?
      end
    rescue ex : OpenSSL::SSL::Error | IO::Error | Socket::Error
      # A peer can leave during the TLS handshake.
      Log.debug { "connection ended: #{ex.message}" }
    ensure
      ssl.try { |s| s.close rescue nil }
      socket.close rescue nil
    end

    private def handle(request, response, peer)
      case {request.method, request.path}
      when {"GET", "/api/localsend/v2/info"}, {"POST", "/api/localsend/v2/info"}
        json response, own_info.to_json
      when {"POST", "/api/localsend/v2/register"}
        register request
        json response, own_info.to_json
      when {"POST", "/api/localsend/v2/prepare-upload"}
        prepare_upload request, response, peer
      when {"POST", "/api/localsend/v2/upload"}
        upload request, response
      when {"POST", "/api/localsend/v2/cancel"}
        @session = nil
        response.status_code = 200
      else
        Log.debug { "no route for #{request.method} #{request.resource}" }
        response.status_code = 404
      end
    rescue ex
      Log.error(exception: ex) { "request failed" }
      response.status_code = 500
    end

    private def register(request)
      body = request.body
      return unless body
      info = Protocol::DeviceInfo.from_json body
      @on_register.call info, peer_address(request)
    rescue JSON::ParseException
      Log.debug { "malformed register body" }
    end

    private def prepare_upload(request, response, peer)
      body = request.body
      return response.status_code = 400 unless body
      prepared = Protocol::PrepareUploadRequest.from_json body
      device = Device.from_info prepared.info, peer_address(request)

      unless verified? device.fingerprint, peer
        response.status_code = 403
        return
      end

      case pin_status request
      when 401 then return response.status_code = 401
      when 429 then return response.status_code = 429
      end

      if (session = @session) && !session.stale?
        response.status_code = 409
        return
      end

      transfer = IncomingTransfer.new(device, prepared.files.map { |id, file|
        IncomingTransfer::File.new(id, file.file_name, file.size, file.file_type)
      })

      @incoming.send transfer
      destination = transfer.await_decision
      unless destination
        Log.info { "declined transfer from #{device}" }
        response.status_code = 403
        return
      end

      files = {} of String => Pending
      tokens = {} of String => String
      prepared.files.each do |id, file|
        token = UUID.random.to_s
        files[id] = Pending.new(id, token, safe_name(file.file_name), file.size)
        tokens[id] = token
      end

      session = Session.new(UUID.random.to_s, files, destination)
      @session = session
      json response, Protocol::PrepareUploadResponse.new(session.id, tokens).to_json
    end

    private def verified?(announced : String, peer : String?) : Bool
      return true if Protocol::TLS.matches? peer, announced
      Log.warn { "fingerprint mismatch, announced #{announced}, presented #{peer || "nothing"}" }
      false
    end

    # A configured PIN locks after three failed attempts.
    def pin_status(request) : Int32?
      expected = @pin
      return nil unless expected
      return 429 if @wrong_pins >= 3

      given = request.query_params["pin"]?
      if given && Crypto::Subtle.constant_time_compare(given, expected)
        @wrong_pins = 0
        return 200
      end

      @wrong_pins += 1
      Log.info { "wrong PIN, attempt #{@wrong_pins} of 3" }
      @wrong_pins >= 3 ? 429 : 401
    end

    private def upload(request, response)
      session = @session
      file = authorize request.query_params

      unless session && file
        response.status_code = 403
        return
      end

      Dir.mkdir_p session.destination
      path = unique_path session.destination, file.file_name
      written = ::File.open(path, "wb") do |target|
        # Do not read more than the peer announced.
        IO.copy request.body || IO::Memory.new, target, file.size
      end

      if written != file.size
        # Discard incomplete uploads.
        ::File.delete path rescue nil
        Log.warn { "#{file.file_name} incomplete, #{written} of #{file.size} bytes, discarded" }
        response.status_code = 500
        return
      end

      Log.info { "saved #{path}" }
      session.received << file.id
      @session = nil if session.complete?
      response.status_code = 200
    end

    private def authorize(params) : Pending?
      session = @session
      return nil unless session && params["sessionId"]? == session.id
      file = session.files[params["fileId"]?]?
      return nil unless file && params["token"]? == file.token
      file
    end

    # File names come from the peer.
    def safe_name(name : String) : String
      base = ::File.basename(name.gsub('\\', '/'))
      base.empty? || base == "." || base == ".." ? "unnamed" : base
    end

    # Do not overwrite an existing file.
    def unique_path(directory : Path, file_name : String) : Path
      path = directory / file_name
      return path unless ::File.exists? path

      ext = ::File.extname file_name
      stem = file_name[0, file_name.size - ext.size]
      (1..).each do |n|
        candidate = directory / "#{stem} (#{n})#{ext}"
        return candidate unless ::File.exists? candidate
      end
      path
    end

    private def own_info
      Protocol::DeviceInfo.of @identity, @port
    end

    private def json(response, body)
      response.status_code = 200
      response.content_type = "application/json"
      response.print body
    end

    private def peer_address(request) : String
      request.remote_address.as?(Socket::IPAddress).try(&.address) || "?"
    end
  end
end
