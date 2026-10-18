# frozen_string_literal: true

require "spec_helper"

RSpec.describe InertiaRailsSsrCache::Probe, :aggregate_failures do
  let(:origin) { "https://public.example" }
  let(:key) { "inertia_ssr/#{'a' * 32}" }

  before do
    allow(InertiaRails).to receive(:cache_store).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  def emit_fetch(key, hit: true, operation: :fetch)
    ActiveSupport::Notifications.instrument("cache_read.active_support", key: key, hit: hit, super_operation: operation)
  end

  it "sends only a fresh anonymous HTML GET context" do
    requests = []
    app = lambda do |env|
      requests << env.slice("REQUEST_METHOD", "HTTP_HOST", "HTTP_ACCEPT", "HTTP_COOKIE", "HTTP_X_INERTIA",
                            "REMOTE_ADDR")
      emit_fetch(key)
      [200, { "content-type" => "text/html", "set-cookie" => "private=secret" }, ["<html></html>"]]
    end
    allow(Rails).to receive(:application).and_return(app)

    2.times { described_class.call(origin: origin, path: "/") }

    expect(requests).to eq(Array.new(2, "REQUEST_METHOD" => "GET", "HTTP_HOST" => "public.example",
                                        "HTTP_ACCEPT" => "text/html", "REMOTE_ADDR" => "192.0.2.1"))
  end

  it "ignores unrelated cache keys and non-fetch reads" do
    app = lambda do |_env|
      emit_fetch("other/#{key}")
      emit_fetch(key, operation: :read)
      emit_fetch(key)
      [200, { "content-type" => "text/html" }, [""]]
    end
    allow(Rails).to receive(:application).and_return(app)

    expect(described_class.call(origin: origin, path: "/").fetches).to eq([[key, true]])
  end

  it "attributes overlapping threads only to their own requests" do
    entered = Queue.new
    finish = Queue.new
    app = lambda do |env|
      emit_fetch("inertia_ssr/#{env.fetch('PATH_INFO').delete_prefix('/') * 32}")
      entered << true
      finish.pop
      [200, { "content-type" => "text/html" }, [""]]
    end
    allow(Rails).to receive(:application).and_return(app)
    workers = %w[a b].map do |letter|
      Thread.new { described_class.call(origin: origin, path: "/#{letter}") }
    end
    2.times { entered.pop }
    2.times { finish << true }

    expect(workers.map { |worker| worker.value.fetches }).to eq([
                                                                  [["inertia_ssr/#{'a' * 32}", true]],
                                                                  [["inertia_ssr/#{'b' * 32}", true]]
                                                                ])
  end

  it "attributes overlapping fibers on one thread only to their own requests" do
    app = lambda do |env|
      emit_fetch("inertia_ssr/#{env.fetch('PATH_INFO').delete_prefix('/') * 32}")
      Fiber.yield
      [200, { "content-type" => "text/html" }, [""]]
    end
    allow(Rails).to receive(:application).and_return(app)
    workers = %w[a b].map do |letter|
      Fiber.new { described_class.new(origin, "/#{letter}").call }
    end
    workers.each(&:resume)

    expect(workers.map { |worker| worker.resume.fetches }).to eq([
                                                                   [["inertia_ssr/#{'a' * 32}", true]],
                                                                   [["inertia_ssr/#{'b' * 32}", true]]
                                                                 ])
  end

  it "removes its subscription when the Rack application raises" do
    app = ->(_env) { raise IOError, "unavailable" }
    allow(Rails).to receive(:application).and_return(app)
    notifier = ActiveSupport::Notifications.notifier
    previous_count = notifier.listeners_for("cache_read.active_support").size

    expect { described_class.call(origin: origin, path: "/") }.to raise_error(IOError, "unavailable")
    expect(notifier.listeners_for("cache_read.active_support").size).to eq(previous_count)
  end
end
