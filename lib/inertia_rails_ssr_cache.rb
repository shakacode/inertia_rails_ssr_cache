# frozen_string_literal: true

# Copyright (c) 2026 ShakaCode LLC.
#
# SPDX-License-Identifier: LicenseRef-InertiaRailsSsrCache
#
# This file is part of Inertia Rails SSR Cache. Use is governed by The
# Inertia Rails SSR Cache License in LICENSE.md.

require "rails"
require "inertia_rails"
require_relative "inertia_rails_ssr_cache/version"
require_relative "inertia_rails_ssr_cache/configuration"
require_relative "inertia_rails_ssr_cache/result"
require_relative "inertia_rails_ssr_cache/probe"
require_relative "inertia_rails_ssr_cache/railtie"

module InertiaRailsSsrCache
  autoload :WarmJob, "#{__dir__}/inertia_rails_ssr_cache/warm_job"

  class << self
    def configure
      configuration = Configuration.new
      yield configuration
      @configuration = configuration.validate!
    end

    def configuration
      @configuration || raise(ConfigurationError, "register public warming targets with configure first")
    end

    def current_release
      validate_release!(InertiaRails.configuration.version)
    end

    def validate_release!(release)
      Configuration.validate_release(release)
    end

    def warm_later
      registered = configuration
      release = current_release.dup.freeze
      WarmJob.validate_environment!
      job = WarmJob.set(queue: registered.queue_name).perform_later(registered.origin, registered.paths, release)
      raise ConfigurationError, "Active Job did not enqueue the warming job" unless job

      job.job_id
    end
  end
end
