# frozen_string_literal: true

# Public configuration/enqueue logic and the pure safety/proof domain are checked.
# Job dispatch, Rack and notification adaptation are covered by real framework tests;
# narrow framework interfaces for the public facade are in sig/framework_boundary.rbs.
target :core do
  signature "sig"
  library "uri"
  check "lib/inertia_rails_ssr_cache.rb"
  check "lib/inertia_rails_ssr_cache/configuration.rb"
  check "lib/inertia_rails_ssr_cache/result.rb"
end
