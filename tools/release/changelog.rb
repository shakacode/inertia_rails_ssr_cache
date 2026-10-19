# frozen_string_literal: true

module Release
  # Reads release sections from CHANGELOG.md. A section heading is "## VERSION — DATE".
  class Changelog
    HEADING = /^## (\S+) — (.+)$/

    def initialize(text)
      @text = text
    end

    def latest_version
      @text[HEADING, 1]
    end

    def dated?(version)
      date = headings[version]
      !date.nil? && date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    end

    # The section body for a version, without its heading, or nil.
    def section(version)
      lines = @text.lines
      start = lines.index { |line| line.match(HEADING)&.captures&.first == version }
      return unless start

      finish = lines[(start + 1)..].index { |line| line.start_with?("## ") }
      body = finish ? lines[(start + 1), finish] : lines[(start + 1)..]
      body.join.strip
    end

    private

    def headings
      @text.scan(HEADING).to_h { |version, date| [version, date.strip] }
    end
  end
end
