# frozen_string_literal: true

require "tempfile"

module Release
  # Creates or updates the GitHub release for a pushed tag from its CHANGELOG.md section.
  class GithubRelease
    def initialize(shell:, version:, changelog:, dry_run:)
      @shell = shell
      @version = version
      @changelog = changelog
      @dry_run = dry_run
    end

    def run
      notes = @changelog.section(@version.gem)
      raise "CHANGELOG.md has no section for #{@version.gem}" if notes.nil? || notes.empty?
      return dry_run_report if @dry_run

      raise "Tag #{@version.tag} is not on origin; push it first" unless tag_on_origin?

      publish(notes)
    end

    private

    def publish(notes)
      Tempfile.create(["release-notes-", ".md"]) do |file|
        file.write(notes)
        file.flush
        @shell.run("gh", "release", existing? ? "edit" : "create", *arguments(file.path))
      end
    end

    def arguments(notes_path)
      arguments = [@version.tag, "--title", title, "--notes-file", notes_path]
      arguments << "--verify-tag" unless existing?
      arguments << "--prerelease" if @version.prerelease?
      arguments
    end

    def title
      date = @changelog.date(@version.gem)
      date ? "#{@version.tag} (#{date})" : @version.tag
    end

    def existing?
      @existing = @shell.success?("gh", "release", "view", @version.tag) if @existing.nil?
      @existing
    end

    def tag_on_origin?
      @shell.success?("git", "ls-remote", "--exit-code", "--tags", "origin", "refs/tags/#{@version.tag}")
    end

    def dry_run_report
      puts "DRY RUN: would create or update GitHub release #{@version.tag} from its CHANGELOG.md section" \
           "#{' (prerelease)' if @version.prerelease?}."
    end
  end
end
