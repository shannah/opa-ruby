# frozen_string_literal: true

RSpec.describe OPA::Archive do
  describe "#write" do
    it "creates a valid ZIP with manifest and prompt" do
      archive = OPA::Archive.new
      archive.manifest["Title"] = "Test"
      archive.prompt = "# Hello\nDo the thing."

      io = StringIO.new
      archive.write(io)

      verifier = OPA::Verifier.new(StringIO.new(io.string))
      expect(verifier.manifest["Title"]).to eq("Test")
      expect(verifier.prompt).to eq("# Hello\nDo the thing.")
    end

    it "includes data assets" do
      archive = OPA::Archive.new
      archive.prompt = "Use the data."
      archive.add_data("report.csv", "a,b,c\n1,2,3")

      io = StringIO.new
      archive.write(io)

      verifier = OPA::Verifier.new(StringIO.new(io.string))
      expect(verifier.data_entries["data/report.csv"]).to eq("a,b,c\n1,2,3")
    end

    it "includes session history" do
      archive = OPA::Archive.new
      archive.prompt = "Continue."
      session_json = '{"opa_version":"0.1","session_id":"s1","messages":[]}'
      archive.add_session(session_json)

      io = StringIO.new
      archive.write(io)

      verifier = OPA::Verifier.new(StringIO.new(io.string))
      expect(verifier.session).to eq(session_json)
    end

    it "writes to a file path" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "test.opa")
        archive = OPA::Archive.new
        archive.prompt = "Test"
        archive.write(path)

        verifier = OPA::Verifier.new(path)
        expect(verifier.prompt).to eq("Test")
      end
    end
  end

  describe "signed archives" do
    let(:key_and_cert) { generate_test_keypair }
    let(:key) { key_and_cert[0] }
    let(:cert) { key_and_cert[1] }

    it "creates a signed archive that verifies" do
      archive = OPA::Archive.new
      archive.prompt = "Signed prompt."
      archive.add_data("info.txt", "some data")
      archive.sign(key, cert)

      io = StringIO.new
      archive.write(io)

      verifier = OPA::Verifier.new(StringIO.new(io.string))
      expect(verifier).to be_signed
      expect(verifier.verify!(certificate: cert)).to be true
    end

    it "detects tampering with entry content" do
      archive = OPA::Archive.new
      archive.prompt = "Original prompt."
      archive.sign(key, cert)

      io = StringIO.new
      archive.write(io)

      # Tamper: rewrite with modified prompt but same signatures
      tampered = tamper_with_entry(io.string, "prompt.md", "Tampered prompt.")

      verifier = OPA::Verifier.new(StringIO.new(tampered))
      expect { verifier.verify!(certificate: cert) }.to raise_error(OPA::SignatureError)
    end

    it "supports SHA-384 digest" do
      archive = OPA::Archive.new
      archive.prompt = "SHA-384 test"
      archive.sign(key, cert, algorithm: "SHA-384")

      io = StringIO.new
      archive.write(io)

      verifier = OPA::Verifier.new(StringIO.new(io.string))
      expect(verifier.verify!(certificate: cert)).to be true
    end

    it "supports SHA-512 digest" do
      archive = OPA::Archive.new
      archive.prompt = "SHA-512 test"
      archive.sign(key, cert, algorithm: "SHA-512")

      io = StringIO.new
      archive.write(io)

      verifier = OPA::Verifier.new(StringIO.new(io.string))
      expect(verifier.verify!(certificate: cert)).to be true
    end

    it "rejects MD5 digest" do
      archive = OPA::Archive.new
      archive.prompt = "Test"
      expect { archive.sign(key, cert, algorithm: "MD5") }.to raise_error(ArgumentError, /not allowed/)
    end

    it "rejects SHA-1 digest" do
      archive = OPA::Archive.new
      archive.prompt = "Test"
      expect { archive.sign(key, cert, algorithm: "SHA-1") }.to raise_error(ArgumentError, /not allowed/)
    end
  end
end

# Helper: create a tampered ZIP where one entry's content is replaced
# but the signature files are left intact.
def tamper_with_entry(zip_data, entry_name, new_content)
  entries = OPA::ZipIO::Reader.read(zip_data)
  writer = OPA::ZipIO::Writer.new
  entries.each do |name, content|
    if name == entry_name
      writer.add_entry(name, new_content)
    else
      writer.add_entry(name, content)
    end
  end
  writer.to_bytes
end
