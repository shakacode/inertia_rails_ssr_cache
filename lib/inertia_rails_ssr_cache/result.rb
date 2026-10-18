# frozen_string_literal: true

# Copyright (c) 2026 ShakaCode LLC.
#
# SPDX-License-Identifier: LicenseRef-InertiaRailsSsrCache
#
# This file is part of Inertia Rails SSR Cache. Use is governed by The
# Inertia Rails SSR Cache License in LICENSE.md.

module InertiaRailsSsrCache
  # Evidence interpretation is pure; framework events are reduced before this boundary.
  class Observation
    attr_reader :status, :html, :fetches, :ssr

    def initialize(status:, html:, fetches:, ssr:)
      @ssr = ssr
      @status = status
      @html = html
      @fetches = fetches.freeze
      freeze
    end

    def self.ssr_value?(value)
      return false unless value.is_a?(Hash)

      head = value["head"]
      value["body"].is_a?(String) && head.is_a?(Array) && head.all?(String)
    end

    def failure
      return :http_failure unless status == 200 && html
      return :missing_cache_evidence if fetches.empty?
      return :ambiguous_cache_evidence unless fetches.size == 1
      return :invalid_ssr_value unless ssr

      nil
    end
  end

  class TargetResult
    attr_reader :path, :outcome, :initial_cache_hit

    def initialize(path:, outcome:, initial_cache_hit: nil)
      @path = path.dup.freeze
      @outcome = outcome
      @initial_cache_hit = initial_cache_hit
      freeze
    end

    def self.compare(path, first, second)
      failure = first.failure || second.failure
      return new(path: path, outcome: failure) if failure

      initial_key, initial_hit = first.fetches.fetch(0)
      repeat_key, repeat_hit = second.fetches.fetch(0)
      outcome = reuse_outcome(initial_key, repeat_key, repeat_hit)
      new(path: path, outcome: outcome, initial_cache_hit: initial_hit)
    end

    def self.reuse_outcome(initial_key, repeat_key, repeat_hit)
      return :cache_key_changed if initial_key != repeat_key
      return :cache_not_reused unless repeat_hit

      :reused
    end
    private_class_method :reuse_outcome
  end

  class Report
    attr_reader :release, :results

    def initialize(release:, results:)
      @release = release.dup.freeze
      @results = results.freeze
      freeze
    end

    def success?
      !results.empty? && results.all? { |result| result.outcome == :reused }
    end
  end

  class WarmFailed < StandardError
    attr_reader :report

    def initialize(report)
      @report = report
      outcomes = report.results.reject { |result| result.outcome == :reused }.map(&:outcome).uniq
      super("SSR warming could not verify cache reuse: #{outcomes.join(', ')}")
    end
  end
end
