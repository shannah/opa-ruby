# frozen_string_literal: true

RSpec.describe OPA::Manifest do
  describe "#to_s" do
    it "includes required attributes by default" do
      manifest = OPA::Manifest.new
      output = manifest.to_s
      expect(output).to include("Manifest-Version: 1.0")
      expect(output).to include("OPA-Version: 0.1")
    end

    it "includes custom attributes" do
      manifest = OPA::Manifest.new
      manifest["Title"] = "Test Archive"
      manifest["Created-By"] = "opa-ruby"
      output = manifest.to_s
      expect(output).to include("Title: Test Archive")
      expect(output).to include("Created-By: opa-ruby")
    end

    it "includes per-entry sections" do
      manifest = OPA::Manifest.new
      manifest.add_entry("prompt.md", { "SHA-256-Digest" => "abc123" })
      output = manifest.to_s
      expect(output).to include("Name: prompt.md")
      expect(output).to include("SHA-256-Digest: abc123")
    end

    it "wraps long lines at 72 bytes" do
      manifest = OPA::Manifest.new
      manifest["Description"] = "A" * 200
      output = manifest.to_s
      output.each_line do |line|
        expect(line.chomp.bytesize).to be <= 72
      end
    end
  end

  describe ".parse" do
    it "round-trips a manifest" do
      original = OPA::Manifest.new
      original["Title"] = "Round Trip"
      original["Execution-Mode"] = "batch"
      original.add_entry("prompt.md", { "SHA-256-Digest" => "abc123" })
      original.add_entry("data/file.csv", { "SHA-256-Digest" => "def456" })

      parsed = OPA::Manifest.parse(original.to_s)
      expect(parsed["Manifest-Version"]).to eq("1.0")
      expect(parsed["Title"]).to eq("Round Trip")
      expect(parsed["Execution-Mode"]).to eq("batch")
      expect(parsed.entries["prompt.md"]["SHA-256-Digest"]).to eq("abc123")
      expect(parsed.entries["data/file.csv"]["SHA-256-Digest"]).to eq("def456")
    end

    it "handles continuation lines from wrapping" do
      manifest = OPA::Manifest.new
      long_desc = "B" * 200
      manifest["Description"] = long_desc
      parsed = OPA::Manifest.parse(manifest.to_s)
      expect(parsed["Description"]).to eq(long_desc)
    end
  end
end
