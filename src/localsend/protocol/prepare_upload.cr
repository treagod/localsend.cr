require "json"
require "./device_info"

module LocalSend::Protocol
  # A file in a prepare-upload request.
  struct FileInfo
    include JSON::Serializable

    getter id : String

    @[JSON::Field(key: "fileName")]
    getter file_name : String

    getter size : Int64

    @[JSON::Field(key: "fileType")]
    getter file_type : String

    def initialize(@id, @file_name, @size, @file_type)
    end
  end

  struct PrepareUploadRequest
    include JSON::Serializable

    getter info : DeviceInfo
    getter files : Hash(String, FileInfo)

    def initialize(@info, @files)
    end
  end

  struct PrepareUploadResponse
    include JSON::Serializable

    @[JSON::Field(key: "sessionId")]
    getter session_id : String

    # Maps file IDs to upload tokens.
    getter files : Hash(String, String)

    def initialize(@session_id, @files)
    end
  end
end
