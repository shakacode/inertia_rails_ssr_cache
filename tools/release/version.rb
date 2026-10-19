# frozen_string_literal: true

require "json"
require "pathname"
require "rubygems/version"

module Release
  # One release version, in RubyGems and npm syntax, checked against the version files.
  class Version
    GEM_PATTERN = /\A\d+\.\d+\.\d+(?:\.(?:alpha|beta|rc)\.\d+)?\z/
    MANIFESTS = %w[package.json packages/inertia-rails-ssr-cache/package.json].freeze

    attr_reader :gem

    def initialize(gem_version)
      @gem = gem_version.to_s.strip.delete_prefix("v")
      raise ArgumentError, "Invalid release version #{gem_version.inspect}; use 1.2.3 or 1.2.3.rc.1" unless
        @gem.match?(GEM_PATTERN)
    end

    def npm
      gem.sub(/\.(alpha|beta|rc)\./, '-\1.')
    end

    def prerelease?
      Gem::Version.new(gem).prerelease?
    end

    def tag
      "v#{gem}"
    end

    def npm_dist_tag
      prerelease? ? "next" : "latest"
    end

    def ==(other)
      other.is_a?(Version) && other.gem == gem
    end

    # Returns the files whose version differs from this one; empty when all agree.
    def mismatched_files(root)
      root = Pathname.new(root)
      mismatched = []
      mismatched << "lib/inertia_rails_ssr_cache/version.rb" unless version_file(root) == gem
      MANIFESTS.each do |path|
        mismatched << path unless JSON.parse(root.join(path).read).fetch("version") == npm
      end
      mismatched
    end

    private

    def version_file(root)
      root.join("lib/inertia_rails_ssr_cache/version.rb").read[/VERSION = "([^"]+)"/, 1]
    end
  end
end
