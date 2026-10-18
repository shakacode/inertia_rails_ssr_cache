# frozen_string_literal: true

require "spec_helper"
require_relative "../../fixtures/runtime"

RSpec.describe InertiaRailsSsrCache::WarmJob do
  around do |example|
    example.run
  ensure
    runtime.close
  end

  let(:runtime) { FixtureRuntime.new }
  let(:renderer) { runtime.start_renderer("release-a") }

  it "warms native SSR and reuses it in a different Rails process", :aggregate_failures do
    warmed = runtime.run("warm", ["/stable"], renderer: renderer)
    visitor = runtime.run("visit", ["/stable", "/stable"], renderer: renderer)

    expect(warmed.fetch("success")).to be true
    expect(warmed.fetch("events").map { |event| event.fetch("hit") }).to eq([false, true])
    expect(warmed.fetch("events").map { |event| event.fetch("key") }.uniq.length).to eq(1)
    expect(visitor.fetch("events").map { |event| event.fetch("hit") }).to eq([true, true])
    expect(visitor.fetch("events").first.fetch("key")).to eq(warmed.fetch("events").first.fetch("key"))
    responses = visitor.fetch("visits")
    expect(responses.map { |response| response.fetch("status") }).to eq([200, 200])
    expect(responses.first.fetch("body")).to eq(responses.last.fetch("body"))
    expect(responses.first.fetch("body")).to include('data-build="release-a"', "Real React SSR", "Cookie: none",
                                                     "Fixture release-a</title>")
    expect(runtime.render_count(renderer)).to eq(1)
  end

  it "preserves the queued job executor while giving each request a fresh context", :aggregate_failures do
    result = runtime.run("execute", ["/stable"], renderer: renderer)

    expect(result.fetch("success")).to be true
    expect(result.fetch("before")).to eq(
      "executor_active" => true, "job_marker" => "job-context", "job_completions" => 0
    )
    expect(result.fetch("after")).to eq(result.fetch("before"))
    expect(result.fetch("after_execute")).to eq(
      "executor_active" => false, "job_marker" => nil, "job_completions" => 1
    )
    expect(result.fetch("requests")).to eq([
                                             { "job_marker" => nil, "request_marker" => nil },
                                             { "job_marker" => nil, "request_marker" => nil }
                                           ])
    expect(runtime.render_count(renderer)).to eq(1)
  end

  it "supplies a valid reserved source address to ordinary Rails controllers", :aggregate_failures do
    result = runtime.run("warm", ["/valid-ip"], renderer: renderer)

    expect(result.fetch("success")).to be true
    expect(result.fetch("events").map { |event| event.fetch("hit") }).to eq([false, true])
    expect(runtime.render_count(renderer)).to eq(1)
  end

  it "propagates request exceptions without completing the job executor early", :aggregate_failures do
    result = runtime.run("execute", ["/exception"], renderer: renderer)

    expect(result.fetch("success")).to be false
    expect(result.fetch("error_class")).to eq("IOError")
    expect(result.fetch("error_message")).to eq("fixture controller unavailable")
    expect(result.fetch("after")).to eq(result.fetch("before"))
    expect(result.fetch("after_execute")).to eq(
      "executor_active" => false, "job_marker" => nil, "job_completions" => 1
    )
    expect(result.fetch("requests")).to eq([{ "job_marker" => nil, "request_marker" => nil }])
    expect(runtime.render_count(renderer)).to eq(0)
  end

  {
    "null payload cached before CSR fallback" => ["/null-payload", "normal"],
    "false payload cached before CSR fallback" => ["/false-payload", "normal"],
    "SSR failure" => ["/broken", "normal"],
    "disabled SSR" => ["/stable", "ssr_disabled"],
    "global caching disabled" => ["/stable", "cache_disabled"],
    "per-render caching disabled" => ["/uncached", "normal"],
    "nonretaining cache store" => ["/stable", "null_store"],
    "unstable page props" => ["/unstable", "normal"],
    "redirect" => ["/redirect", "normal"],
    "authentication requirement" => ["/protected", "normal"],
    "failure after SSR cached" => ["/late-failure", "normal"],
    "missing SSR bundle" => ["/stable", "missing_bundle"]
  }.each do |description, (path, scenario)|
    it "rejects #{description} as verified warming", :aggregate_failures do
      result = runtime.run("warm", [path], renderer: renderer, scenario: scenario)

      expect(result.fetch("success")).to be false
      expect(result.fetch("results").first.fetch("outcome")).not_to eq("reused")
    end
  end

  it "rejects a Node build that does not match the Rails release", :aggregate_failures do
    wrong_renderer = runtime.start_renderer("release-b")
    result = runtime.run("warm", ["/stable"], renderer: wrong_renderer)

    expect(result.fetch("success")).to be false
    expect(runtime.render_count(wrong_renderer)).to eq(0)
    expect(result.fetch("events").none? { |event| event.fetch("hit") }).to be true
  end

  it "rejects warming when the SSR process is unavailable", :aggregate_failures do
    Process.kill("TERM", renderer.pid)
    Process.wait(renderer.pid)
    result = runtime.run("warm", ["/stable"], renderer: renderer)

    expect(result.fetch("success")).to be false
    expect(result.fetch("results").first.fetch("outcome")).to eq("invalid_ssr_value")
  end

  it "isolates new-release entries and restores the old entry on rollback", :aggregate_failures do
    old_result = runtime.run("warm", ["/stable"], renderer: renderer)
    new_renderer = runtime.start_renderer("release-b")
    new_result = runtime.run("warm", ["/stable"], renderer: new_renderer, release: "release-b")
    new_visit = runtime.run("visit", ["/stable"], renderer: new_renderer, release: "release-b")
    rollback = runtime.run("warm", ["/stable"], renderer: renderer)
    old_visit = runtime.run("visit", ["/stable"], renderer: renderer)

    expect([old_result, new_result, rollback].map { |result| result.fetch("success") }).to all(be true)
    expect(new_result.fetch("events").first.fetch("key")).not_to eq(old_result.fetch("events").first.fetch("key"))
    expect(new_visit.fetch("visits").first.fetch("body")).to include('data-build="release-b"')
    expect(rollback.fetch("events").map { |event| event.fetch("hit") }).to eq([true, true])
    expect(old_visit.fetch("visits").first.fetch("body")).to include('data-build="release-a"')
    expect([runtime.render_count(renderer), runtime.render_count(new_renderer)]).to eq([1, 1])
  end

  it "does not transfer response cookies between any warm requests", :aggregate_failures do
    result = runtime.run("warm", ["/set-cookie", "/read-cookie"], renderer: renderer)
    visitor = runtime.run("visit", ["/read-cookie"], renderer: renderer)

    expect(result.fetch("success")).to be true
    expect(visitor.fetch("events").first.fetch("hit")).to be true
    expect(visitor.fetch("visits").first.fetch("body")).to include("Cookie: none")
    expect(visitor.fetch("visits").first.fetch("body")).not_to include("do-not-transfer")
    expect(runtime.render_count(renderer)).to eq(2)
  end
end
