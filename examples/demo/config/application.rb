# frozen_string_literal: true

require_relative "boot"
require "rails"
require "action_controller/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "inertia_rails"
require "inertia_rails_ssr_cache"
require "solid_queue"

module WarmerDemo
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.enable_reloading = false
    config.secret_key_base = "local-warmer-demo-only-not-for-deployment-#{'0' * 64}"
    config.hosts = ["127.0.0.1", "localhost"]
    config.logger = ActiveSupport::Logger.new(RUNTIME.join("rails.log"))
    config.active_support.deprecation = :stderr
    config.action_dispatch.show_exceptions = :none
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = { database: { writing: :primary } }
    config.solid_queue.use_skip_locked = false
    config.solid_queue.supervisor_pidfile = RUNTIME.join("jobs.pid")
    config.cache_store = :file_store, RUNTIME.join("cache").to_s
    config.public_file_server.enabled = true
    config.paths["public"] = RUNTIME.join("public").to_s
    config.paths["tmp"] = RUNTIME.to_s
  end
end
