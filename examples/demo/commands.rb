# frozen_string_literal: true

require_relative "config/environment"

module WarmerDemo
  module Commands
    def self.prepare
      schema = queue_schema
      existing = ActiveRecord::Base.connection.tables.grep(/^solid_queue_/)
      if existing.empty?
        ActiveRecord::Schema.verbose = false
        load schema
      elsif existing.sort != schema_tables(schema)
        raise "Incomplete Solid Queue schema: use a fresh DEMO_RUNTIME directory"
      end
      { status: "prepared", runtime: RUNTIME.to_s }
    end

    def self.queue_schema
      gem_root = Gem.loaded_specs.fetch("solid_queue").full_gem_path
      File.join(gem_root, "lib/generators/solid_queue/install/templates/db/queue_schema.rb")
    end

    def self.schema_tables(schema)
      tables = File.read(schema).scan(/create_table\s+"(solid_queue_\w+)"/).flatten.sort
      raise "The installed Solid Queue schema could not be identified" if tables.empty?

      tables
    end

    def self.status(job_id)
      job = SolidQueue::Job.find_by!(active_job_id: job_id)
      failure = job.failed_execution
      state = if failure then "failed"
              elsif job.finished? then "finished"
              else "pending"
              end
      { job_id: job_id, status: state, error: failure&.error&.slice("exception_class", "message") }
    end

    def self.call(operation, job_id = nil)
      case operation
      when "prepare" then prepare
      when "enqueue" then { job_id: InertiaRailsSsrCache.warm_later }
      when "status" then status(job_id)
      else raise ArgumentError, "Expected prepare, enqueue or status JOB_ID"
      end
    end
  end
end

puts JSON.generate(WarmerDemo::Commands.call(*ARGV))
