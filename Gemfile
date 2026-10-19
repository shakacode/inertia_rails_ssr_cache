# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "bundler-audit", "~> 0.9", require: false
gem "rails", ENV.fetch("RAILS_VERSION", "~> 8.1.0")
gem "rake", "~> 13.4"
gem "rbs", "~> 4.2", require: false
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.92", require: false
gem "rubocop-performance", "~> 1.27", require: false
gem "rubocop-rspec", "~> 3.10", require: false
gem "steep", "~> 2.1", require: false

# Runnable demo infrastructure; not runtime dependencies of the gem.
gem "puma", "~> 8.0", require: false
gem "solid_queue", "~> 1.3", require: false
gem "sqlite3", "~> 2.7", require: false
