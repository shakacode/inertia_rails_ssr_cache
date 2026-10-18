# frozen_string_literal: true

# Copyright (c) 2026 ShakaCode LLC.
#
# SPDX-License-Identifier: LicenseRef-InertiaRailsSsrCache
#
# This file is part of Inertia Rails SSR Cache. Use is governed by The
# Inertia Rails SSR Cache License in LICENSE.md.

require "rack/mock"
require "active_support/dependencies"
require "active_support/notifications"

module InertiaRailsSsrCache
  # The native-key format belongs only here; compatibility is pinned to Inertia Rails 3.22.
  class Probe
    Fetch = Data.define(:key, :native_key, :hit, :namespace, :version)
    NATIVE_KEY = %r{\Ainertia_ssr/[0-9a-f]{32}\z}

    def self.call(origin:, path:)
      Thread.handle_interrupt(Object => :never) { wait_for_request(start_request(origin, path)) }
    end

    def self.start_request(origin, path)
      Thread.new do
        Thread.current.report_on_exception = false
        Thread.handle_interrupt(Object => :immediate) { new(origin, path).call }
      end
    end

    def self.wait_for_request(request_thread)
      # Rails request middleware resets its executor; isolate it from the job's executor.
      Thread.handle_interrupt(Object => :immediate) do
        ActiveSupport::Dependencies.interlock.permit_concurrent_loads { request_thread.value }
      end
    ensure
      drain_request(request_thread)
    end

    def self.drain_request(request_thread)
      # Never interrupt Rails completion callbacks or replace an interrupted parent's error.
      # The normal wait above already propagates request exceptions.
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads { request_thread.join }
    rescue Exception # rubocop:disable Lint/RescueException
      raise if request_thread.alive?
    end
    private_class_method :start_request, :wait_for_request, :drain_request

    def initialize(origin, path)
      @origin = origin
      @path = path
      @fetches = []
      @owner_thread = Thread.current
      @owner_fiber = Fiber.current
    end

    def call
      response = ActiveSupport::Notifications.subscribed(method(:record), "cache_read.active_support") { request }
      Observation.new(status: response.status, html: response.media_type == "text/html",
                      fetches: @fetches.map { |fetch| [fetch.key, fetch.hit] }, ssr: retained_ssr?)
    end

    private

    def request
      Rack::MockRequest.new(Rails.application).get(
        "#{@origin}#{@path}",
        "HTTP_HOST" => @origin.sub(%r{\Ahttps?://}i, ""),
        "HTTP_ACCEPT" => "text/html",
        "REMOTE_ADDR" => "192.0.2.1"
      )
    end

    def record(*)
      return unless Thread.current.equal?(@owner_thread) && Fiber.current.equal?(@owner_fiber)

      payload = ActiveSupport::Notifications::Event.new(*).payload
      return unless payload[:super_operation] == :fetch

      native_key = native_key(payload)
      return unless native_key

      @fetches << Fetch.new(payload[:key], native_key, payload[:hit] == true, payload[:namespace], payload[:version])
    end

    def native_key(payload)
      logical_key = logical_key(payload[:key], payload[:store])
      return unless logical_key

      namespace = payload[:namespace]
      return unless namespace.nil? || namespace.is_a?(String)

      logical_key = logical_key.delete_prefix("#{namespace}:") if namespace
      logical_key if NATIVE_KEY.match?(logical_key)
    rescue Encoding::CompatibilityError
      nil
    end

    def retained_ssr?
      return false unless @fetches.size == 1

      fetch = @fetches.fetch(0)
      value = InertiaRails.cache_store.read(fetch.native_key, namespace: fetch.namespace, version: fetch.version)
      Observation.ssr_value?(value)
    end

    def logical_key(key, store)
      return unless key.is_a?(String)

      decoded = if store == "ActiveSupport::Cache::FileStore"
                  URI.decode_www_form_component(File.basename(key))
                else
                  key
                end
      decoded if decoded.valid_encoding?
    rescue ArgumentError
      # Unparseable notification keys must not interrupt unrelated cache requests.
      nil
    end
  end
end
