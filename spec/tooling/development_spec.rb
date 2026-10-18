# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../tools/commands"

RSpec.describe Development, :aggregate_failures do
  let(:directory) { Dir.mktmpdir("package-manager-path-") }
  let(:expected) { JSON.parse(described_class::ROOT.join("package.json").read).fetch("packageManager").split("@").last }

  after { FileUtils.remove_entry(directory) }

  def executable(name, source)
    File.write(File.join(directory, name), "#!#{RbConfig.ruby}\n#{source}\n", perm: 0o755)
  end

  def recorder
    <<~RUBY
      require "json"
      puts JSON.generate(command: File.basename($PROGRAM_NAME), arguments: ARGV, home: ENV["COREPACK_HOME"])
    RUBY
  end

  def run_pnpm
    Open3.capture3({ "PATH" => directory }, RbConfig.ruby, "-r", described_class::ROOT.join("tools/commands").to_s,
                   "-e", 'Development.pnpm("install", "--frozen-lockfile")')
  end

  def expect_corepack
    executable("corepack", recorder)
    output, error, status = run_pnpm

    expect(status.success?).to be(true), error
    expect(JSON.parse(output.lines.last)).to include(
      "command" => "corepack", "arguments" => %w[pnpm install --frozen-lockfile],
      "home" => described_class::ROOT.join("tmp/corepack").to_s
    )
  end

  it "uses available Corepack when pnpm is missing from PATH" do
    expect_corepack
  end

  it "uses Corepack when pnpm has a different version" do
    executable("pnpm", 'puts "0.0.0"')

    expect_corepack
  end

  it "uses Corepack when pnpm version detection fails" do
    executable("pnpm", "exit 1")

    expect_corepack
  end

  it "uses pnpm directly when its version matches the package manager pin" do
    executable("pnpm", "if ARGV == ['--version']; puts #{expected.inspect}; exit; end\n#{recorder}")
    output, error, status = run_pnpm

    expect(status.success?).to be(true), error
    expect(JSON.parse(output.lines.last)).to include("command" => "pnpm", "arguments" => %w[install --frozen-lockfile])
  end
end
