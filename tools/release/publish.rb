# frozen_string_literal: true

require_relative "registry"

module Release
  # Publishes both artifacts, skipping a registry that already holds identical bytes,
  # so a partial release can be resumed by rerunning the task.
  class Publish
    # npm can take several minutes to serve a new version ("Your package is being processed").
    VERIFY_ATTEMPTS = 60
    VERIFY_INTERVAL = 10

    def initialize(shell:, version:, build:, registry: Registry.new, sleeper: ->(seconds) { sleep(seconds) })
      @shell = shell
      @version = version
      @build = build
      @registry = registry
      @sleeper = sleeper
    end

    # Raises before publishing anything when a registry holds different bytes.
    def plan
      { gem: gem_state, npm: npm_state }.each do |registry, state|
        raise "#{registry} already has #{@version.gem} with different contents; never republish a version" if
          state == :different
      end
    end

    def run
      plan => { gem: gem_plan, npm: npm_plan }
      push_gem if gem_plan == :absent
      publish_npm if npm_plan == :absent
      verify
    end

    def gem_state
      Registry.state(@registry.gem_sha256(@version), Registry.local_gem_sha256(@build.gem_path))
    end

    def npm_state
      Registry.state(@registry.npm_integrity(@version), Registry.local_npm_integrity(@build.npm_path))
    end

    private

    def push_gem
      puts "RubyGems will ask for your one-time password next."
      @shell.run("gem", "push", @build.gem_path)
    end

    def publish_npm
      puts "npm will ask for your one-time password next."
      @shell.run("npm", "publish", @build.npm_path, "--access", "public", "--tag", @version.npm_dist_tag)
    end

    def verify
      VERIFY_ATTEMPTS.times do |attempt|
        return puts("Both registries serve #{@version.gem} with the built contents.") if published?

        puts "Waiting for #{pending.join(' and ')} to serve #{@version.gem}..." if (attempt % 6).zero?
        @sleeper.call(VERIFY_INTERVAL)
      end
      raise timeout_message
    end

    def timeout_message
      "#{pending.join(' and ')} did not serve #{@version.gem} within " \
        "#{VERIFY_ATTEMPTS * VERIFY_INTERVAL / 60} minutes. Rerun the same release command to resume: " \
        "registries that already serve the built contents are skipped."
    end

    def pending
      [("RubyGems" unless gem_state == :same), ("npm" unless npm_state == :same)].compact
    end

    def published?
      gem_state == :same && npm_state == :same
    end
  end
end
