require "./spec_helper"

describe LocalSend::Protocol::TLS do
  it "matches a fingerprint regardless of spelling" do
    hash = "861b22c1786dc275c7b60ce59bb4ddd51b0c6b9e9f53e6fda146f8e18c97eac1"

    LocalSend::Protocol::TLS.matches?(hash, hash.upcase).should be_true
    LocalSend::Protocol::TLS.matches?(hash.upcase, hash).should be_true
    LocalSend::Protocol::TLS.matches?("aa" * 32, hash).should be_false
  end

  it "refuses a peer that presented no certificate at all" do
    LocalSend::Protocol::TLS.matches?(nil, "aa" * 32).should be_false
  end
end
