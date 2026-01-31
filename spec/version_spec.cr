require "./spec_helper"

describe LocalSend do
  it "matches the version in shard.yml" do
    shard = File.read(File.join(__DIR__, "..", "shard.yml"))
    shard.should contain "version: #{LocalSend::VERSION}"
  end
end
