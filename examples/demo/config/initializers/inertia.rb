# frozen_string_literal: true

InertiaRails.configure do |config|
  config.version = WarmerDemo::RELEASE
  config.ssr_enabled = true
  config.ssr_url = "http://127.0.0.1:#{WarmerDemo::SSR_PORT}"
  config.ssr_cache = { expires_in: 1.hour }
  config.cache_store = Rails.cache
end

InertiaRailsSsrCache.configure do |config|
  config.origin = "http://127.0.0.1:#{WarmerDemo::WEB_PORT}"
  config.paths = ["/"]
  config.queue_name = :ssr_warming
end
