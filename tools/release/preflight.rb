# frozen_string_literal: true

require "json"
require_relative "login"

module Release
  # Checks that must pass before anything is built or published. In a dry run,
  # problems are reported instead of stopping the run.
  class Preflight
    REQUIRED_CHECKS = ["Static checks, tests and packages", "Ruby 3.3 / Node 22"].freeze

    attr_reader :problems

    def initialize(shell:, version:, changelog:, dry_run:, login: Login.new(shell: shell))
      @shell = shell
      @login = login
      @version = version
      @changelog = changelog
      @dry_run = dry_run
      @problems = []
    end

    def run
      check_git
      check_versions
      check_auth
      check_ci
      report!
    end

    def head
      @head ||= @shell.capture("git", "rev-parse", "HEAD")
    end

    def repository
      @repository ||= @shell.capture("gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner")
    end

    private

    def problem(message)
      @problems << message
    end

    def check_git
      @shell.run("git", "fetch", "--quiet", "--tags", "origin", "main")
      problem("Release from main; current branch is #{branch}") unless branch == "main"
      problem("Working tree has uncommitted changes") unless @shell.capture("git", "status", "--porcelain").empty?
      problem("HEAD is not origin/main; pull or push first") unless head == origin_main
    end

    def origin_main
      @shell.capture("git", "rev-parse", "origin/main")
    end

    def branch
      @shell.capture("git", "branch", "--show-current")
    end

    def check_versions
      mismatched = @version.mismatched_files(@shell.root)
      problem("Version files are not #{@version.gem}: #{mismatched.join(', ')}. Merge a bump PR first") if
        mismatched.any?
      problem("CHANGELOG.md has no dated section for #{@version.gem}") unless @changelog.dated?(@version.gem)
    end

    def check_auth
      problem("GitHub CLI is not authenticated") unless @shell.success?("gh", "auth", "status")
      npm_user = @login.npm
      if npm_user
        puts "npm: logged in as #{npm_user}"
      else
        problem("npm is not logged in; npm login failed or was skipped")
      end
      problem("RubyGems has no credentials; gem signin failed or was skipped") unless @login.rubygems?
    end

    def check_ci
      runs = check_runs
      return problem("GitHub has no CI results for #{head[0, 7]}; push it and wait for CI") unless runs

      REQUIRED_CHECKS.each do |name|
        run = runs.find { |entry| entry["name"] == name }
        problem("CI check #{name.inspect} has not passed on #{head[0, 7]}") unless run&.fetch("conclusion") == "success"
      end
    end

    def check_runs
      JSON.parse(@shell.capture("gh", "api", "repos/#{repository}/commits/#{head}/check-runs",
                                "--jq", "[.check_runs[] | {name, status, conclusion}]"))
    rescue RuntimeError
      nil
    end

    def report!
      return if @problems.empty?

      @problems.each { |message| warn "#{@dry_run ? 'DRY RUN would stop' : 'Stopped'}: #{message}" }
      abort "Release preflight failed." unless @dry_run
    end
  end
end
