# frozen_string_literal: true

module OPA
  # Represents a META-INF/MANIFEST.MF file in JAR/OPA format.
  # Handles parsing and generating manifest content with main attributes
  # and per-entry sections (used for signing digests).
  class Manifest
    MAIN_ATTRS_ORDER = %w[
      Manifest-Version OPA-Version Prompt-File Title Description
      Created-By Created-At Agent-Hint Execution-Mode Session-File
      Data-Root Schema-Extensions
    ].freeze

    LINE_WIDTH = 72

    attr_reader :main_attributes, :entries

    def initialize
      @main_attributes = {
        "Manifest-Version" => "1.0",
        "OPA-Version" => OPA::OPA_VERSION
      }
      @entries = {} # name => { attr => value }
    end

    def []=(key, value)
      @main_attributes[key] = value
    end

    def [](key)
      @main_attributes[key]
    end

    def add_entry(name, attributes = {})
      @entries[name] = attributes
    end

    def to_s
      lines = []

      # Main section - ordered attributes first, then any extras
      ordered_keys = MAIN_ATTRS_ORDER & @main_attributes.keys
      extra_keys = @main_attributes.keys - MAIN_ATTRS_ORDER
      (ordered_keys + extra_keys).each do |key|
        lines << wrap_line("#{key}: #{@main_attributes[key]}")
      end
      lines << ""

      # Per-entry sections
      @entries.each do |name, attrs|
        lines << wrap_line("Name: #{name}")
        attrs.each do |key, value|
          lines << wrap_line("#{key}: #{value}")
        end
        lines << ""
      end

      lines.join("\n")
    end

    def self.parse(text)
      manifest = new
      sections = text.split(/\n(?=Name: )/m)

      # Parse main section
      main_section = sections.shift || ""
      parse_section(main_section).each do |key, value|
        manifest[key] = value
      end

      # Parse entry sections
      sections.each do |section|
        attrs = parse_section(section)
        name = attrs.delete("Name")
        manifest.add_entry(name, attrs) if name
      end

      manifest
    end

    private

    def wrap_line(line)
      return line if line.bytesize <= LINE_WIDTH

      result = line.byteslice(0, LINE_WIDTH)
      pos = LINE_WIDTH
      while pos < line.bytesize
        chunk = line.byteslice(pos, LINE_WIDTH - 1)
        result += "\n #{chunk}"
        pos += LINE_WIDTH - 1
      end
      result
    end

    def self.parse_section(text)
      # Unfold continuation lines (lines starting with a single space)
      unfolded = text.gsub(/\n /, "")
      attrs = {}
      unfolded.each_line do |line|
        line = line.chomp
        next if line.empty?
        if line =~ /\A([A-Za-z0-9_-]+):\s*(.*)\z/
          attrs[Regexp.last_match(1)] = Regexp.last_match(2)
        end
      end
      attrs
    end
  end
end
