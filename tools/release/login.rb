# frozen_string_literal: true

require "open3"

module Release
  # Makes sure npm and RubyGems can publish, signing in interactively when they cannot,
  # as react_on_rails' release task does for npm.
  class Login
    NPM_REGISTRY = "https://registry.npmjs.org/"

    def initialize(shell:, interactive: $stdin.tty?, credentials: File.expand_path("~/.gem/credentials"))
      @shell = shell
      @interactive = interactive
      @credentials = credentials
    end

    # Returns the npm user name, or nil when not logged in.
    def npm
      user = npm_user
      return user if user || !@interactive

      puts "npm: not logged in. Running npm login..."
      @shell.success_interactive?("npm", "login", "--registry", NPM_REGISTRY)
      npm_user
    end

    # Returns true when RubyGems has an API key to push with.
    def rubygems?
      return true if rubygems_credentials?
      return false unless @interactive

      puts "RubyGems: no credentials. Running gem signin..."
      @shell.success_interactive?("gem", "signin")
      rubygems_credentials?
    end

    private

    def npm_user
      output, status = Open3.capture2e("npm", "whoami", "--registry", NPM_REGISTRY, chdir: @shell.root)
      output.strip if status.success?
    end

    def rubygems_credentials?
      return true if ENV.fetch("GEM_HOST_API_KEY", "").strip != ""

      File.file?(@credentials) && File.read(@credentials).match?(/^:rubygems_api_key:\s*\S/)
    end
  end
end
