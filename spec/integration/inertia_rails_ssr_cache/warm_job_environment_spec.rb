# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"

RSpec.describe InertiaRailsSsrCache::WarmJob do
  def boot(mode)
    fixture = File.expand_path("../../fixtures/environment.rb", __dir__)
    Open3.popen3(RbConfig.ruby, "-Ilib", fixture, mode) do |input, output, error, waiter|
      input.close
      raise "Environment fixture failed: #{error.read}" unless wait_for_exit(waiter).success?

      JSON.parse(output.read.lines.last)
    end
  end

  def wait_for_exit(waiter)
    return waiter.value if waiter.join(10)

    Process.kill("KILL", waiter.pid)
    waiter.join
    raise "Environment fixture exceeded its deadline; possible executor deadlock"
  end

  { "reloading" => "config.enable_reloading", "serialized" => "config.allow_concurrency" }.each do |mode, setting|
    it "rejects #{mode} before enqueue and request thread creation", :aggregate_failures do
      result = boot(mode)
      failure = { "accepted" => false, "error" => "InertiaRailsSsrCache::ConfigurationError",
                  "message" => include(setting) }

      expect(result).to include("threads_started" => 0, "requests" => 0, "enqueued_jobs" => 0)
      expect(result.values_at("enqueue", "execution")).to all(include(failure))
    end
  end

  it "allows nonreloading concurrent execution through full request middleware", :aggregate_failures do
    result = boot("supported")

    expect(result).to include("threads_started" => 2, "requests" => 2, "enqueued_jobs" => 1)
    expect(result.fetch("enqueue")).to include("accepted" => true)
    expect(result.fetch("execution")).to include("error" => "InertiaRailsSsrCache::WarmFailed")
  end
end
