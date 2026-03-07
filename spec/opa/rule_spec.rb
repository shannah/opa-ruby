# frozen_string_literal: true

RSpec.describe OPA::Rule do
  describe "#to_rego" do
    it "generates a simple rule without conditions" do
      rule = OPA::Rule.new("allow")
      expect(rule.to_rego).to eq('allow = true')
    end

    it "generates a rule with a false value" do
      rule = OPA::Rule.new("deny", value: false)
      expect(rule.to_rego).to eq('deny = false')
    end

    it "generates a rule with a string value" do
      rule = OPA::Rule.new("role", value: "admin")
      expect(rule.to_rego).to eq('role = "admin"')
    end

    it "generates a rule with conditions" do
      rule = OPA::Rule.new("allow") do
        condition 'input.method == "GET"'
        condition 'input.path == "/public"'
      end

      expected = <<~REGO.chomp
        allow = true {
          input.method == "GET"
          input.path == "/public"
        }
      REGO
      expect(rule.to_rego).to eq(expected)
    end

    it "supports adding conditions via method chaining" do
      rule = OPA::Rule.new("allow")
      rule.condition('input.user == "admin"')
      rule.condition("input.action == \"read\"")

      expect(rule.to_rego).to include('input.user == "admin"')
      expect(rule.to_rego).to include('input.action == "read"')
    end

    it "generates a rule with a numeric value" do
      rule = OPA::Rule.new("max_retries", value: 3)
      expect(rule.to_rego).to eq("max_retries = 3")
    end
  end
end
