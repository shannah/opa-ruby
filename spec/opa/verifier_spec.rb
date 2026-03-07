# frozen_string_literal: true

RSpec.describe OPA::Verifier do
  let(:key_and_cert) { generate_test_keypair }
  let(:key) { key_and_cert[0] }
  let(:cert) { key_and_cert[1] }

  def build_archive(signed: false, algorithm: "SHA-256", &block)
    archive = OPA::Archive.new
    archive.prompt = "Test prompt"
    block&.call(archive)
    archive.sign(key, cert, algorithm: algorithm) if signed
    io = StringIO.new
    archive.write(io)
    StringIO.new(io.string)
  end

  describe "reading unsigned archives" do
    it "reads the manifest" do
      verifier = OPA::Verifier.new(build_archive)
      expect(verifier.manifest["Manifest-Version"]).to eq("1.0")
      expect(verifier.manifest["OPA-Version"]).to eq("0.1")
    end

    it "reads the prompt" do
      verifier = OPA::Verifier.new(build_archive)
      expect(verifier.prompt).to eq("Test prompt")
    end

    it "reports as not signed" do
      verifier = OPA::Verifier.new(build_archive)
      expect(verifier).not_to be_signed
    end

    it "raises when verifying unsigned archive" do
      verifier = OPA::Verifier.new(build_archive)
      expect { verifier.verify! }.to raise_error(OPA::SignatureError, /not signed/)
    end
  end

  describe "reading signed archives" do
    it "verifies a valid signed archive" do
      verifier = OPA::Verifier.new(build_archive(signed: true))
      expect(verifier.verify!(certificate: cert)).to be true
    end

    it "reports as signed" do
      verifier = OPA::Verifier.new(build_archive(signed: true))
      expect(verifier).to be_signed
    end

    it "reads entries from a signed archive" do
      io = build_archive(signed: true) do |a|
        a.add_data("notes.txt", "hello world")
      end
      verifier = OPA::Verifier.new(io)
      expect(verifier.prompt).to eq("Test prompt")
      expect(verifier.data_entries["data/notes.txt"]).to eq("hello world")
    end
  end

  describe "path traversal protection" do
    it "rejects paths with .." do
      # Build a malicious ZIP manually
      buf = StringIO.new
      Zip::OutputStream.write_buffer(buf) do |zip|
        zip.put_next_entry("META-INF/MANIFEST.MF")
        zip.write("Manifest-Version: 1.0\nOPA-Version: 0.1\n\n")
        zip.put_next_entry("../etc/passwd")
        zip.write("malicious")
      end

      expect { OPA::Verifier.new(StringIO.new(buf.string)) }.to raise_error(OPA::SignatureError, /traversal/)
    end
  end

  describe "#read_entry" do
    it "returns raw content for any path" do
      io = build_archive do |a|
        a.add_entry("custom/path.txt", "custom content")
      end
      verifier = OPA::Verifier.new(io)
      expect(verifier.read_entry("custom/path.txt")).to eq("custom content")
    end
  end
end
