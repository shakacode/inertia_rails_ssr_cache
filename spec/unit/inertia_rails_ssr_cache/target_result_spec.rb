# frozen_string_literal: true

require_relative "../../../lib/inertia_rails_ssr_cache/result"

RSpec.describe InertiaRailsSsrCache::TargetResult, :aggregate_failures do
  let(:key) { "inertia_ssr/#{'a' * 32}" }
  let(:first) { observation([[key, false]]) }
  let(:second) { observation([[key, true]]) }

  def observation(fetches, status: 200, html: true, ssr: true)
    InertiaRailsSsrCache::Observation.new(status: status, html: html, fetches: fetches, ssr: ssr)
  end

  it "requires actual same-key native cache reuse" do
    result = described_class.compare("/", first, second)

    expect(result.outcome).to eq(:reused)
    expect(result.initial_cache_hit).to be(false)
  end

  it "rejects a failed layout even after a native cache hit" do
    result = described_class.compare("/", first, observation([[key, true]], status: 500))

    expect(result.outcome).to eq(:http_failure)
  end

  it "rejects JSON visits despite native cache evidence" do
    result = described_class.compare("/", first, observation([[key, true]], html: false))

    expect(result.outcome).to eq(:http_failure)
  end

  it "does not mistake successful CSR fallback for a warm" do
    result = described_class.compare("/", observation([]), observation([]))

    expect(result.outcome).to eq(:missing_cache_evidence)
  end

  it "rejects evidence from multiple renders" do
    result = described_class.compare("/", observation([[key, false], [key, true]]), second)

    expect(result.outcome).to eq(:ambiguous_cache_evidence)
  end

  it "rejects a second hit for a different page identity" do
    result = described_class.compare("/", first, observation([["inertia_ssr/#{'b' * 32}", true]]))

    expect(result.outcome).to eq(:cache_key_changed)
  end

  it "rejects stores that never retain a rendered value" do
    result = described_class.compare("/", first, first)

    expect(result.outcome).to eq(:cache_not_reused)
  end

  it "rejects a cached nil or false SSR value even when the entry is a hit" do
    result = described_class.compare("/", first, observation([[key, true]], ssr: false))

    expect(result.outcome).to eq(:invalid_ssr_value)
  end

  it "reports a failed partial run without including private response data" do
    failure = described_class.new(path: "/", outcome: :cache_not_reused)
    report = InertiaRailsSsrCache::Report.new(release: "release-a", results: [failure])
    error = InertiaRailsSsrCache::WarmFailed.new(report)

    expect(report.success?).to be(false)
    expect(error.report).to equal(report)
    expect(error.message).to include("cache_not_reused")
  end
end
