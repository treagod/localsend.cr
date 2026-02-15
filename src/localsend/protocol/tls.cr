require "http/client"
require "openssl"
require "socket"
require "../error"
require "../identity"
require "../log"

module LocalSend::Protocol
  # TLS for LocalSend's self-signed certificates.
  #
  # LocalSend has no CA, so certificate-chain validation is disabled. Connections
  # compare the presented SHA-256 fingerprint with the announcement instead.
  module TLS
    Log = LocalSend::Log.for("tls")

    def self.client_context(identity : Identity) : OpenSSL::SSL::Context::Client
      ctx = OpenSSL::SSL::Context::Client.new
      ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      # Peers require clients to present a certificate during the TLS handshake.
      ctx.certificate_chain = identity.certificate_path
      ctx.private_key = identity.private_key_path
      ctx
    end

    def self.server_context(identity : Identity) : OpenSSL::SSL::Context::Server
      ctx = OpenSSL::SSL::Context::Server.new
      ctx.certificate_chain = identity.certificate_path
      ctx.private_key = identity.private_key_path
      # Request a client certificate but accept self-signed peers. Fingerprint
      # verification is the authentication gate.
      LibSSL.ssl_ctx_set_verify(ctx.to_unsafe, OpenSSL::SSL::VerifyMode::PEER,
        ->(_ok : LibC::Int, _store : LibCrypto::X509_STORE_CTX) { LibC::Int.new(1) })
      ctx
    end

    def self.fingerprint_of(socket : OpenSSL::SSL::Socket) : String?
      socket.peer_certificate.try { |cert| Identity.normalize(cert.digest("SHA256").hexstring) }
    end

    # Checks the presented certificate against the announced fingerprint.
    def self.matches?(presented : String?, announced : String) : Bool
      return false unless presented
      Identity.normalize(presented) == Identity.normalize(announced)
    end

    # Opens an HTTP connection and verifies the expected TLS fingerprint before
    # sending data.
    #
    # Build the socket manually because HTTP::Client's TLS constructor does not
    # expose it for fingerprint verification.
    def self.connect(identity : Identity, host : String, port : Int32,
                     protocol : String, expect_fingerprint : String?,
                     timeout : Time::Span) : HTTP::Client
      unless protocol == "https"
        client = HTTP::Client.new(host, port)
        client.connect_timeout = timeout
        client.read_timeout = timeout
        return client
      end

      tcp = TCPSocket.new(host, port, connect_timeout: timeout)
      ssl = OpenSSL::SSL::Socket::Client.new(tcp, client_context(identity),
        sync_close: true, hostname: host)

      if expect_fingerprint
        presented = fingerprint_of ssl
        unless matches? presented, expect_fingerprint
          ssl.close rescue nil
          raise FingerprintMismatchError.new(Identity.normalize(expect_fingerprint), presented)
        end
        Log.debug { "#{host}:#{port} certificate matches announcement" }
      end

      client = HTTP::Client.new(ssl, host, port)
      client.read_timeout = timeout
      client
    rescue ex : Socket::Error | IO::Error | OpenSSL::SSL::Error
      raise ConnectionError.new "cannot reach #{host}:#{port}: #{ex.message}"
    end
  end
end
