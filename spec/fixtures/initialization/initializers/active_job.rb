# frozen_string_literal: true

Rails.application.config.active_job.queue_adapter = :test
Rails.application.config.active_job.queue_name_prefix = "initializer-prefix"
