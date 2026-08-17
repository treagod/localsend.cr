require "openssl_ext"
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
        generate cert, key, name
        File.chmod key, 0o600
      end

      type = device_type.is_a?(Symbol) ? DeviceType.parse(device_type.to_s) : device_type
      new(name, cert, key, device_model, type)
    end

    # SHA-256 fingerprint announced to peers.
    def fingerprint : String
      @fingerprint ||= self.class.normalize(
        OpenSSL::X509::Certificate.new(File.read(@certificate_path))
          .digest("SHA256").hexstring)
    end

    @fingerprint : String?

    # Peers may use uppercase letters and colons in the same fingerprint.
    def self.normalize(hash : String) : String
      hash.strip.delete(':').downcase
    end

    private def self.generate(certificate_path : String, private_key_path : String,
                              name : String) : Nil
      key = OpenSSL::PKey::RSA.new(2048)

      # Not `Name.parse`: it splits on '/' and would mangle an alias containing one.
      subject = OpenSSL::X509::Name.new
      subject.add_entry "CN", name

      certificate = OpenSSL::X509::Certificate.new
      certificate.subject = subject
      certificate.issuer = subject
      certificate.public_key = key.public_key
      certificate.not_before = OpenSSL::ASN1::Time.new(0)
      certificate.not_after = OpenSSL::ASN1::Time.days_from_now(3650)
      certificate.sign key, OpenSSL::Digest.new("SHA256")

      File.write certificate_path, certificate.to_pem
      File.write private_key_path, key.to_pem
    end
  end
end
