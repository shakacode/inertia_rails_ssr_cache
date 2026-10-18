# frozen_string_literal: true

require "json"
require_relative "commands"

# Release checks for the license text and the license metadata of both packages.
module LicenseCheck
  SPDX = "LicenseRef-InertiaRailsSsrCache"
  NPM_LICENSE = "SEE LICENSE IN LICENSE.md"
  MANIFESTS = %w[package.json packages/inertia-rails-ssr-cache/package.json].freeze
  PACKAGE_LICENSE = "packages/inertia-rails-ssr-cache/LICENSE.md"
  PUSH_HOST = "https://rubygems.org"

  def self.sources
    text = Development::ROOT.join("LICENSE.md").read
    raise "Draft license text" if text.match?(/DRAFT|not yet in force/)
    raise "Unexpected license text" unless text.include?("SPDX-License-Identifier: #{SPDX}")
    raise "npm LICENSE.md differs from LICENSE.md" unless Development::ROOT.join(PACKAGE_LICENSE).read == text

    manifests
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
  end
end
