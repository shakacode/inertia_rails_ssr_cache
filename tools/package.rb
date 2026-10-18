# frozen_string_literal: true

require "bundler"
require "fileutils"
require "json"
require "rubygems/package"
require "tmpdir"
require "zlib"
require_relative "commands"
require_relative "license_check"
require_relative "../lib/inertia_rails_ssr_cache/version"

module PackageCheck
  OUTPUT = Development::ROOT.join("tmp/packages")
  NAME = "inertia-rails-ssr-cache"
  VERSION = InertiaRailsSsrCache::VERSION

  def self.run
    FileUtils.mkdir_p(OUTPUT)
    check_versions
    Development.pnpm("--filter", NAME, "pack", "--pack-destination", OUTPUT.to_s)
    npm = OUTPUT.join("#{NAME}-#{VERSION}.tgz").to_s
    Development.pnpm("publint", "--strict", npm)
    Development.pnpm("attw", npm, "--profile", "esm-only")
    npm_smoke(npm)
    gem = OUTPUT.join("inertia_rails_ssr_cache-#{VERSION}.gem").to_s
    Development.run("gem", "build", "inertia_rails_ssr_cache.gemspec", "--output", gem, "--strict")
    gem_smoke(gem)
  end

  def self.check_versions
    %w[package.json packages/inertia-rails-ssr-cache/package.json].each do |path|
      package = JSON.parse(Development::ROOT.join(path).read)
      raise "Version mismatch: #{path}" unless package.fetch("version") == VERSION
    end
    LicenseCheck.sources
  end

  def self.npm_smoke(archive)
    files = npm_files(archive)
    %w[package/LICENSE.md package/README.md package/dist/index.js package/dist/index.d.ts].each do |path|
      raise "Missing npm artifact file: #{path}" unless files.include?(path)
    end
    raise "Unexpected npm artifact file" unless files.all? { |path| npm_path?(path) }

    npm_consumer(archive)
  end

  def self.npm_path?(path)
    path.match?(%r{\Apackage/(dist/|LICENSE\.md\z|README\.md\z|package\.json\z)})
  end

  def self.npm_files(archive)
    files = []
    Zlib::GzipReader.open(archive) do |gzip|
      Gem::Package::TarReader.new(gzip).each { |entry| files << entry.full_name if entry.file? }
    end
    files
  end

  def self.npm_consumer(archive)
    Dir.mktmpdir("npm-consumer-", Development::ROOT.join("tmp")) do |directory|
      Development.run("npm", "install", "--prefix", directory, "--cache", Development::ROOT.join("tmp/npm-cache").to_s,
                      "--offline", "--ignore-scripts", "--no-audit", "--no-fund", archive)
      File.write(File.join(directory, "smoke.mjs"), npm_consumer_code)
      Development.run("node", File.join(directory, "smoke.mjs"))
    end
  end

  def self.npm_consumer_code
    <<~JS
      import assert from 'node:assert/strict';
      import { guardRelease } from '#{NAME}';
      const render = guardRelease('package-smoke', (page) => page.version);
      assert.equal(render({version: 'package-smoke'}), 'package-smoke');
      assert.throws(() => render({version: 'other'}));
    JS
  end

  def self.gem_smoke(archive)
    package = Gem::Package.new(archive)
    LicenseCheck.gem(package)
    raise "Unexpected gem artifact file" unless package.contents.all? do |path|
      path.match?(%r{\A(lib/|sig/|LICENSE\.md\z|README\.md\z)})
    end

    gem_consumer(package)
  end

  def self.gem_consumer(package)
    Dir.mktmpdir("gem-consumer-", Development::ROOT.join("tmp")) do |directory|
      package.extract_files(directory)
      File.write(File.join(directory, "inertia_rails_ssr_cache.gemspec"), package.spec.to_ruby)
      File.write(File.join(directory, "Gemfile"), "source \"https://rubygems.org\"\ngemspec\n")
      env = gem_environment(directory)
      Development.run("bundle", "lock", "--local", env: env)
      Development.run("bundle", "exec", "ruby", "-I", File.join(directory, "lib"), "-e", gem_consumer_code, env: env)
    end
  end

  def self.gem_environment(directory)
    env = { "PACKAGED_GEM" => directory, "BUNDLE_GEMFILE" => File.join(directory, "Gemfile"),
            "BUNDLE_LOCKFILE" => File.join(directory, "Gemfile.lock"), "BUNDLE_FROZEN" => "false" }
    path = Bundler.settings[:path]
    env["BUNDLE_PATH"] = File.expand_path(path, Development::ROOT) if path
    env
  end

  def self.gem_consumer_code
    <<~RUBY
      require File.join(ENV.fetch("PACKAGED_GEM"), "lib/inertia_rails_ssr_cache")
      abort "Unexpected version" unless InertiaRailsSsrCache::VERSION == "#{VERSION}"
      files = $LOADED_FEATURES.select do |path|
        path.end_with?("/lib/inertia_rails_ssr_cache.rb") || path.include?("/lib/inertia_rails_ssr_cache/")
      end
      package_root = File.join(ENV.fetch("PACKAGED_GEM"), "")
      abort "Source checkout leaked into consumer" unless files.all? { |path| path.start_with?(package_root) }
      abort "Missing public API" unless InertiaRailsSsrCache.respond_to?(:warm_later)
    RUBY
  end
end

PackageCheck.run
