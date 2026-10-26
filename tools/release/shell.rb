# frozen_string_literal: true

require "open3"
require "shellwords"

module Release
  # Runs commands from a fixed directory. `run` keeps the terminal attached, so
  # RubyGems and npm can prompt for one-time passwords.
  #
  # An unbundled shell clears the Bundler environment that `bundle exec rake` sets, so a
  # command in another checkout uses that checkout's Gemfile and code, not the caller's.
  class Shell
    attr_reader :root

    def initialize(root, unbundled: false)
      @root = root.to_s
      @unbundled = unbundled
    end

    def run(*command, env: {})
      puts "+ #{Shellwords.join(command)}"
      environment { system(env, *command, chdir: root, exception: true) }
    end

    # Runs a command attached to the terminal, for prompts such as npm login.
    def success_interactive?(*command)
      puts "+ #{Shellwords.join(command)}"
      environment { system(*command, chdir: root) }
    end

    def success?(*command)
      environment { system(*command, chdir: root, out: File::NULL, err: File::NULL) }
    end

    def capture(*command)
      output, status = environment { Open3.capture2(*command, chdir: root) }
      raise "Command failed: #{Shellwords.join(command)}" unless status.success?

      output.strip
    end

    private

    def environment(&)
      @unbundled && defined?(Bundler) ? Bundler.with_unbundled_env(&) : yield
    end
  end
end
