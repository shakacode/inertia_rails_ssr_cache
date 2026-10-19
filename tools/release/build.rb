# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "registry"
require_relative "shell"

module Release
  # Validates and packages an exact commit in a detached worktree, so the artifacts
  # come from committed files only.
  class Build
    attr_reader :gem_path, :npm_path

    def initialize(shell:, commit:, version:)
      @shell = shell
      @commit = commit
      @version = version
    end

    def run
      @directory = Dir.mktmpdir("inertia-rails-ssr-cache-release-")
      @shell.run("git", "worktree", "add", "--detach", @directory, @commit)
      checkout = Shell.new(@directory)
      %w[bin/setup bin/validate bin/audit].each { |command| checkout.run(command) }
      locate_artifacts
      self
    end

    def summary
      [
        "Commit:  #{@commit}",
        "Gem:     #{gem_path}",
        "         sha256 #{Registry.local_gem_sha256(gem_path)}",
        "npm:     #{npm_path}",
        "         #{Registry.local_npm_integrity(npm_path)}"
      ].join("\n")
    end

    def cleanup
      return unless @directory && File.directory?(@directory)

      @shell.run("git", "worktree", "remove", "--force", @directory)
    end

    private

    def locate_artifacts
      packages = File.join(@directory, "tmp/packages")
      @gem_path = File.join(packages, "#{Registry::GEM_NAME}-#{@version.gem}.gem")
      @npm_path = File.join(packages, "#{Registry::NPM_NAME}-#{@version.npm}.tgz")
      [@gem_path, @npm_path].each { |path| raise "bin/package did not produce #{path}" unless File.file?(path) }
    end
  end
end
