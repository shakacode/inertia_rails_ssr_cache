# frozen_string_literal: true

require "open3"
require "shellwords"

module Release
  # Runs commands from a fixed directory. `run` keeps the terminal attached, so
  # RubyGems and npm can prompt for one-time passwords.
  class Shell
    attr_reader :root

    def initialize(root)
      @root = root.to_s
    end

    def run(*command, env: {})
      puts "+ #{Shellwords.join(command)}"
      system(env, *command, chdir: root, exception: true)
    end

    # Runs a command attached to the terminal, for prompts such as npm login.
    def success_interactive?(*command)
      puts "+ #{Shellwords.join(command)}"
      system(*command, chdir: root)
    end

    def success?(*command)
      system(*command, chdir: root, out: File::NULL, err: File::NULL)
    end

    def capture(*command)
      output, status = Open3.capture2(*command, chdir: root)
      raise "Command failed: #{Shellwords.join(command)}" unless status.success?

      output.strip
    end
  end
end
