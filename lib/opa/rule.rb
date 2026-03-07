# frozen_string_literal: true

module OPA
  class Rule
    attr_reader :name, :value, :conditions

    def initialize(name, value: true, &block)
      @name = name
      @value = value
      @conditions = []
      instance_eval(&block) if block_given?
    end

    def condition(expression)
      @conditions << expression
      self
    end

    def to_rego
      lines = []
      if @conditions.empty?
        lines << "#{@name} = #{rego_value(@value)}"
      else
        lines << "#{@name} = #{rego_value(@value)} {"
        @conditions.each { |c| lines << "  #{c}" }
        lines << "}"
      end
      lines.join("\n")
    end

    private

    def rego_value(val)
      case val
      when true then "true"
      when false then "false"
      when String then "\"#{val}\""
      when Numeric then val.to_s
      when Array then "[#{val.map { |v| rego_value(v) }.join(", ")}]"
      when Hash then "{#{val.map { |k, v| "#{rego_value(k)}: #{rego_value(v)}" }.join(", ")}}"
      else val.to_s
      end
    end
  end
end
