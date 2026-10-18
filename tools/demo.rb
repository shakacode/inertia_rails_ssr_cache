# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "socket"
require "tmpdir"
require_relative "commands"
require_relative "demo/processes"
require_relative "demo/proof"

# Local, same-host demo supervisor. It never configures the library's queue backend.
class Demo
  ROOT = Development::ROOT
  APP = ROOT.join("examples/demo")

  def self.free_ports
    TCPServer.open("127.0.0.1", 0) { |web| TCPServer.open("127.0.0.1", 0) { |ssr| [web.addr[1], ssr.addr[1]] } }
  end

  def initialize(directory: ENV.fetch("DEMO_RUNTIME", ROOT.join("tmp/demo").to_s),
                 web_port: ENV.fetch("DEMO_WEB_PORT", "3300"), ssr_port: ENV.fetch("DEMO_SSR_PORT", "13373"))
    @directory = File.expand_path(directory)
    @environment = {
      "DEMO_RUNTIME" => @directory, "DEMO_WEB_PORT" => web_port.to_s, "DEMO_SSR_PORT" => ssr_port.to_s,
      "APP_RELEASE" => ENV.fetch("APP_RELEASE", "demo-v1"), "RAILS_ENV" => "demo",
      "BUNDLE_GEMFILE" => File.expand_path(ENV.fetch("BUNDLE_GEMFILE", "Gemfile"), ROOT)
    }
    @processes = DemoProcesses.new(@environment, APP)
  end

  def start
    with_services do
      start_worker
      warm
      puts "Demo ready: #{origin}\nShared cache and queue: #{@directory}\nPress Ctrl-C to stop."
      keep_running
    end
  rescue Interrupt
    puts "Demo stopped."
  end

  def warm
    job_id = command("enqueue").fetch("job_id")
    wait_for_job(job_id)
    puts JSON.generate(job_id: job_id, status: "finished")
    job_id
  end

  def verify
    with_services do
      job_id = command("enqueue").fetch("job_id")
      raise "Job executed without the worker" unless command("status", job_id).fetch("status") == "pending"

      start_worker
      wait_for_job(job_id)
      responses = Array.new(2) { @processes.get(origin, "/") }
      proof = verify_requests(responses)
      puts JSON.generate(proof.merge(job_id: job_id, status: "passed", pending_before_worker: true))
    end
  end

  private

  def keep_running
    loop do
      @processes.check
      sleep 1
    end
  end

  def verify_requests(responses)
    DemoProof.new(@directory, @environment.fetch("APP_RELEASE")).verify(responses)
  end

  def origin
    "http://127.0.0.1:#{@environment.fetch('DEMO_WEB_PORT')}"
  end

  def with_services(&block)
    FileUtils.mkdir_p(@directory)
    File.open(File.join(@directory, "demo.lock"), "w") do |lock|
      raise "A demo already owns #{@directory}" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

      serve(&block)
    end
  end

  def serve
    prepare
    start_servers
    yield
  ensure
    @processes.close
  end

  def prepare
    Development.pnpm("build")
    Development.run("node", APP.join("build.mjs").to_s, env: @environment)
    command("prepare")
  end

  def start_servers
    @processes.launch("ssr", "node", File.join(@directory, "ssr.mjs"))
    @processes.wait("SSR startup") { File.read(log_path("ssr")).include?("Inertia SSR server started.") }
    @processes.launch("web", "bundle", "exec", "puma", "--bind", origin.sub("http:", "tcp:"),
                      "--threads", "1:3", APP.join("config.ru").to_s)
    @processes.wait("web startup") { @processes.get(origin, "/up").code == "200" }
  end

  def start_worker
    @processes.launch("worker", "bundle", "exec", "ruby", APP.join("bin/rails").to_s, "solid_queue:start")
  end

  def log_path(name)
    File.join(@directory, "#{name}.log")
  end

  def command(*arguments)
    stdout, stderr, status = Open3.capture3(@environment, "bundle", "exec", "ruby",
                                            APP.join("commands.rb").to_s, *arguments, chdir: ROOT)
    raise "Demo command failed: #{arguments.first}\n#{stderr}\n#{stdout}" unless status.success?

    JSON.parse(stdout.lines.last || "")
  end

  def wait_for_job(job_id)
    @processes.wait("job #{job_id}") do
      result = command("status", job_id)
      raise "Warm job failed: #{result.fetch('error')}" if result.fetch("status") == "failed"

      result.fetch("status") == "finished"
    end
  end
end
