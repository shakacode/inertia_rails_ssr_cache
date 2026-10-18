# frozen_string_literal: true

module FixtureBenchmark
  WARMUP_COUNT = 5

  def self.call(samples)
    WARMUP_COUNT.times { request }
    durations = Array.new(samples) { measure }
    statistics(durations).merge(
      samples: samples, warmup_requests: WARMUP_COUNT, request_ms: durations,
      rails: Rails.version, inertia_rails: InertiaRails::VERSION
    )
  end

  def self.request
    Rack::MockRequest.new(Rails.application).get(
      "http://fixture.test/stable", "HTTP_HOST" => "fixture.test", "HTTP_ACCEPT" => "text/html"
    )
  end

  def self.measure
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = request
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    unless response.status == 200 && response.body.include?("data-build=")
      raise "Benchmark did not receive real SSR HTML"
    end

    elapsed.round(4)
  end

  def self.statistics(durations)
    ordered = durations.sort
    {
      p50_ms: ordered.fetch((ordered.length * 0.50).ceil - 1),
      p95_ms: ordered.fetch((ordered.length * 0.95).ceil - 1)
    }
  end
end
