# frozen_string_literal: true

require "json"
require "rails"
require "action_controller/railtie"
require "active_job/railtie"
require "inertia_rails_ssr_cache"

class EnvironmentFixtureApplication < Rails::Application
  config.eager_load = false
  config.enable_reloading = ARGV.fetch(0) == "reloading"
  config.allow_concurrency = false if ARGV.fetch(0) == "serialized"
  config.secret_key_base = "fixture-only-not-a-production-secret"
  config.hosts = ["fixture.test"]
  config.logger = Logger.new(File::NULL)
  config.active_job.queue_adapter = :test
  config.action_dispatch.show_exceptions = :none
end

EnvironmentFixtureApplication.initialize!

class EnvironmentFixturePagesController < ActionController::Base
  class_attribute :visits, default: 0

  def show
    self.class.visits += 1
    render plain: "Environment control", content_type: "text/html"
  end
end

EnvironmentFixtureApplication.routes.draw { get "/", to: "environment_fixture_pages#show" }
InertiaRails.configure { |config| config.version = "release-a" }
InertiaRailsSsrCache.configure do |config|
  config.origin = "http://fixture.test"
  config.paths = ["/"]
end

def capture_result
  yield
  { accepted: true }
rescue StandardError => e
  { accepted: false, error: e.class.name, message: e.message }
end

threads_started = 0
result = TracePoint.new(:thread_begin) { threads_started += 1 }.enable(target_thread: nil) do
  enqueue = capture_result { InertiaRailsSsrCache.warm_later }
  job = InertiaRailsSsrCache::WarmJob.new("http://fixture.test", ["/"], "release-a")
  execution = capture_result { ActiveJob::Base.execute(job.serialize) }
  { enqueue: enqueue, execution: execution }
end
result[:threads_started] = threads_started
result[:requests] = EnvironmentFixturePagesController.visits
result[:enqueued_jobs] = InertiaRailsSsrCache::WarmJob.queue_adapter.enqueued_jobs.size
$stdout.puts JSON.generate(result)
