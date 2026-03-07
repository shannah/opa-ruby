# frozen_string_literal: true

RSpec.describe OPA::Policy do
  describe "#to_rego" do
    it "generates a minimal policy with just a package" do
      policy = OPA::Policy.new("example")
      output = policy.to_rego
      expect(output).to start_with("package example\n")
    end

    it "generates a policy with imports" do
      policy = OPA::Policy.new("example.authz") do
        add_import "data.users"
        add_import "input"
      end

      output = policy.to_rego
      expect(output).to include("import data.users")
      expect(output).to include("import input")
    end

    it "generates a policy with default rules" do
      policy = OPA::Policy.new("example.authz") do
        default "allow", false
      end

      output = policy.to_rego
      expect(output).to include("default allow = false")
    end

    it "generates a complete policy" do
      policy = OPA::Policy.new("example.authz") do
        add_import "data.users"

        default "allow", false

        rule "allow" do
          condition 'input.method == "GET"'
          condition 'input.path == "/public"'
        end

        rule "allow" do
          condition "input.user == data.users[_]"
        end
      end

      expected = <<~REGO
        package example.authz

        import data.users

        default allow = false

        allow = true {
          input.method == "GET"
          input.path == "/public"
        }

        allow = true {
          input.user == data.users[_]
        }
      REGO

      expect(policy.to_rego).to eq(expected)
    end
  end

  describe "#save" do
    it "writes the policy to a file" do
      policy = OPA::Policy.new("test") do
        default "allow", false
      end

      tmpfile = "/tmp/test_policy_#{Process.pid}.rego"
      begin
        policy.save(tmpfile)
        content = File.read(tmpfile)
        expect(content).to include("package test")
        expect(content).to include("default allow = false")
      ensure
        File.delete(tmpfile) if File.exist?(tmpfile)
      end
    end
  end

  describe "#rule" do
    it "returns the created rule" do
      policy = OPA::Policy.new("test")
      r = policy.rule("allow") { condition "true" }
      expect(r).to be_a(OPA::Rule)
      expect(r.name).to eq("allow")
    end
  end
end
