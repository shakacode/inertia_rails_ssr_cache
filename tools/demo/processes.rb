# frozen_string_literal: true

class DemoProcesses
  def initialize(environment, app)
    @environment = environment
    @directory = environment.fetch("DEMO_RUNTIME")
    @app = app
    @children = {}
  end

  def launch(name, *)
    log = File.join(@directory, "#{name}.log")
    @children[name] = Process.spawn(@environment, *, chdir: @app, out: log, err: log, pgroup: true)
  end

  def wait(label)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    loop do
      check
      return if yield
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "Timed out waiting for #{label}; logs: #{@directory}"
      end

      sleep 0.1
    end
  end

  def check
    @children.each do |name, pid|
      next unless Process.waitpid(pid, Process::WNOHANG)

      raise "#{name} exited unexpectedly:\n#{File.read(File.join(@directory, "#{name}.log"))}"
    end
  end

  def get(origin, path)
    uri = URI("#{origin}#{path}")
    Net::HTTP.start(uri.host, uri.port, nil, open_timeout: 1, read_timeout: 5) { |http| http.get(uri.request_uri) }
  rescue Errno::ECONNREFUSED
    Struct.new(:code).new("unavailable")
  end

  def close
    # Signal all groups before waiting so no child waits for another still-running service.
    terminate
    @children.each_value { |pid| reap(pid) }
  end

  private

  def terminate
    @children.each_value { |pid| signal_group("TERM", pid) }
  end

  def reap(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until Process.waitpid(pid, Process::WNOHANG)
      signal_group("KILL", pid) if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
  rescue Errno::ECHILD
    nil
  end

  def signal_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH
    nil
  end
end
