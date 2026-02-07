require "./spec_helper"

private def with_identity(&)
  dir = Path[File.tempname("localsend-identity")]
  begin
    yield LocalSend::Identity.load_or_create(dir, alias: "Spec Device",
      device_model: "Crystal", device_type: :desktop), dir
  ensure
    FileUtils.rm_rf dir.to_s
  end
end

describe LocalSend::Identity do
  it "creates a certificate on first use and reuses it afterwards" do
    with_identity do |identity, dir|
      File.exists?(identity.certificate_path).should be_true
      File.info(identity.private_key_path).permissions.should eq File::Permissions.new(0o600)

      again = LocalSend::Identity.load_or_create(dir, alias: "Spec Device")
      again.fingerprint.should eq identity.fingerprint
    end
  end

  it "derives a 64 character hex fingerprint from the certificate" do
    with_identity do |identity, _dir|
      identity.fingerprint.should match /\A[0-9a-f]{64}\z/
    end
  end

  # Peers may format the same fingerprint differently.
  it "treats the same hash in any spelling as equal" do
    lower = "861b22c1786dc275c7b60ce59bb4ddd51b0c6b9e9f53e6fda146f8e18c97eac1"
    colons = lower.upcase.chars.each_slice(2).map(&.join).join(":")

    LocalSend::Identity.normalize(lower.upcase).should eq lower
    LocalSend::Identity.normalize(colons).should eq lower
    LocalSend::Identity.normalize("  #{lower.upcase}\n").should eq lower
    LocalSend::Identity.normalize("aa" * 32).should_not eq lower
  end
end

describe LocalSend::DeviceType do
  it "maps unknown wire values to Unknown instead of raising" do
    LocalSend::DeviceType.parse_wire("mobile").should eq LocalSend::DeviceType::Mobile
    LocalSend::DeviceType.parse_wire("smart_fridge").should eq LocalSend::DeviceType::Unknown
    LocalSend::DeviceType.parse_wire(nil).should eq LocalSend::DeviceType::Unknown
  end

  it "omits Unknown on the wire rather than inventing a value" do
    LocalSend::DeviceType::Mobile.to_wire.should eq "mobile"
    LocalSend::DeviceType::Unknown.to_wire.should be_nil
  end
end
