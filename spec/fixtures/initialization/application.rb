# frozen_string_literal: true

require "json"
require "rails"
require "action_controller/railtie"
require "active_job/railtie"

with_gem = ARGV.fetch(0) == "with_gem"
require "inertia_rails_ssr_cache" if with_gem
base_loaded = ActiveJob.autoload?(:Base).nil?

class InitializationApplication < Rails::Application
  config.eager_load = false
  config.secret_key_base = "fixture-only-not-a-production-secret"
  config.logger = Logger.new(File::NULL)
  config.active_job.queue_adapter = :async
  config.paths["config/initializers"] = [File.expand_path("initializers", __dir__)]
end

InitializationApplication.initialize!

result = {
  rails: Rails.version,
  base_loaded_before_initialization: base_loaded,
  configured_adapter: Rails.application.config.active_job.queue_adapter,
  base_adapter: ActiveJob::Base.queue_adapter_name,
  base_queue_prefix: ActiveJob::Base.queue_name_prefix
}
if with_gem
  result[:warm_job_adapter] = InertiaRailsSsrCache::WarmJob.queue_adapter_name
  result[:warm_job_queue_prefix] = InertiaRailsSsrCache::WarmJob.queue_name_prefix
end
$stdout.puts JSON.generate(result)
