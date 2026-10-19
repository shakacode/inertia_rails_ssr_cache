# frozen_string_literal: true

require "date"
require_relative "commands"
require_relative "release/build"
require_relative "release/changelog"
require_relative "release/github_release"
require_relative "release/preflight"
require_relative "release/publish"
require_relative "release/shell"
require_relative "release/version"

# Releases the gem and the npm package together. The version bump is a merged PR;
# this task never commits or pushes to main. See docs/releasing.md.
module Release
  def self.changelog
    Changelog.new(Development::ROOT.join("CHANGELOG.md").read)
  end

  def self.version(requested)
    requested = changelog.latest_version if requested.to_s.strip.empty?
    Version.new(requested)
  end

  def self.release(requested, dry_run:)
    Runner.new(version(requested), dry_run: dry_run).run
  end

  def self.sync_github_release(requested, dry_run:)
    shell = Shell.new(Development::ROOT)
    GithubRelease.new(shell: shell, version: version(requested), changelog: changelog, dry_run: dry_run).run
  end

  # The release sequence: preflight, build, confirm, tag, publish, push tag, GitHub release.
  class Runner
    def initialize(version, dry_run:)
      @version = version
      @dry_run = dry_run
      @shell = Shell.new(Development::ROOT)
      @changelog = Release.changelog
      @preflight = Preflight.new(shell: @shell, version: version, changelog: @changelog, dry_run: dry_run)
    end

    def run
      puts "#{'DRY RUN: ' if @dry_run}Releasing #{@version.gem} (npm #{@version.npm}, dist-tag " \
           "#{@version.npm_dist_tag})"
      @preflight.run
      build = Build.new(shell: @shell, commit: @preflight.head, version: @version).run
      begin
        release(build)
      ensure
        build.cleanup
      end
    end

    private

    def release(build)
      publish = Publish.new(shell: @shell, version: @version, build: build)
      publish.plan
      puts build.summary
      report_registries(publish)
      return dry_run_report if @dry_run

      confirm!
      tag!
      publish.run
      @shell.run("git", "push", "origin", "refs/tags/#{@version.tag}")
      GithubRelease.new(shell: @shell, version: @version, changelog: @changelog, dry_run: false).run
    end

    def report_registries(publish)
      puts "RubyGems: #{publish.gem_state}   npm: #{publish.npm_state}   (absent = will publish, same = skip)"
    end

    def confirm!
      print "Type #{@version.gem} to tag #{@preflight.head[0, 7]} and publish: "
      abort "Release cancelled." unless $stdin.gets.to_s.strip == @version.gem
    end

    def tag!
      existing = @shell.success?("git", "rev-parse", "--verify", "--quiet", "refs/tags/#{@version.tag}")
      if existing
        tagged = @shell.capture("git", "rev-parse", "#{@version.tag}^{commit}")
        raise "Tag #{@version.tag} exists on #{tagged[0, 7]}, not #{@preflight.head[0, 7]}" unless
          tagged == @preflight.head
      else
        @shell.run("git", "tag", "--annotate", @version.tag, "--message", "inertia_rails_ssr_cache #{@version.gem}",
                   @preflight.head)
      end
    end

    def dry_run_report
      puts "DRY RUN: would tag #{@version.tag} on #{@preflight.head[0, 7]}, gem push and npm publish the " \
           "artifacts above (each asks for a one-time password), push the tag, and create the GitHub release."
      puts "To release: bundle exec rake \"release[#{@version.gem}]\""
    end
  end
end
