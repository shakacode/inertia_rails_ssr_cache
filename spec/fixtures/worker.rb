# frozen_string_literal: true

require "json"
require_relative "application"

mode, *paths = ARGV
release = ENV.fetch("FIXTURE_RELEASE")
origin = "http://fixture.test"
events = []
subscriber = lambda do |*arguments|
  payload = ActiveSupport::Notifications::Event.new(*arguments).payload
  next unless payload[:super_operation] == :fetch

  events << { key: payload[:key], hit: payload[:hit] }
end

output = ActiveSupport::Notifications.subscribed(subscriber, "cache_read.active_support") do
  case mode
  when "warm", "execute"
    InertiaRailsSsrCache.configure do |config|
      config.origin = origin
      config.paths = paths
    end
    if mode == "execute"
      require_relative "execution_context"
      next FixtureExecutionContext.call(origin, paths, release)
    end
    begin
      report = InertiaRailsSsrCache::WarmJob.perform_now(origin, paths, release)
    rescue InertiaRailsSsrCache::WarmFailed => e
      report = e.report
    end
    { success: report.success?, release: report.release, results: report.results.map do |result|
      { path: result.path, outcome: result.outcome, initial_cache_hit: result.initial_cache_hit }
    end }
  when "benchmark"
    require_relative "benchmark"
    FixtureBenchmark.call(Integer(paths.fetch(0)))
  when "visit"
    visits = paths.map do |path|
      response = Rack::MockRequest.new(Rails.application).get(
        "#{origin}#{path}", "HTTP_HOST" => "fixture.test", "HTTP_ACCEPT" => "text/html"
      )
      { status: response.status, body: response.body }
    end
    { visits: visits }
  else
    raise ArgumentError, "Unknown fixture mode"
  end
end
puts JSON.generate(output.merge(events: events))
