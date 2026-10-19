# frozen_string_literal: true

require_relative "lib/inertia_rails_ssr_cache/version"

Gem::Specification.new do |spec|
  spec.name = "inertia_rails_ssr_cache"
  spec.version = InertiaRailsSsrCache::VERSION
  spec.authors = ["Justin Gordon", "ShakaCode"]
  spec.email = ["justin@shakacode.com"]
  spec.summary = "Verified Inertia Rails SSR cache warming through Active Job."
  spec.description = "Warm explicitly registered public routes through the native Inertia SSR cache."
  spec.homepage = "https://github.com/shakacode/inertia_rails_ssr_cache"
  spec.license = "LicenseRef-InertiaRailsSsrCache"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => spec.homepage,
    "documentation_uri" => "#{spec.homepage}#readme",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "license_uri" => "#{spec.homepage}/blob/main/LICENSE.md"
  }
  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "sig/**/*", "README.md", "LICENSE.md"].select do |path|
      File.file?(path)
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.2", "< 8.2"
  spec.add_dependency "activejob", ">= 7.2", "< 8.2"
  spec.add_dependency "activesupport", ">= 7.2", "< 8.2"
  spec.add_dependency "inertia_rails", ">= 3.22", "< 3.24"
  spec.add_dependency "rack", ">= 3.1", "< 4"
  spec.add_dependency "railties", ">= 7.2", "< 8.2"
end
