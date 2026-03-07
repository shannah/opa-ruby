# frozen_string_literal: true

RSpec.describe OPA::Signer do
  let(:key_and_cert) { generate_test_keypair }
  let(:key) { key_and_cert[0] }
  let(:cert) { key_and_cert[1] }

  describe "#digest" do
    it "returns a Base64-encoded SHA-256 digest" do
      signer = OPA::Signer.new(key, cert, algorithm: "SHA-256")
      result = signer.digest("hello")
      expected = Base64.strict_encode64(Digest::SHA256.digest("hello"))
      expect(result).to eq(expected)
    end
  end

  describe "#signature_file" do
    it "generates a valid SF file with manifest digest" do
      signer = OPA::Signer.new(key, cert)
      manifest = "Manifest-Version: 1.0\nOPA-Version: 0.1\n\nName: prompt.md\nSHA-256-Digest: abc\n\n"
      sf = signer.signature_file(manifest)

      expect(sf).to include("Signature-Version: 1.0")
      expect(sf).to include("SHA-256-Digest-Manifest:")
      expect(sf).to include("Name: prompt.md")
      expect(sf).to include("SHA-256-Digest:")
    end
  end

  describe "#signature_block" do
    it "produces a valid DER-encoded PKCS7 signature" do
      signer = OPA::Signer.new(key, cert)
      sf_content = "Signature-Version: 1.0\nSHA-256-Digest-Manifest: abc\n\n"
      block = signer.signature_block(sf_content)

      pkcs7 = OpenSSL::PKCS7.new(block)
      expect(pkcs7).to be_a(OpenSSL::PKCS7)
    end
  end

  describe "#block_extension" do
    it "returns .RSA for RSA keys" do
      signer = OPA::Signer.new(key, cert)
      expect(signer.block_extension).to eq(".RSA")
    end

    it "returns .EC for EC keys" do
      ec_key, ec_cert = generate_test_keypair(algorithm: :ec)
      signer = OPA::Signer.new(ec_key, ec_cert)
      expect(signer.block_extension).to eq(".EC")
    end
  end

  describe "rejected algorithms" do
    it "rejects MD5" do
      expect { OPA::Signer.new(key, cert, algorithm: "MD5") }.to raise_error(ArgumentError)
    end

    it "rejects SHA-1" do
      expect { OPA::Signer.new(key, cert, algorithm: "SHA-1") }.to raise_error(ArgumentError)
    end
  end
end
