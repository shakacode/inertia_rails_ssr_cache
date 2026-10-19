# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "uri"

module Release
  # What a registry already holds for a version, compared with a locally built artifact.
  class Registry
    GEM_NAME = "inertia_rails_ssr_cache"
    NPM_NAME = "inertia-rails-ssr-cache"

    # :absent, :same (published from identical bytes), or :different.
    def self.state(published, local)
      return :absent if published.nil?

      published == local ? :same : :different
    end

    def initialize(fetch: method(:get_json))
      @fetch = fetch
    end

    # SHA-256 hex digest of the published .gem, or nil when the version is absent.
    def gem_sha256(version)
      versions = @fetch.call("https://rubygems.org/api/v1/versions/#{GEM_NAME}.json") || []
      versions.find { |entry| entry["number"] == version.gem }&.fetch("sha")
    end

    # npm "sha512-..." integrity of the published tarball, or nil when the version is absent.
    def npm_integrity(version)
      document = @fetch.call("https://registry.npmjs.org/#{NPM_NAME}") || {}
      document.dig("versions", version.npm, "dist", "integrity")
    end

    def self.local_gem_sha256(path)
      Digest::SHA256.file(path).hexdigest
    end

    def self.local_npm_integrity(path)
      "sha512-#{Base64.strict_encode64(Digest::SHA512.file(path).digest)}"
    end

    private

    def get_json(url)
      response = Net::HTTP.get_response(URI(url))
      return if response.is_a?(Net::HTTPNotFound)
      raise "#{url} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
