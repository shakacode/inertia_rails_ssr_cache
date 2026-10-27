# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "../../tools/release"

RSpec.describe Release, :aggregate_failures do
  describe Release::Version do
    it "maps RubyGems prerelease syntax to npm syntax" do
      version = described_class.new("v0.2.0.rc.1")
      expect([version.gem, version.npm, version.tag]).to eq(%w[0.2.0.rc.1 0.2.0-rc.1 v0.2.0.rc.1])
      expect([version.prerelease?, version.npm_dist_tag]).to eq([true, "next"])
      expect(described_class.new("0.1.0").npm_dist_tag).to eq("latest")
    end

    it "rejects versions the two registries would spell differently" do
      expect { described_class.new("0.1") }.to raise_error(ArgumentError)
      expect { described_class.new("0.1.0-rc.1") }.to raise_error(ArgumentError)
    end

    it "agrees with the repository's version files" do
      current = InertiaRailsSsrCache::VERSION
      expect(described_class.new(current).mismatched_files(Development::ROOT)).to be_empty
      expect(described_class.new("99.0.0").mismatched_files(Development::ROOT).size).to eq(3)
    end
  end

  describe Release::Changelog do
    let(:changelog) do
      described_class.new(<<~MD)
        # Changelog

        ## 0.2.0 — Unreleased

        - Next.

        ## 0.1.0 — 2026-10-18

        First release.

        - Item.
      MD
    end

    it "reads the newest version and whether a section is dated" do
      expect(changelog.latest_version).to eq("0.2.0")
      expect([changelog.dated?("0.2.0"), changelog.dated?("0.1.0"), changelog.dated?("9.9.9")])
        .to eq([false, true, false])
      expect([changelog.date("0.1.0"), changelog.date("0.2.0")]).to eq(["2026-10-18", nil])
    end

    it "returns one section's body" do
      expect(changelog.section("0.1.0")).to eq("First release.\n\n- Item.")
      expect(changelog.section("0.2.0")).to eq("- Next.")
      expect(changelog.section("9.9.9")).to be_nil
    end

    it "has a dated section for the repository's current version" do
      changelog = Release.changelog
      expect(changelog.dated?(InertiaRailsSsrCache::VERSION)).to be(true)
    end
  end

  describe Release::Registry do
    let(:version) { Release::Version.new("0.1.0") }
    let(:documents) do
      {
        "https://rubygems.org/api/v1/versions/inertia_rails_ssr_cache.json" => [
          { "number" => "0.1.0", "sha" => "abc" }
        ],
        "https://registry.npmjs.org/inertia-rails-ssr-cache" => {
          "versions" => { "0.1.0" => { "dist" => { "integrity" => "sha512-x" } } }
        }
      }
    end

    it "finds published checksums and treats missing packages as absent" do
      registry = described_class.new(fetch: documents.method(:[]))
      expect([registry.gem_sha256(version), registry.npm_integrity(version)]).to eq(%w[abc sha512-x])
      empty = described_class.new(fetch: ->(_url) {})
      expect([empty.gem_sha256(version), empty.npm_integrity(version)]).to eq([nil, nil])
    end

    it "compares published and local contents" do
      expect(described_class.state(nil, "a")).to eq(:absent)
      expect(described_class.state("a", "a")).to eq(:same)
      expect(described_class.state("b", "a")).to eq(:different)
    end

    it "computes the checksums the registries publish" do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "artifact")
        File.write(path, "bytes")
        expect(described_class.local_gem_sha256(path)).to eq(Digest::SHA256.hexdigest("bytes"))
        expect(described_class.local_npm_integrity(path))
          .to eq("sha512-#{Base64.strict_encode64(Digest::SHA512.digest('bytes'))}")
      end
    end
  end

  describe Release::Build do
    it "removes its worktree when the build fails" do
      shell = instance_double(Release::Shell, success?: true)
      allow(shell).to receive(:run).and_raise("setup failed")
      build = described_class.new(shell: shell, commit: "abc", version: Release::Version.new("0.1.0"))
      directory = nil
      allow(Dir).to(receive(:mktmpdir).and_wrap_original { |original, *args| directory = original.call(*args) })
      expect { build.run }.to raise_error("setup failed")
      build.cleanup
      expect(File.exist?(directory)).to be(false)
      expect(shell).to have_received(:success?).with("git", "worktree", "remove", "--force", directory)
    end
  end

  describe Release::GithubRelease do
    it "titles the release with the changelog date, not today's" do
      shell = instance_double(Release::Shell, success?: true, run: true)
      changelog = Release::Changelog.new("## 0.1.0 — 2026-10-18\n\nFirst release.\n")
      described_class.new(shell: shell, version: Release::Version.new("0.1.0"), changelog: changelog,
                          dry_run: false).run
      expect(shell).to have_received(:run).with("gh", "release", "edit", "v0.1.0", "--title", "v0.1.0 (2026-10-18)",
                                                "--notes-file", kind_of(String))
    end
  end

  describe Release::Shell do
    it "hides the caller's Bundler environment from an unbundled checkout" do
      script = 'print ENV.fetch("BUNDLE_GEMFILE", "unset")'
      bundled = described_class.new(Dir.pwd).capture(RbConfig.ruby, "-e", script)
      unbundled = described_class.new(Dir.pwd, unbundled: true).capture(RbConfig.ruby, "-e", script)
      expect(bundled).to eq(ENV.fetch("BUNDLE_GEMFILE"))
      expect(unbundled).to eq("unset")
    end
  end

  describe Release::Login do
    let(:directory) { Dir.mktmpdir("release-login-") }
    let(:credentials) { File.join(directory, "credentials") }
    let(:shell) { instance_double(Release::Shell, root: directory, success_interactive?: true) }

    after { FileUtils.remove_entry(directory) }

    def login(interactive:)
      described_class.new(shell: shell, interactive: interactive, credentials: credentials)
    end

    it "runs gem signin when RubyGems has no credentials and a terminal is attached" do
      allow(shell).to receive(:success_interactive?).with("gem", "signin") do
        File.write(credentials, "---\n:rubygems_api_key: rubygems_abc\n")
      end
      expect { expect(login(interactive: true).rubygems?).to be(true) }.to output(/Running gem signin/).to_stdout
      expect(shell).to have_received(:success_interactive?).with("gem", "signin")
    end

    it "only reports missing RubyGems credentials without a terminal" do
      expect(login(interactive: false).rubygems?).to be(false)
      expect(shell).not_to have_received(:success_interactive?)
    end

    it "accepts existing RubyGems credentials without signing in" do
      File.write(credentials, "---\n:rubygems_api_key: rubygems_abc\n")
      expect(login(interactive: true).rubygems?).to be(true)
      expect(shell).not_to have_received(:success_interactive?)
    end
  end

  describe Release::Publish do
    let(:directory) { Dir.mktmpdir("release-publish-") }
    let(:version) { Release::Version.new("0.1.0") }
    let(:build) do
      gem_path = File.join(directory, "a.gem")
      npm_path = File.join(directory, "a.tgz")
      File.write(gem_path, "gem")
      File.write(npm_path, "npm")
      Struct.new(:gem_path, :npm_path).new(gem_path, npm_path)
    end
    let(:shell) { instance_double(Release::Shell, run: true) }

    after { FileUtils.remove_entry(directory) }

    def registry(gem:, npm:)
      instance_double(Release::Registry, gem_sha256: gem, npm_integrity: npm)
    end

    def publisher(registry)
      described_class.new(shell: shell, version: version, build: build, registry: registry, sleeper: ->(_) {})
    end

    it "refuses to publish over a version with different contents" do
      expect { publisher(registry(gem: "other", npm: nil)).plan }.to raise_error(/rubygems|gem already has/)
      expect(shell).not_to have_received(:run)
    end

    it "tells the operator to rerun when a registry is still processing" do
      gem_sha = Release::Registry.local_gem_sha256(build.gem_path)
      processing = publisher(registry(gem: gem_sha, npm: nil))
      expect { processing.send(:verify) }.to raise_error(/npm did not serve 0.1.0 within 10 minutes. Rerun/)
                                         .and output(/Waiting for npm/).to_stdout
    end

    it "succeeds when a registry starts serving during the final wait" do
      gem_sha = Release::Registry.local_gem_sha256(build.gem_path)
      integrity = nil
      published = instance_double(Release::Registry, gem_sha256: gem_sha)
      allow(published).to receive(:npm_integrity) { integrity }
      sleeps = 0
      sleeper = lambda do |_seconds|
        sleeps += 1
        integrity = Release::Registry.local_npm_integrity(build.npm_path) if sleeps == described_class::VERIFY_ATTEMPTS
      end
      verifier = described_class.new(shell: shell, version: version, build: build, registry: published,
                                     sleeper: sleeper)
      expect { verifier.send(:verify) }.to output(/Both registries serve 0.1.0/).to_stdout
    end

    it "skips a registry that already serves identical bytes" do
      gem_sha = Release::Registry.local_gem_sha256(build.gem_path)
      npm_integrity = Release::Registry.local_npm_integrity(build.npm_path)
      published = registry(gem: gem_sha, npm: npm_integrity)
      expect { publisher(published).run }.to output(/Both registries serve 0.1.0/).to_stdout
      expect(shell).not_to have_received(:run)
    end
  end
end
