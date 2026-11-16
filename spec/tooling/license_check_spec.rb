# frozen_string_literal: true

require_relative "../../tools/license_check"
require_relative "../../tools/release"
require "fileutils"
require "tmpdir"

RSpec.describe LicenseCheck do
  it "accepts the approved license text at the first eligible release" do
    expect { described_class.release!("0.2.0") }.not_to raise_error
  end

  it "refuses the current release version" do
    expect { described_class.release!("0.1.0") }.to raise_error(/0\.2\.0/)
  end

  it "refuses counsel markers and text that is not in force" do
    ["[COUNSEL-1]", "This license is not in force"].each do |draft|
      expect { described_class.release!("0.2.0", text: draft) }.to raise_error(/Draft license text/)
    end
  end

  it "pins the source license bytes" do
    expect { described_class.sources }.not_to raise_error
  end

  it "refuses modified license bytes even with the expected identifier" do
    Dir.mktmpdir do |directory|
      text = Development::ROOT.join("LICENSE.md").binread
      File.binwrite(File.join(directory, "LICENSE.md"), text.sub("The ShakaStack License", "A ShakaStack License"))
      stub_const("Development::ROOT", Pathname.new(directory))

      expect { described_class.sources }.to raise_error("Unexpected license text")
    end
  end

  it "blocks the current version in release preflight" do
    version = Release::Version.new(InertiaRailsSsrCache::VERSION)
    shell = instance_double(Release::Shell, root: Development::ROOT)
    preflight = Release::Preflight.new(shell: shell, version: version, changelog: Release.changelog, dry_run: false)

    preflight.send(:check_versions)

    expect(preflight.problems).to include(/0\.2\.0/)
  end
end
