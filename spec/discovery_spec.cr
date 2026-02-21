require "./spec_helper"

private def with_discovery(&)
  dir = Path[File.tempname("localsend-discovery")]
  identity = LocalSend::Identity.load_or_create(dir, alias: "Spec Device")
  discovery = LocalSend::Discovery.new(identity, port: 53399)
  begin
    yield discovery
  ensure
    discovery.stop
    FileUtils.rm_rf dir.to_s
  end
end

private def info(alias name = "Nice Orange", fingerprint = "aa" * 32, port = 53317)
  LocalSend::Protocol::DeviceInfo.new(alias: name, version: "2.0",
    device_model: "iPhone", device_type: "mobile", fingerprint: fingerprint,
    port: port, protocol: "https")
end

describe LocalSend::Discovery do
  it "reports a new peer once, then only on change" do
    with_discovery do |discovery|
      discovery.register info, "192.168.178.150"
      event = discovery.events.receive
      event.should be_a LocalSend::Discovery::Found
      event.device.alias.should eq "Nice Orange"

      # Registering the same peer emits no event.
      discovery.register info, "192.168.178.150"
      select
      when unexpected = discovery.events.receive
        fail "expected no event, got #{unexpected.class}"
      when timeout(100.milliseconds)
      end

      # A changed port emits `Updated`.
      discovery.register info(port: 53318), "192.168.178.150"
      discovery.events.receive.should be_a LocalSend::Discovery::Updated
    end
  end

  it "forgets a peer that stopped announcing itself" do
    with_discovery do |discovery|
      discovery.register info, "192.168.178.150"
      discovery.events.receive.should be_a LocalSend::Discovery::Found

      discovery.sweep Time.instant + LocalSend::Discovery::FORGET_AFTER + 1.second
      event = discovery.events.receive
      event.should be_a LocalSend::Discovery::Lost
      event.device.alias.should eq "Nice Orange"
      discovery.peers.should be_empty
    end
  end

  it "finds a peer by alias or address" do
    with_discovery do |discovery|
      discovery.register info, "192.168.178.150"

      discovery.wait_for("nice orange", 1.second).try(&.address).should eq "192.168.178.150"
      discovery.wait_for("192.168.178.150", 1.second).try(&.alias).should eq "Nice Orange"
      discovery.wait_for("nobody", 100.milliseconds).should be_nil
    end
  end
end
