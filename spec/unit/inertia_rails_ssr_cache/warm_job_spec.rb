# frozen_string_literal: true

require "spec_helper"

RSpec.describe InertiaRailsSsrCache::WarmJob, :aggregate_failures do
  let(:origin) { "https://public.example" }
  let(:version) { "release-a" }
  let(:rails_config) do
    instance_double(Rails::Application::Configuration, reloading_enabled?: false, allow_concurrency: nil)
  end
  let(:observation) do
    InertiaRailsSsrCache::Observation.new(status: 200, html: true, ssr: true,
                                          fetches: [["inertia_ssr/#{'a' * 32}", true]])
  end

  before do
    InertiaRailsSsrCache.configure do |config|
      config.origin = origin
      config.paths = ["/", "/pricing"]
    end
    allow(InertiaRails.configuration).to receive(:version).and_return(version)
    allow(InertiaRailsSsrCache::Probe).to receive(:call).and_return(observation)
    allow(Rails).to receive(:application).and_return(instance_double(Rails::Application, config: rails_config))
  end

  it "refuses a stale queued release before dispatching any request" do
    expect { described_class.perform_now(origin, ["/"], "old-release") }
      .to raise_error(InertiaRailsSsrCache::WarmFailed) { |error|
        expect(error.report.results.map(&:outcome)).to eq([:release_mismatch])
      }
    expect(InertiaRailsSsrCache::Probe).not_to have_received(:call)
  end

  it "checks release identity again for every target" do
    allow(InertiaRails.configuration).to receive(:version).and_return(version, "release-b")

    expect { described_class.perform_now(origin, ["/", "/pricing"], version) }
      .to raise_error(InertiaRailsSsrCache::WarmFailed) { |error|
        expect(error.report.results.map(&:outcome)).to eq(%i[reused release_mismatch])
      }
    expect(InertiaRailsSsrCache::Probe).to have_received(:call).with(origin: origin, path: "/").twice
    expect(InertiaRailsSsrCache::Probe).not_to have_received(:call).with(origin: origin, path: "/pricing")
  end

  it "rejects a queued target removed from the current registration" do
    expect { described_class.perform_now(origin, ["/private"], version) }
      .to raise_error(InertiaRailsSsrCache::ConfigurationError, /no longer registered/)
    expect(InertiaRailsSsrCache::Probe).not_to have_received(:call)
  end

  it "rejects malformed serialized job arguments at execution" do
    expect { described_class.perform_now(origin, ["//other.example"], version) }
      .to raise_error(InertiaRailsSsrCache::ConfigurationError)
    expect(InertiaRailsSsrCache::Probe).not_to have_received(:call)
  end

  it "captures the release and queue in one Active Job enqueue" do
    previous_adapter = described_class.queue_adapter
    described_class.queue_adapter = :test
    job_id = InertiaRailsSsrCache.warm_later
    job = described_class.queue_adapter.enqueued_jobs.last

    expect(job_id).to eq(job.fetch("job_id"))
    expect(job.fetch(:args)).to eq([origin, ["/", "/pricing"], version])
    expect(job.fetch(:queue)).to eq("ssr_warming")
  ensure
    described_class.queue_adapter = previous_adapter
  end

  it "does not turn an enqueue failure into an apparent receipt" do
    configured_job = instance_double(ActiveJob::ConfiguredJob, perform_later: false)
    allow(described_class).to receive(:set).with(queue: "ssr_warming").and_return(configured_job)

    expect { InertiaRailsSsrCache.warm_later }
      .to raise_error(InertiaRailsSsrCache::ConfigurationError, /did not enqueue/)
  end
end
