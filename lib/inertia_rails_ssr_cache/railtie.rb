# frozen_string_literal: true

# Copyright (c) 2026 ShakaCode LLC.
#
# SPDX-License-Identifier: LicenseRef-InertiaRailsSsrCache
#
# This file is part of Inertia Rails SSR Cache. Use is governed by The
# Inertia Rails SSR Cache License in LICENSE.md.

module InertiaRailsSsrCache
  class Railtie < Rails::Railtie
    rake_tasks do
      namespace :inertia_rails_ssr_cache do
        desc "Enqueue native SSR cache warming for registered public routes"
        task warm: :environment do
          puts "Enqueued SSR warming job #{InertiaRailsSsrCache.warm_later}"
        end
      end
    end
  end
end
