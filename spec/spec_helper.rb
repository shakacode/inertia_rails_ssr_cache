# frozen_string_literal: true

require "inertia_rails_ssr_cache"

InertiaRailsSsrCache::WarmJob.logger = Logger.new(File::NULL)

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
