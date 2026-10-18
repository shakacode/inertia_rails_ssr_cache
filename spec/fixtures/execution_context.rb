# frozen_string_literal: true

require "active_support/current_attributes"

class FixtureCurrent < ActiveSupport::CurrentAttributes
  attribute :job_marker, :request_marker
end

class FixtureExecutionContext
  def self.call(origin, paths, release)
    evidence = { job_completions: 0, requests: [] }
    observe_executor(evidence)
    observe_requests(evidence)
    observe_job(evidence)
    result = execute(origin, paths, release)
    evidence.merge(result, after_execute: snapshot(evidence))
  end

  def self.execute(origin, paths, release)
    report = ActiveJob::Base.execute(InertiaRailsSsrCache::WarmJob.new(origin, paths, release).serialize)
    { success: report.success? }
  rescue StandardError => e
    { success: false, error_class: e.class.name, error_message: e.message }
  end

  def self.observe_executor(evidence)
    job_thread = Thread.current
    Rails.application.executor.to_complete do
      evidence[:job_completions] += 1 if Thread.current.equal?(job_thread)
    end
  end

  def self.observe_requests(evidence)
    FixturePagesController.before_action do
      evidence[:requests] << { job_marker: FixtureCurrent.job_marker, request_marker: FixtureCurrent.request_marker }
      FixtureCurrent.request_marker = "request-context"
    end
  end

  def self.observe_job(evidence)
    InertiaRailsSsrCache::WarmJob.around_perform do |_job, perform|
      FixtureCurrent.job_marker = "job-context"
      evidence[:before] = FixtureExecutionContext.snapshot(evidence)
      perform.call
    ensure
      evidence[:after] = FixtureExecutionContext.snapshot(evidence)
    end
  end

  def self.snapshot(evidence)
    {
      executor_active: Rails.application.executor.active?,
      job_marker: FixtureCurrent.job_marker,
      job_completions: evidence.fetch(:job_completions)
    }
  end
end
