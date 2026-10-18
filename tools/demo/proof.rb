# frozen_string_literal: true

class DemoProof
  def initialize(directory, release)
    @directory = directory
    @release = release
  end

  def verify(responses)
    responses.each { |response| verify_html(response) }
    web_pid = Integer(responses.first["X-Demo-Pid"])
    events = records("events.jsonl")
    target = events.find { |event| event["type"] == "target" && event["outcome"] == "reused" }
    raise "Worker did not report reuse" unless target && target.fetch("pid") != web_pid

    verify_cache(events, target.fetch("pid"), web_pid)
    { outcome: "reused", worker_pid: target.fetch("pid"), web_pid: web_pid, web_cache_hits: 2, ssr_renders: 1 }
  end

  private

  def records(file)
    File.readlines(File.join(@directory, file)).map { |line| JSON.parse(line) }
  end

  def verify_html(response)
    markers = ["Warmed before you arrive", "<title", "data-build=\"#{@release}\""]
    return if response.code == "200" && markers.all? { |marker| response.body.include?(marker) }

    raise "HTTP visitor did not receive the expected SSR body, head and build"
  end

  def verify_cache(events, worker_pid, web_pid)
    worker = cache_events(events, worker_pid)
    web = cache_events(events, web_pid)
    verify_hits(worker, [false, true])
    verify_hits(web, [true, true])
    verify_identity(worker + web)
    raise "Node rendered more than once" unless records("renders.jsonl").length == 1
  end

  def cache_events(events, pid)
    events.select { |event| event["type"] == "cache" && event["pid"] == pid }
  end

  def verify_hits(events, expected)
    raise "Unexpected native cache misses/hits" unless events.map { |event| event.fetch("hit") } == expected
  end

  def verify_identity(events)
    raise "Cache identities differ" unless events.map { |event| event.fetch("key") }.uniq.length == 1
  end
end
