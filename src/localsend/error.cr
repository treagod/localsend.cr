module LocalSend
  # Everything this shard raises derives from `Error`, so an application can
  # rescue the whole library with one clause and refine from there.
  class Error < Exception
  end

  # The peer could not be reached, or the connection died mid-transfer.
  class ConnectionError < Error
  end

  # The peer answered, but not the way the protocol says it should.
  class ProtocolError < Error
  end

  # The peer declined the transfer.
  class RejectedError < Error
  end

  # The certificate the peer presented is not the one it announced. The
  # announcement is the only identity anchor LocalSend has -- there is no CA --
  # so this is a hard stop, never a warning.
  class FingerprintMismatchError < Error
    getter announced : String
    getter presented : String?

    def initialize(@announced, @presented)
      super <<-MSG
        certificate fingerprint mismatch
            announced: #{@announced}
            presented: #{@presented || "(no certificate)"}
        MSG
    end
  end

  # The peer requires a PIN, or the one we sent was wrong.
  class PinError < Error
  end
end
