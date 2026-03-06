require "./spec_helper"

private def with_receiver(pin = nil, &)
  dir = Path[File.tempname("localsend-receiver")]
  identity = LocalSend::Identity.load_or_create(dir, alias: "Spec Receiver")
  begin
    yield LocalSend::Receiver.new(identity, port: 53398, pin: pin), dir
  ensure
    FileUtils.rm_rf dir.to_s
  end
end

private def prepare_request(pin = nil)
  query = pin ? "?pin=#{pin}" : ""
  HTTP::Request.new("POST", "/api/localsend/v2/prepare-upload#{query}")
end

private def files
  [LocalSend::IncomingTransfer::File.new("f1", "a.txt", 10_i64, "text/plain"),
   LocalSend::IncomingTransfer::File.new("f2", "b.txt", 5_i64, "text/plain")]
end

private def device
  LocalSend::Device.new(alias: "Nice Orange", version: "2.0", device_model: "iPhone",
    device_type: LocalSend::DeviceType::Mobile, fingerprint: "aa" * 32,
    address: "192.168.178.150", port: 53317)
end

describe LocalSend::Receiver do
  it "keeps peer file names inside the destination" do
    with_receiver do |receiver, _dir|
      receiver.safe_name("../../.ssh/authorized_keys").should eq "authorized_keys"
      receiver.safe_name("/etc/passwd").should eq "passwd"
      receiver.safe_name("..\\..\\windows\\evil.exe").should eq "evil.exe"
      receiver.safe_name("..").should eq "unnamed"
    end
  end

  it "chooses a free path instead of overwriting a file" do
    with_receiver do |receiver, dir|
      receiver.unique_path(dir, "test.pdf").should eq dir / "test.pdf"

      File.write dir / "test.pdf", "x"
      receiver.unique_path(dir, "test.pdf").should eq dir / "test (1).pdf"

      File.write dir / "test (1).pdf", "x"
      receiver.unique_path(dir, "test.pdf").should eq dir / "test (2).pdf"

      File.write dir / "noext", "x"
      receiver.unique_path(dir, "noext").should eq dir / "noext (1)"
    end
  end

  it "resets successful PIN attempts and locks after three failures" do
    with_receiver(pin: "123456") do |receiver, _dir|
      receiver.pin_status(prepare_request("123456")).should eq 200
      receiver.pin_status(prepare_request("000000")).should eq 401
      receiver.pin_status(prepare_request("123456")).should eq 200 # A successful attempt resets the count.

      receiver.pin_status(prepare_request("000000")).should eq 401
      receiver.pin_status(prepare_request("000001")).should eq 401
      receiver.pin_status(prepare_request("000002")).should eq 429
      receiver.pin_status(prepare_request("123456")).should eq 429 # Lockout remains after the right PIN.
    end
  end

  it "does not require a PIN when none is configured" do
    with_receiver do |receiver, _dir|
      receiver.pin_status(prepare_request("whatever")).should be_nil
    end
  end
end

describe LocalSend::IncomingTransfer do
  it "returns the destination after acceptance" do
    transfer = LocalSend::IncomingTransfer.new(device, files)
    transfer.total_size.should eq 15
    transfer.decided?.should be_false

    spawn { transfer.accept Path["./received"] }
    transfer.await_decision.should eq Path["./received"]
    transfer.decided?.should be_true
  end

  it "returns no destination after rejection" do
    transfer = LocalSend::IncomingTransfer.new(device, files)
    spawn { transfer.reject }
    transfer.await_decision.should be_nil
  end

  it "allows one decision" do
    transfer = LocalSend::IncomingTransfer.new(device, files)
    transfer.reject
    expect_raises(LocalSend::Error, /already decided/) { transfer.accept Path["./received"] }
  end
end
