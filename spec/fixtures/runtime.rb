# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
require "uri"

class FixtureRuntime
  ROOT = File.expand_path("../..", __dir__)
  SSR_MODULE = URI::Generic.build(scheme: "file", path: File.join(__dir__, "ssr.mjs")).to_s
  Renderer = Data.define(:url, :counter, :pid)

  attr_reader :directory

  def initialize
    @directory = Dir.mktmpdir("inertia-runtime-")
    @renderers = []
  end

  def start_renderer(release)
    port = TCPServer.open("127.0.0.1", 0) { |listener| listener.addr[1] }
    entry, counter, log = renderer_files(release, port)
    pid = Process.spawn("node", entry, out: log, err: log, chdir: ROOT)
    renderer = Renderer.new(url: "http://127.0.0.1:#{port}", counter: counter, pid: pid)
    @renderers << renderer
    wait_for_server(pid, log)
    renderer
  end

  def render_count(renderer)
    File.exist?(renderer.counter) ? File.foreach(renderer.counter).count : 0
  end

  def run(mode, paths, renderer:, release: "release-a", scenario: "normal")
    stdout, stderr, status = Open3.capture3(
      environment(renderer, release, scenario),
      RbConfig.ruby, "-Ilib", File.join(__dir__, "worker.rb"), mode, *paths, chdir: ROOT
    )
    unless status.success?
      raise "Fixture worker failed (#{status.exitstatus}): #{stderr.lines.first(12).join}\n#{stdout}"
    end

    JSON.parse(stdout.lines.last || "")
  end

  def close
    @renderers.each do |renderer|
      Process.kill("TERM", renderer.pid)
      Process.wait(renderer.pid)
    rescue Errno::ESRCH, Errno::ECHILD
      next
    end
    FileUtils.remove_entry(directory)
  end

  private

  def renderer_files(release, port)
    counter = File.join(directory, "renders-#{@renderers.length}.jsonl")
    entry = File.join(directory, "entry-#{@renderers.length}.mjs")
    File.write(entry, <<~JS)
      import { startFixture } from #{JSON.generate(SSR_MODULE)};
      startFixture(#{JSON.generate(release)}, #{port}, #{JSON.generate(counter)});
    JS
    [entry, counter, File.join(directory, "node-#{@renderers.length}.log")]
  end

  def environment(renderer, release, scenario)
    {
      "FIXTURE_RELEASE" => release,
      "FIXTURE_SSR_URL" => renderer.url,
      "FIXTURE_CACHE" => File.join(directory, "cache"),
      "FIXTURE_SCENARIO" => scenario
    }
  end

  def wait_for_server(pid, log)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      return if File.read(log).include?("Inertia SSR server started.")
      if Process.waitpid(pid, Process::WNOHANG) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "Node fixture did not start: #{File.read(log)}"
      end

      sleep 0.02
    end
  end
end
