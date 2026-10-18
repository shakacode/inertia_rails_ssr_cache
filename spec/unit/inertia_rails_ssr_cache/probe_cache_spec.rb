# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe InertiaRailsSsrCache::Probe, :aggregate_failures do
  def key = "inertia_ssr/#{'b' * 32}"
  let(:ssr_value) { { "head" => ["<title>SSR</title>"], "body" => "<div>SSR</div>" } }
  let(:cache_options) { { namespace: "app:release", version: "entry-v3" } }
  let(:app) do
    lambda do |_env|
      store.fetch(key, **cache_options) { ssr_value }
      [200, { "content-type" => "text/html" }, ["<html></html>"]]
    end
  end

  def origin = "https://public.example"

  def probe_with_native_events
    events = []
    subscriber = ->(*arguments) { events << ActiveSupport::Notifications::Event.new(*arguments).payload }
    observation = ActiveSupport::Notifications.subscribed(subscriber, "cache_read.active_support") do
      described_class.call(origin: origin, path: "/")
    end
    [observation, events.select { |event| event[:super_operation] == :fetch }]
  end

  before do
    allow(Rails).to receive(:application).and_return(app)
    allow(InertiaRails).to receive(:cache_store).and_return(store)
  end

  shared_examples "retained native SSR evidence" do
    it "reads the exact namespace and entry version through the public store API" do
      first = described_class.call(origin: origin, path: "/")
      second = described_class.call(origin: origin, path: "/")

      expect(first.ssr).to be(true)
      expect(second.ssr).to be(true)
      expect(second.fetches.first.last).to be(true)
      expect(store.read(key, namespace: cache_options.fetch(:namespace), version: "wrong")).to be_nil
    end

    [nil, false, {}, { "head" => [], "body" => 42 }].each do |invalid_value|
      context "when the SSR server returned #{invalid_value.inspect}" do
        let(:ssr_value) { invalid_value }

        it "rejects a native hit containing an invalid SSR result" do
          described_class.call(origin: origin, path: "/")
          repeated = described_class.call(origin: origin, path: "/")

          expect(repeated.fetches.first.last).to be(true)
          expect(repeated.failure).to eq(:invalid_ssr_value)
        end
      end
    end

    context "when nil results are skipped by native fetch options" do
      let(:ssr_value) { nil }
      let(:cache_options) { super().merge(skip_nil: true) }

      it "reports missing retained SSR instead of treating generation as success" do
        described_class.call(origin: origin, path: "/")
        repeated = described_class.call(origin: origin, path: "/")

        expect(repeated.fetches.first.last).to be(false)
        expect(repeated.failure).to eq(:invalid_ssr_value)
      end
    end

    context "when the cache does not retain the generated value" do
      let(:cache_options) { super().merge(expires_in: 0) }

      it "does not claim retained SSR evidence" do
        expect(described_class.call(origin: origin, path: "/").ssr).to be(false)
      end
    end
  end

  context "with MemoryStore" do
    let(:store) { ActiveSupport::Cache::MemoryStore.new }

    it_behaves_like "retained native SSR evidence"

    context "when an unrelated cache key contains invalid UTF-8 bytes" do
      let(:cache_options) { {} }

      def key = "\xFF".dup.force_encoding(Encoding::UTF_8)

      it "leaves the normal cache request intact and ignores the invalid key" do
        store.write(key, ssr_value)
        expect(store.read(key)).to eq(ssr_value)

        observation = described_class.call(origin: origin, path: "/")

        expect(observation.status).to eq(200)
        expect(observation.fetches).to be_empty
        expect(observation.failure).to eq(:missing_cache_evidence)
      end
    end
  end

  context "with FileStore" do
    let(:directory) { Dir.mktmpdir("ssr-cache-probe") }
    let(:store) { ActiveSupport::Cache::FileStore.new(directory) }

    after do
      FileUtils.remove_entry(directory)
    end

    it_behaves_like "retained native SSR evidence"

    context "when an unrelated Unicode cache key is split across filenames" do
      let(:cache_options) { {} }

      def key = "é" * 100

      it "ignores a split multibyte character without interrupting the cache hit" do
        store.write(key, ssr_value)
        expect(store.read(key)).to eq(ssr_value)

        observation, events = probe_with_native_events
        native_fetch = events.fetch(0)
        decoded_basename = URI.decode_www_form_component(File.basename(native_fetch.fetch(:key)))

        expect(decoded_basename.valid_encoding?).to be(false)
        expect(native_fetch.fetch(:hit)).to be(true)
        expect(observation.status).to eq(200)
        expect(observation.fetches).to be_empty
        expect(observation.failure).to eq(:missing_cache_evidence)
      end
    end

    context "when a long namespace splits the encoded filename" do
      let(:cache_options) { super().merge(namespace: "long-namespace-" * 24) }

      it "rejects unverifiable identity despite a valid native cache hit" do
        store.write(key, ssr_value, **cache_options)
        observation, events = probe_with_native_events
        native_fetch = events.fetch(0)

        expect(events.size).to eq(1)
        expect(native_fetch.fetch(:hit)).to be(true)
        expect(File.dirname(native_fetch.fetch(:key))).to include("long-namespace-")
        expect(store.read(key, **cache_options)).to eq(ssr_value)
        expect(observation.fetches).to be_empty
        expect(observation.failure).to eq(:missing_cache_evidence)
      end
    end

    context "with a FileStore subclass" do
      let(:store) { stub_const("CustomFileStore", Class.new(ActiveSupport::Cache::FileStore)).new(directory) }

      it "rejects the unverified store encoding despite a valid native cache hit" do
        store.write(key, ssr_value, **cache_options)
        observation, events = probe_with_native_events
        native_fetch = events.fetch(0)

        expect(events.size).to eq(1)
        expect(native_fetch.fetch(:hit)).to be(true)
        expect(native_fetch.fetch(:store)).to eq("CustomFileStore")
        expect(store.read(key, **cache_options)).to eq(ssr_value)
        expect(observation.fetches).to be_empty
        expect(observation.failure).to eq(:missing_cache_evidence)
      end
    end
  end
end
