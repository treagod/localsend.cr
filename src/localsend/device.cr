require "socket"
require "./identity"
require "./protocol/device_info"

module LocalSend
  # A discovered LocalSend peer, ready for application use.
  #
  # Unlike `Protocol::DeviceInfo`, this has a resolved address and normalized
  # identity data.
  struct Device
    getter alias : String
    getter version : String
    getter device_model : String?
    getter device_type : DeviceType
    getter fingerprint : String
    getter address : String
    getter port : Int32
    getter protocol : String

    def initialize(@alias, @version, @device_model, @device_type, @fingerprint,
                   @address, @port, @protocol = "https")
    end

    def self.from_info(info : Protocol::DeviceInfo, address : String) : Device
      new(
        alias: info.alias,
        version: info.version,
        device_model: info.device_model,
        device_type: DeviceType.parse_wire(info.device_type),
        fingerprint: Identity.normalize(info.fingerprint),
        address: address,
        port: info.port || DEFAULT_PORT,
        protocol: info.protocol || "https",
      )
    end

    def to_s(io : IO) : Nil
      io << @alias << " (" << @address << ':' << @port << ')'
    end
  end
end
