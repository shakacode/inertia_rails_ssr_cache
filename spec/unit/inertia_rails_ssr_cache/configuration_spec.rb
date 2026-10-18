# frozen_string_literal: true

require_relative "../../../lib/inertia_rails_ssr_cache/configuration"

RSpec.describe InertiaRailsSsrCache::Configuration, :aggregate_failures do
  subject(:configuration) { described_class.new }

  before do
    configuration.origin = "https://public.example"
    configuration.paths = ["/".dup, "/pricing?locale=en".dup]
  end

  it "freezes a snapshot without freezing caller-owned paths" do
    original = configuration.paths
    configured = configuration.validate!
    original.first.replace("/changed")

    expect(configured.paths).to eq(["/", "/pricing?locale=en"])
    expect(configured).to be_frozen
    expect(configured.paths).to be_frozen
  end

  ["//other.example/private", "https://other.example", "/bad\\path", "/bad\npath", "/path#fragment",
   "relative"].each do |path|
    it "rejects the unsafe target #{path.inspect}" do
      configuration.paths = [path]

      expect { configuration.validate! }.to raise_error(InertiaRailsSsrCache::ConfigurationError)
    end
  end

  ["file:///tmp", "https://user:password@public.example", "https://public.example/", "https://public.example?x=1",
   "https://public.example#fragment"].each do |origin|
    it "rejects the unsafe origin #{origin.inspect}" do
      configuration.origin = origin

      expect { configuration.validate! }.to raise_error(InertiaRailsSsrCache::ConfigurationError)
    end
  end

  it "bounds distinct targets and preserves request query order" do
    configuration.paths = Array.new(75, "/?b=2&a=1")

    expect(configuration.validate!.paths).to eq(["/?b=2&a=1"])
  end

  it "rejects more than fifty distinct paths" do
    configuration.paths = Array.new(51) { |index| "/#{index}" }

    expect { configuration.validate! }.to raise_error(InertiaRailsSsrCache::ConfigurationError, /at most 50/)
  end

  ["", "release/other", "release\n", ".hidden", "a" * 129, nil].each do |release|
    it "rejects unsupported release token #{release.inspect}" do
      expect { described_class.validate_release(release) }
        .to raise_error(InertiaRailsSsrCache::ConfigurationError)
    end
  end

  it "rejects empty target sets" do
    configuration.paths = []

    expect { configuration.validate! }.to raise_error(InertiaRailsSsrCache::ConfigurationError, /nonempty/)
  end

  it "rejects an origin changed in a serialized job" do
    configuration.validate!

    expect { configuration.verify_targets!("https://other.example", ["/"]) }
      .to raise_error(InertiaRailsSsrCache::ConfigurationError, /no longer registered/)
  end

  it "rejects removed or unregistered queued paths" do
    configuration.validate!

    expect { configuration.verify_targets!(configuration.origin, ["/private"]) }
      .to raise_error(InertiaRailsSsrCache::ConfigurationError, /no longer registered/)
  end
end
