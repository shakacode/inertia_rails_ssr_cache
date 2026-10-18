# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)
ENV["RAILS_ENV"] ||= "demo"

require "bundler/setup"
require "fileutils"
require "pathname"

module WarmerDemo
  RUNTIME = Pathname.new(ENV.fetch("DEMO_RUNTIME"))
  raise ArgumentError, "DEMO_RUNTIME must be an absolute path" unless RUNTIME.absolute?

  RELEASE = ENV.fetch("APP_RELEASE", "demo-v1")
  WEB_PORT = Integer(ENV.fetch("DEMO_WEB_PORT", "3300"))
  SSR_PORT = Integer(ENV.fetch("DEMO_SSR_PORT", "13373"))

  FileUtils.mkdir_p(RUNTIME.join("public"))
end
