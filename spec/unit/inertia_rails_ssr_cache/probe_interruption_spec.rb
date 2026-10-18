# frozen_string_literal: true

require "spec_helper"
require "action_view"
require "action_dispatch/middleware/executor"

RSpec.describe InertiaRailsSsrCache::Probe, :aggregate_failures do
  let(:state) do
    { entered: Queue.new, release_request: Queue.new, cleanup: Queue.new,
      release_cleanup: Queue.new, events: [] }
  end

  before do
    request_state = state
    executor = Class.new(ActiveSupport::Executor)
    executor.to_complete do
      request_state[:cleanup] << true
      request_state[:release_cleanup].pop
      request_state[:events] << :cleanup_finished
    end
    executor.to_complete { request_state[:events] << :last_cleanup }
    allow(Rails).to receive(:application).and_return(ActionDispatch::Executor.new(request_app, executor))
  end

  after do
    state[:release_request] << true
    state[:release_cleanup] << true
    [state[:parent], state[:child]].compact.each { |thread| clean_up_thread(thread) }
  end

  def request_app
    lambda do |_env|
      state[:entered] << Thread.current
      state[:release_request].pop
      raise state[:request_error] if state[:request_error]

      [200, { "content-type" => "text/html" }, ["ok"]]
    ensure
      state[:events] << :request_ensured
    end
  end

  def start_parent
    parent = Thread.new do
      described_class.call(origin: "https://public.example", path: "/")
    rescue StandardError => e
      state[:parent_error] = e
    ensure
      state[:events] << :parent_finished
    end
    state[:parent] = parent
    state[:child] = await(state[:entered])
    parent
  end

  def await(queue)
    queue.pop(timeout: 2) || raise("Timed out waiting for request coordination")
  end

  def complete_request
    state[:release_request] << true
    await(state[:cleanup])
    complete_cleanup
  end

  def complete_cleanup
    state[:release_cleanup] << true
    expect(state[:parent].join(2)).to eq(state[:parent])
    expect_cleanup_finished
  end

  def expect_cleanup_finished
    expect(state[:child]).not_to be_alive
    expect(state[:events]).to eq(%i[request_ensured cleanup_finished last_cleanup parent_finished])
  end

  def clean_up_thread(thread)
    return unless thread.alive?
    return if thread.join(2)

    thread.kill.join(2)
  rescue StandardError
    raise if thread.alive?
  end

  it "drains the owned request before propagating a parent exception" do
    interruption = RuntimeError.new("job interrupted")
    parent = start_parent
    parent.raise(interruption)

    expect(parent.join(0.02)).to be_nil
    complete_request

    expect(state[:parent_error]).to equal(interruption)
  end

  it "finishes every executor callback before allowing an interrupted parent to terminate" do
    parent = start_parent
    state[:release_request] << true
    await(state[:cleanup])
    parent.kill

    expect(parent.join(0.02)).to be_nil
    complete_cleanup

    expect(state[:parent_error]).to be_nil
  end

  it "preserves the parent exception when its request also fails during cleanup" do
    state[:request_error] = IOError.new("request failed")
    interruption = RuntimeError.new("job interrupted")
    parent = start_parent
    parent.raise(interruption)

    expect(parent.join(0.02)).to be_nil
    complete_request

    expect(state[:parent_error]).to equal(interruption)
  end

  it "propagates the original request exception during a normal wait" do
    state[:request_error] = IOError.new("request failed")
    start_parent
    complete_request

    expect(state[:parent_error]).to equal(state[:request_error])
  end

  it "does not leave the request thread with its parent's interrupt mask" do
    request_error = IOError.new("request interrupted")
    start_parent
    state[:child].raise(request_error)
    await(state[:cleanup])
    complete_cleanup

    expect(state[:parent_error]).to equal(request_error)
  end
end
