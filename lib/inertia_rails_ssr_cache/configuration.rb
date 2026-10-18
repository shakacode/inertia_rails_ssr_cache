# frozen_string_literal: true

# Copyright (c) 2026 ShakaCode LLC.
#
# SPDX-License-Identifier: LicenseRef-InertiaRailsSsrCache
#
# This file is part of Inertia Rails SSR Cache. Use is governed by The
# Inertia Rails SSR Cache License in LICENSE.md.

require "uri"

module InertiaRailsSsrCache
  class ConfigurationError < StandardError; end

  # Boot-time registration is the only authority for eligible anonymous requests.
  class Configuration
    MAX_TARGETS = 50
    RELEASE = /\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}\z/
    INVALID_CHARACTERS = /[\\\x00-\x20\x7f]/

    attr_accessor :origin, :paths, :queue_name

    def initialize
      @origin = nil
      @paths = []
      @queue_name = :ssr_warming
    end

    def validate!
      @origin = self.class.validate_origin(origin).dup.freeze
      @paths = self.class.validate_paths(paths)
      @queue_name = self.class.validate_queue_name(queue_name)
      freeze
    end

    def verify_targets!(requested_origin, requested_paths)
      checked_origin = self.class.validate_origin(requested_origin)
      checked_paths = self.class.validate_paths(requested_paths)
      unless checked_origin == origin && checked_paths.all? { |path| paths.include?(path) }
        raise ConfigurationError, "queued targets are no longer registered"
      end

      checked_paths
    end

    def self.validate_release(value)
      unless value.is_a?(String) && RELEASE.match?(value)
        raise ConfigurationError,
              "release must be 1-128 ASCII letters, digits, dots, underscores or hyphens, starting alphanumeric"
      end

      value
    end

    def self.validate_queue_name(value)
      unless (value.is_a?(String) || value.is_a?(Symbol)) && !value.to_s.strip.empty?
        raise ConfigurationError, "queue_name must be a nonempty string or symbol"
      end

      value.to_s.dup.freeze
    end

    def self.valid_origin?(parsed)
      parsed.is_a?(URI::HTTP) && !parsed.host.to_s.empty? && parsed.path == "" &&
        [parsed.userinfo, parsed.query, parsed.fragment].all?(&:nil?)
    end

    def self.validate_origin(value)
      unless value.is_a?(String) && !INVALID_CHARACTERS.match?(value)
        raise ConfigurationError, "origin must be an absolute HTTP(S) origin"
      end

      parsed = URI.parse(value)
      unless valid_origin?(parsed)
        raise ConfigurationError, "origin must contain only HTTP(S) scheme and host, with an optional port"
      end

      value
    rescue URI::InvalidURIError
      raise ConfigurationError, "origin is not a valid URI"
    end

    def self.validate_paths(value)
      unless value.is_a?(Array) && !value.empty? && value.all?(String)
        raise ConfigurationError, "paths must be a nonempty array of rooted paths"
      end

      paths = value.uniq
      if paths.size > MAX_TARGETS
        raise ConfigurationError,
              "at most #{MAX_TARGETS} distinct paths may be warmed per job"
      end

      paths.each { |path| validate_path(path) }
      paths.map { |path| path.dup.freeze }.freeze
    end

    def self.validate_path(path)
      unless path.start_with?("/") && !path.start_with?("//") && !INVALID_CHARACTERS.match?(path)
        raise ConfigurationError, "each path must be rooted and must not contain an authority or control characters"
      end

      parsed = URI.parse(path)
      unless [parsed.fragment, parsed.host, parsed.scheme].all?(&:nil?)
        raise ConfigurationError, "paths must not contain fragments, hosts or schemes"
      end
    rescue URI::InvalidURIError
      raise ConfigurationError, "path is not a valid URI"
    end
  end
end
