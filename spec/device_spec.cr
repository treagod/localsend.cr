require "./spec_helper"

private ANNOUNCEMENT = <<-JSON
  {
    "alias": "Nice Orange",
    "version": "2.0",
    "deviceModel": "iPhone",
    "deviceType": "mobile",
    "fingerprint": "861B22C1786DC275C7B60CE59BB4DDD51B0C6B9E9F53E6FDA146F8E18C97EAC1",
    "port": 53317,
    "protocol": "https",
    "download": true,
    "announce": true
  }
  JSON

describe LocalSend::Protocol::DeviceInfo do
  it "parses an announcement from the official app" do
    info = LocalSend::Protocol::DeviceInfo.from_json ANNOUNCEMENT

    info.alias.should eq "Nice Orange"
    info.device_model.should eq "iPhone"
    info.device_type.should eq "mobile"
    info.announce.should be_true
  end

  it "survives a device type nobody has invented yet" do
    info = LocalSend::Protocol::DeviceInfo.from_json ANNOUNCEMENT.sub("mobile", "smart_fridge")
    LocalSend::DeviceType.parse_wire(info.device_type).should eq LocalSend::DeviceType::Unknown
  end
end

describe LocalSend::Device do
  it "normalizes the announced fingerprint so later comparisons hold" do
    info = LocalSend::Protocol::DeviceInfo.from_json ANNOUNCEMENT
    device = LocalSend::Device.from_info info, "192.168.178.150"

    device.fingerprint.should eq "861b22c1786dc275c7b60ce59bb4ddd51b0c6b9e9f53e6fda146f8e18c97eac1"
    device.device_type.should eq LocalSend::DeviceType::Mobile
    device.address.should eq "192.168.178.150"
    device.port.should eq 53317
    device.to_s.should eq "Nice Orange (192.168.178.150:53317)"
  end

  it "falls back to the default port and https when the peer omits them" do
    info = LocalSend::Protocol::DeviceInfo.from_json <<-JSON
      {"alias": "Sparse", "version": "2.0", "fingerprint": "ab"}
      JSON
    device = LocalSend::Device.from_info info, "10.0.0.5"

    device.port.should eq LocalSend::DEFAULT_PORT
    device.protocol.should eq "https"
    device.device_type.should eq LocalSend::DeviceType::Unknown
  end
end
