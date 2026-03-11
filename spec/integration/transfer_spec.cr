require "../spec_helper"

# Runs a Client and Receiver over a real TLS connection with separate
# identities. Both certificate fingerprint checks are exercised.
private def with_pair(port : Int32, pin : String? = nil, &)
  root = Path[File.tempname("localsend-integration")]
  Dir.mkdir_p root

  begin
    sender = LocalSend::Identity.load_or_create(root / "sender", alias: "Sender",
      device_model: "Crystal", device_type: :desktop)
    receiver_identity = LocalSend::Identity.load_or_create(root / "receiver",
      alias: "Receiver", device_model: "Crystal", device_type: :headless)

    receiver = LocalSend::Receiver.new(receiver_identity, port: port, pin: pin)
    receiver.run

    device = LocalSend::Device.new(alias: "Receiver", version: "2.0",
      device_model: "Crystal", device_type: LocalSend::DeviceType::Headless,
      fingerprint: receiver_identity.fingerprint, address: "127.0.0.1", port: port)

    yield LocalSend::Client.new(sender, port: port + 1), receiver, device, root
  ensure
    receiver.try &.stop
    FileUtils.rm_rf root.to_s
  end
end

private def accept_next(receiver, destination : Path)
  spawn { receiver.incoming.receive.accept destination }
end

describe "client and receiver" do
  it "transfers a file without changing its bytes" do
    with_pair(53501) do |client, receiver, device, root|
      source = root / "note.txt"
      File.write source, "hallo localsend"
      destination = root / "received"
      accept_next receiver, destination

      seen = [] of LocalSend::Progress
      client.send(device, source) { |progress| seen << progress }

      File.read(destination / "note.txt").should eq "hallo localsend"
      seen.last.percent.should eq 100
      seen.last.file_name.should eq "note.txt"
    end
  end

  it "releases a completed multi-file session" do
    with_pair(53502) do |client, receiver, device, root|
      one = root / "one.txt"
      two = root / "two.txt"
      File.write one, "first"
      File.write two, "second"
      destination = root / "received"

      accept_next receiver, destination
      client.send device, [one, two]

      # A stale session would answer this with 409.
      accept_next receiver, destination
      client.send device, one

      File.read(destination / "one.txt").should eq "first"
      File.read(destination / "two.txt").should eq "second"
      File.read(destination / "one (1).txt").should eq "first"
    end
  end

  it "raises RejectedError when the receiver rejects a transfer" do
    with_pair(53503) do |client, receiver, device, root|
      source = root / "note.txt"
      File.write source, "hallo"
      spawn { receiver.incoming.receive.reject }

      expect_raises(LocalSend::RejectedError) { client.send device, source }
    end
  end

  it "rejects a receiver with an unexpected certificate" do
    with_pair(53504) do |client, receiver, device, root|
      source = root / "note.txt"
      File.write source, "hallo"

      impostor = LocalSend::Device.new(alias: device.alias, version: device.version,
        device_model: device.device_model, device_type: device.device_type,
        fingerprint: "aa" * 32, address: device.address, port: device.port)

      expect_raises(LocalSend::FingerprintMismatchError) { client.send impostor, source }
      Dir.exists?(root / "received").should be_false
    end
  end

  it "requires the receiver PIN" do
    with_pair(53505, pin: "123456") do |client, receiver, device, root|
      source = root / "note.txt"
      File.write source, "hallo"
      destination = root / "received"

      expect_raises(LocalSend::PinError, /requires a PIN/) { client.send device, source }
      expect_raises(LocalSend::PinError, /wrong PIN/) { client.send device, source, pin: "000000" }

      accept_next receiver, destination
      client.send device, source, pin: "123456"
      File.read(destination / "note.txt").should eq "hallo"
    end
  end
end
