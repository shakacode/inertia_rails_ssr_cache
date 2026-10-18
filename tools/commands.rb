# frozen_string_literal: true

require "json"
require "open3"
require "pathname"

module Development
  ROOT = Pathname.new(File.expand_path("..", __dir__))

  def self.run(*command, env: {})
    puts "+ #{command.join(' ')}"
    system(env, *command, chdir: ROOT.to_s, exception: true)
  end

  def self.pnpm(*)
    expected = JSON.parse(ROOT.join("package.json").read).fetch("packageManager").split("@").last
    if pnpm_version_matches?(expected)
      run("pnpm", *)
    else
      run("corepack", "pnpm", *, env: { "COREPACK_HOME" => ROOT.join("tmp/corepack").to_s })
    end
  end

  def self.pnpm_version_matches?(expected)
    installed, status = Open3.capture2("pnpm", "--version", chdir: ROOT.to_s)
    status.success? && installed.strip == expected
  rescue Errno::ENOENT
    false
  end
  private_class_method :pnpm_version_matches?
end
