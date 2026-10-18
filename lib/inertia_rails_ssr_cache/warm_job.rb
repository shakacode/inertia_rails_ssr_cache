# frozen_string_literal: true

# Copyright (c) 2026 ShakaCode LLC.
#
# SPDX-License-Identifier: LicenseRef-InertiaRailsSsrCache
#
# This file is part of Inertia Rails SSR Cache. Use is governed by The
# Inertia Rails SSR Cache License in LICENSE.md.

require "active_job"

module InertiaRailsSsrCache
  # Backend configuration owns fleet concurrency. This job never fans out or retries itself.
  class WarmJob < ActiveJob::Base
    def self.validate_environment!
      config = Rails.application.config
      if config.reloading_enabled?
        raise ConfigurationError, "SSR cache warming requires config.enable_reloading = false in the job process"
      end
      return unless config.allow_concurrency == false

      raise ConfigurationError, "SSR cache warming requires config.allow_concurrency to permit concurrent execution"
    end

    def perform(origin, paths, release)
      self.class.validate_environment!
      registered = InertiaRailsSsrCache.configuration
      targets = registered.verify_targets!(origin, paths)
      InertiaRailsSsrCache.validate_release!(release)
      results = targets.map { |path| warm_target(origin, path, release) }
      report = Report.new(release: release, results: results)
      ActiveSupport::Notifications.instrument("warm.inertia_rails_ssr_cache", report: report)
      raise WarmFailed, report unless report.success?

      report
    end

    private

    def warm_target(origin, path, release)
      result = if InertiaRailsSsrCache.current_release == release
                 first = Probe.call(origin: origin, path: path)
                 second = Probe.call(origin: origin, path: path)
                 TargetResult.compare(path, first, second)
               else
                 TargetResult.new(path: path, outcome: :release_mismatch)
               end
      ActiveSupport::Notifications.instrument("target.inertia_rails_ssr_cache", result: result, release: release)
      result
    end
  end
end
