# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "rbconfig"

RSpec.describe InertiaRailsSsrCache::Railtie do
  def boot(mode)
    fixture = File.expand_path("../../fixtures/initialization/application.rb", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-Ilib", fixture, mode)
    raise "Initialization fixture failed: #{stderr}" unless status.success?

    JSON.parse(stdout.lines.last)
  end

  it "honors Active Job settings from application initializers", :aggregate_failures do
    control = boot("control")
    with_gem = boot("with_gem")

    expect(control).to include("base_adapter" => "test", "base_queue_prefix" => "initializer-prefix")
    expect(with_gem).to include("base_adapter" => "test", "base_queue_prefix" => "initializer-prefix",
                                "warm_job_adapter" => "test", "warm_job_queue_prefix" => "initializer-prefix")
    expect(with_gem.fetch("base_loaded_before_initialization")).to be false
  end
end
