require "mime"
require "uri"
require "uuid"
require "./device"
require "./error"
require "./identity"
require "./log"
require "./progress"
require "./protocol/prepare_upload"
require "./protocol/tls"

module LocalSend
  # Sends one or more files to a LocalSend device.
  #
  # `#send` waits for the receiver to accept and for every upload to finish.
  # Run it in a fiber when the caller must stay responsive.
  class Client
    Log = LocalSend::Log.for("client")

    # The receiver holds prepare-upload while someone decides.
    ACCEPT_TIMEOUT = 5.minutes

    TRANSFER_TIMEOUT = 60.seconds

    def initialize(@identity : Identity, @port : Int32 = DEFAULT_PORT)
    end

    def send(device : Device, path : Path, pin : String? = nil,
             &report : Progress ->) : Nil
      send device, [path], pin, &report
    end

    def send(device : Device, path : Path, pin : String? = nil) : Nil
      send(device, [path], pin) { }
    end

    def send(device : Device, paths : Enumerable(Path), pin : String? = nil) : Nil
      send(device, paths, pin) { }
    end

    def send(device : Device, paths : Enumerable(Path), pin : String? = nil,
             &report : Progress ->) : Nil
      request = build_request paths
      session = prepare device, request, pin

      request.files.each do |id, file|
        token = session.files[id]?
        raise ProtocolError.new "receiver returned no token for #{file.file_name}" unless token
        upload device, file, session.session_id, token, paths_by_id(paths, request)[id], &report
      end

      Log.info { "sent #{request.files.size} file(s) to #{device}" }
    end

    # Builds the prepare-upload payload without opening a connection.
    def build_request(paths : Enumerable(Path)) : Protocol::PrepareUploadRequest
      files = {} of String => Protocol::FileInfo
      paths.each do |path|
        raise Error.new "no such file: #{path}" unless File.file? path
        id = UUID.random.to_s
        files[id] = Protocol::FileInfo.new(
          id: id,
          file_name: File.basename(path),
          size: File.size(path).to_i64,
          file_type: mime_type(path),
        )
      end
      raise Error.new "nothing to send" if files.empty?
      Protocol::PrepareUploadRequest.new Protocol::DeviceInfo.of(@identity, @port), files
    end

    # MIME tables differ per host: Crystal's built-in table spells text types
    # "text/plain; charset=utf-8" where /etc/apache2/mime.types on macOS says
    # "text/plain". Send the bare type so the wire format is the same everywhere.
    private def mime_type(path : Path) : String
      MIME.from_extension(path.extension, "application/octet-stream").partition(';')[0].strip
    end

    private def paths_by_id(paths, request)
      request.files.keys.zip(paths.to_a).to_h
    end

    private def prepare(device, request, pin) : Protocol::PrepareUploadResponse
      path = "/api/localsend/v2/prepare-upload"
      path += "?pin=#{URI.encode_www_form(pin)}" if pin

      response = post device, path, request.to_json, timeout: ACCEPT_TIMEOUT
      case response.status_code
      when 200
        Protocol::PrepareUploadResponse.from_json response.body
      when 204
        raise RejectedError.new "receiver accepted none of the files"
      when 401
        raise PinError.new pin ? "wrong PIN" : "receiver requires a PIN"
      when 403
        raise RejectedError.new "receiver declined the transfer"
      when 409
        raise RejectedError.new "receiver is busy with another transfer"
      when 429
        raise PinError.new "too many attempts, receiver is refusing further tries"
      else
        raise ProtocolError.new "prepare-upload failed with #{response.status_code}"
      end
    rescue ex : JSON::ParseException
      raise ProtocolError.new "receiver sent a malformed prepare-upload response"
    end

    private def upload(device, file, session_id, token, path, &report : Progress ->)
      query = URI::Params.encode({
        "sessionId" => session_id, "fileId" => file.id, "token" => token,
      })

      response = File.open(path) do |io|
        body = ProgressIO.new(io, file.file_name, file.size) { |progress| report.call progress }
        post device, "/api/localsend/v2/upload?#{query}", body,
          content_type: "application/octet-stream", size: file.size,
          timeout: TRANSFER_TIMEOUT
      end

      unless response.success?
        raise ProtocolError.new "upload of #{file.file_name} failed with #{response.status_code}"
      end
    end

    private def post(device, path, body, content_type = "application/json",
                     size : Int64? = nil, timeout = TRANSFER_TIMEOUT)
      headers = HTTP::Headers{"Content-Type" => content_type}
      headers["Content-Length"] = size.to_s if size

      client = Protocol::TLS.connect(@identity, device.address, device.port,
        device.protocol, device.fingerprint, timeout)
      begin
        client.post path, headers: headers, body: body
      rescue ex : IO::Error | Socket::Error
        raise ConnectionError.new "#{device} hung up: #{ex.message}"
      ensure
        client.close rescue nil
      end
    end
  end
end
