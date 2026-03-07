# frozen_string_literal: true

module OPA
  class Policy
    attr_reader :package_name, :rules, :imports, :default_rules

    def initialize(package_name, &block)
      @package_name = package_name
      @rules = []
      @imports = []
      @default_rules = {}
      instance_eval(&block) if block_given?
    end

    def add_import(path)
      @imports << path
      self
    end

    def default(name, value)
      @default_rules[name] = value
      self
    end

    def rule(name, value: true, &block)
      r = Rule.new(name, value: value, &block)
      @rules << r
      r
    end

    def to_rego
      lines = []
      lines << "package #{@package_name}"
      lines << ""

      @imports.each { |i| lines << "import #{i}" }
      lines << "" unless @imports.empty?

      @default_rules.each do |name, value|
        lines << "default #{name} = #{rego_literal(value)}"
      end
      lines << "" unless @default_rules.empty?

      @rules.each_with_index do |r, i|
        lines << r.to_rego
        lines << "" if i < @rules.size - 1
      end

      lines.join("\n") + "\n"
    end

    def save(path)
      File.write(path, to_rego)
    end

    private

    def rego_literal(val)
      case val
      when true then "true"
      when false then "false"
      when String then "\"#{val}\""
      when Numeric then val.to_s
      else val.to_s
      end
    end
  end
end
