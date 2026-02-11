require "json"
require "../identity"

module LocalSend::Protocol
  # LocalSend device data sent in announcements, registration, and upload requests.
  #
  # Keep extensible protocol values as strings so newer peer values still parse.
  struct DeviceInfo
    include JSON::Serializable

    getter alias : String
    getter version : String

    @[JSON::Field(key: "deviceModel")]
    getter device_model : String?

    @[JSON::Field(key: "deviceType")]
    getter device_type : String?

    getter fingerprint : String
    getter port : Int32?
    getter protocol : String?
    getter download : Bool = false
    getter announce : Bool?

    def initialize(@alias, @version, @device_model, @device_type, @fingerprint,
                   @port, @protocol, @download = false, @announce = nil)
    end

    # Builds this device's advertised information. Set `announce` for discovery greetings.
    def self.of(identity : Identity, port : Int32, announce : Bool? = nil) : DeviceInfo
      new(
        alias: identity.alias,
        version: PROTOCOL_VERSION,
        device_model: identity.device_model,
        device_type: identity.device_type.to_wire,
        fingerprint: identity.fingerprint,
        port: port,
        protocol: "https",
        download: false,
        announce: announce,
      )
    end
  end
end
