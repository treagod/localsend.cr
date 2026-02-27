require "./spec_helper"

describe LocalSend::Progress do
  it "calculates percentages, including empty files" do
    LocalSend::Progress.new("a.txt", 0_i64, 100_i64).percent.should eq 0
    LocalSend::Progress.new("a.txt", 50_i64, 100_i64).percent.should eq 50
    LocalSend::Progress.new("a.txt", 100_i64, 100_i64).percent.should eq 100
    LocalSend::Progress.new("empty", 0_i64, 0_i64).percent.should eq 100
  end

  it "finishes once every byte is reported" do
    LocalSend::Progress.new("a.txt", 99_i64, 100_i64).done?.should be_false
    LocalSend::Progress.new("a.txt", 100_i64, 100_i64).done?.should be_true
  end
end

describe LocalSend::Protocol::PrepareUploadResponse do
  it "parses a prepare-upload response" do
    response = LocalSend::Protocol::PrepareUploadResponse.from_json <<-JSON
      {"sessionId": "mySessionId", "files": {"someFileId": "someFileToken"}}
      JSON

    response.session_id.should eq "mySessionId"
    response.files["someFileId"].should eq "someFileToken"
  end
end

describe LocalSend::Client do
  it "builds prepare-upload entries from files" do
    dir = Path[File.tempname("localsend-client")]
    Dir.mkdir_p dir
    begin
      File.write dir / "note.txt", "hallo localsend"
      identity = LocalSend::Identity.load_or_create(dir / "identity", alias: "Spec Device")
      client = LocalSend::Client.new(identity, port: 53399)

      request = client.build_request [dir / "note.txt"]
      id, file = request.files.first

      id.should eq file.id
      file.file_name.should eq "note.txt"
      file.size.should eq 15
      file.file_type.should eq "text/plain"
      request.info.alias.should eq "Spec Device"
      request.info.fingerprint.should eq identity.fingerprint
    ensure
      FileUtils.rm_rf dir.to_s
    end
  end

  it "rejects files that do not exist" do
    dir = Path[File.tempname("localsend-client")]
    Dir.mkdir_p dir
    begin
      identity = LocalSend::Identity.load_or_create(dir / "identity", alias: "Spec Device")
      client = LocalSend::Client.new(identity)

      expect_raises(LocalSend::Error, /no such file/) do
        client.build_request [Path["/definitely/not/here.txt"]]
      end
    ensure
      FileUtils.rm_rf dir.to_s
    end
  end
end
