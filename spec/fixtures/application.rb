# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
require "active_job/railtie"
require "inertia_rails"
require "inertia_rails_ssr_cache"
require "rack/mock"
require "securerandom"
require "ipaddr"

class FixtureApplication < Rails::Application
  config.eager_load = false
  config.enable_reloading = false
  config.secret_key_base = "fixture-only-not-a-production-secret"
  config.hosts = ["fixture.test"]
  config.logger = Logger.new(File::NULL)
  config.active_job.queue_adapter = :test
  config.active_support.deprecation = :stderr
  config.action_dispatch.show_exceptions = :none
  config.session_store :cookie_store, key: "fixture_session"
end

FixtureApplication.initialize!

class FixturePagesController < ActionController::Base
  prepend_view_path File.expand_path("views", __dir__)
  layout "fixture"
  after_action :fail_after_render, only: :late_failure

  def stable
    render_page
  end

  def valid_ip
    unless IPAddr.new(request.remote_ip) == IPAddr.new("192.0.2.1")
      raise ArgumentError, "expected the synthetic source address"
    end

    render_page
  end

  def unstable
    render_page(nonce: SecureRandom.hex(8))
  end

  def broken
    render_page(component: "Broken")
  end

  def null_payload
    render_page(component: "Null")
  end

  def false_payload
    render_page(component: "False")
  end

  def uncached
    render_page(cache: false)
  end

  def redirect
    redirect_to "/stable"
  end

  def protected_page
    head :unauthorized
  end

  def late_failure
    render_page
  end

  def exception
    raise IOError, "fixture controller unavailable"
  end

  def set_cookie
    cookies[:warm_cookie] = "do-not-transfer"
    render_page
  end

  def read_cookie
    render_page
  end

  private

  def fail_after_render
    response.status = :internal_server_error
  end

  def render_page(nonce: "stable", component: "Fixture", cache: nil)
    render inertia: component, props: {
      message: "Real React SSR",
      cookie: cookies[:warm_cookie] || "none",
      nonce: nonce
    }, layout: "fixture", ssr_cache: cache
  end
end

FixtureApplication.routes.draw do
  get "/stable", to: "fixture_pages#stable"
  get "/valid-ip", to: "fixture_pages#valid_ip"
  get "/unstable", to: "fixture_pages#unstable"
  get "/broken", to: "fixture_pages#broken"
  get "/null-payload", to: "fixture_pages#null_payload"
  get "/false-payload", to: "fixture_pages#false_payload"
  get "/uncached", to: "fixture_pages#uncached"
  get "/redirect", to: "fixture_pages#redirect"
  get "/protected", to: "fixture_pages#protected_page"
  get "/late-failure", to: "fixture_pages#late_failure"
  get "/exception", to: "fixture_pages#exception"
  get "/set-cookie", to: "fixture_pages#set_cookie"
  get "/read-cookie", to: "fixture_pages#read_cookie"
end

scenario = ENV.fetch("FIXTURE_SCENARIO", "normal")
InertiaRails.configure do |config|
  config.version = ENV.fetch("FIXTURE_RELEASE")
  config.ssr_enabled = scenario != "ssr_disabled"
  config.ssr_cache = scenario != "cache_disabled"
  config.ssr_url = ENV.fetch("FIXTURE_SSR_URL")
  config.ssr_bundle = "/definitely-missing-inertia-fixture.js" if scenario == "missing_bundle"
  config.always_include_errors_hash = true
  config.cache_store = if scenario == "null_store"
                         ActiveSupport::Cache::NullStore.new
                       else
                         ActiveSupport::Cache::FileStore.new(ENV.fetch("FIXTURE_CACHE"))
                       end
end
ActiveJob::Base.logger = Logger.new(File::NULL)
