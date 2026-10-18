# frozen_string_literal: true

require "spec_helper"
require_relative "../tools/demo"

RSpec.describe Demo, :aggregate_failures do
  let(:occupied) { [] }

  before do
    # Simulate an allocator that immediately reuses released ports. This is legal
    # allocation behavior, not a claim that the host reproduced an OS collision.
    allow(TCPServer).to receive(:open) do |*_arguments, &block|
      port = ([50_001, 50_002] - occupied).first
      occupied << port
      block.call(instance_double(TCPServer, addr: ["AF_INET", port]))
    ensure
      occupied.delete(port)
    end
  end

  it "selects distinct service ports when released ports are immediately reused" do
    expect(described_class.free_ports).to eq([50_001, 50_002])
    expect(occupied).to be_empty
  end
end
