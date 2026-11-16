# frozen_string_literal: true

require "json"
require "digest"
require "rubygems/version"
require "tmpdir"
require_relative "commands"

# Release checks for the license text and the license metadata of both packages.
module LicenseCheck
  SPDX = "LicenseRef-ShakaStack-1.0-InertiaRailsSsrCache"
  SHA256 = "85a5f1afe31d63bf7627faacf34f2d2a8de823e87ecc9713faea7fb1701ef061"
  RELEASE_FLOOR = Gem::Version.new("0.2.0")
  NPM_LICENSE = "SEE LICENSE IN LICENSE.md"
  MANIFESTS = %w[package.json packages/inertia-rails-ssr-cache/package.json].freeze
  PACKAGE_LICENSE = "packages/inertia-rails-ssr-cache/LICENSE.md"
  PUSH_HOST = "https://rubygems.org"

  def self.sources
    text = Development::ROOT.join("LICENSE.md").binread
    raise "Unexpected license text" unless Digest::SHA256.hexdigest(text) == SHA256
    raise "npm LICENSE.md differs from LICENSE.md" unless Development::ROOT.join(PACKAGE_LICENSE).binread == text

    manifests
  end

  # Draft checks belong to release preflight so validation can inspect proposed text.
  def self.release!(version, text: Development::ROOT.join("LICENSE.md").binread)
    raise "Draft license text" if text.match?(/\[COUNSEL-|not in force/i)
    raise "License requires release 0.2.0 or later" if Gem::Version.new(version) < RELEASE_FLOOR
  end

  def self.manifests
    MANIFESTS.each do |path|
      raise "License mismatch: #{path}" unless manifest(path).fetch("license") == NPM_LICENSE
    end
    raise "Workspace root must stay private" unless manifest("package.json")["private"]
  end

  def self.manifest(path)
    JSON.parse(Development::ROOT.join(path).read)
  end

  def self.gem(package)
    raise "Unexpected gem publication host" unless package.spec.metadata["allowed_push_host"] == PUSH_HOST
    raise "Unexpected gem license" unless package.spec.licenses == [SPDX]
    raise "Missing gem LICENSE.md" unless package.contents.include?("LICENSE.md")

    raise "Unexpected gem LICENSE.md" unless gem_license_sha256(package) == SHA256
  end

  def self.gem_license_sha256(package)
    Dir.mktmpdir("gem-license-") do |directory|
      package.extract_files(directory, "LICENSE.md")
      Digest::SHA256.file(File.join(directory, "LICENSE.md")).hexdigest
    end
  end
end
