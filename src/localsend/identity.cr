require "./error"
require "./log"
require "./version"

module LocalSend
  # Device type announced to peers. Unknown wire values remain representable.
  enum DeviceType
    Mobile
    Desktop
    Web
    Headless
    Server
    Unknown

    def self.parse_wire(value : String?) : DeviceType
      parse?(value || "") || Unknown
    end

    def to_wire : String?
      self == Unknown ? nil : to_s.downcase
    end
  end

  # The local device identity and its TLS material.
  #
  # LocalSend identifies devices by certificate fingerprint, not a CA. Share one
  # identity between `Discovery`, `Client`, and `Receiver`.
  #
  # The caller chooses where to store the certificate and private key.
  class Identity
    Log = LocalSend::Log.for("identity")

    getter alias : String
    getter device_model : String?
    getter device_type : DeviceType
    getter certificate_path : String
    getter private_key_path : String

    def initialize(@alias, @certificate_path, @private_key_path,
                   @device_model = nil, @device_type = DeviceType::Headless)
    end

    # Loads the identity from `dir`, creating a self-signed certificate if needed.
    def self.load_or_create(dir : Path, alias name : String,
                            device_model : String? = nil,
                            device_type : DeviceType | Symbol = DeviceType::Headless) : Identity
      dir = dir.expand(home: true)
      cert = (dir / "cert.pem").to_s
      key = (dir / "key.pem").to_s

      unless File.exists?(cert) && File.exists?(key)
        Log.info { "generating certificate in #{dir}" }
        Dir.mkdir_p dir, 0o700
        openssl "req", "-x509", "-newkey", "rsa:2048", "-nodes",
          "-keyout", key, "-out", cert, "-days", "3650", "-subj", "/CN=#{name}"
        File.chmod key, 0o600
      end

      type = device_type.is_a?(Symbol) ? DeviceType.parse(device_type.to_s) : device_type
      new(name, cert, key, device_model, type)
    end

    # SHA-256 fingerprint announced to peers.
    def fingerprint : String
      @fingerprint ||= self.class.normalize(
        self.class.openssl("x509", "-in", @certificate_path, "-noout",
          "-fingerprint", "-sha256").split('=').last)
    end

    @fingerprint : String?

    # Peers may use uppercase letters and colons in the same fingerprint.
    def self.normalize(hash : String) : String
      hash.strip.delete(':').downcase
    end

    # Crystal can read certificates but cannot create them, so use the `openssl` binary.
    protected def self.openssl(*args) : String
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run "openssl", args, output: output, error: error
      unless status.success?
        raise Error.new "openssl #{args.first} failed: #{error.to_s.lines.first?}"
      end
      output.to_s
    end
  end
end
