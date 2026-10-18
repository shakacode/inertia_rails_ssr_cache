# frozen_string_literal: true

require "json"

module WarmerDemo
  # One flock-protected line lets independent web/worker processes share evidence.
  def self.record(type, **fields)
    File.open(RUNTIME.join("events.jsonl"), "a") do |file|
      file.flock(File::LOCK_EX)
      file.puts(JSON.generate({ type: type, pid: Process.pid, **fields }))
    end
  end
end

# Read observations carry the same store-normalized key on both misses and hits.
ActiveSupport::Notifications.subscribe("cache_read.active_support") do |*arguments|
  payload = ActiveSupport::Notifications::Event.new(*arguments).payload
  key = payload.fetch(:key).to_s
  next unless payload[:super_operation] == :fetch && key.include?("inertia_ssr")

  WarmerDemo.record("cache", key: key, hit: payload.fetch(:hit))
end

ActiveSupport::Notifications.subscribe("target.inertia_rails_ssr_cache") do |*arguments|
  payload = ActiveSupport::Notifications::Event.new(*arguments).payload
  result = payload.fetch(:result)
  WarmerDemo.record("target", path: result.path, outcome: result.outcome, release: payload.fetch(:release))
end
