# frozen_string_literal: true

require "openssl"
require "base64"
require "digest"

module OPA
  # Signs OPA archives using JAR-format digital signatures.
  # Produces META-INF/SIGNATURE.SF and a signature block file (.RSA, .DSA, or .EC).
  class Signer
    SUPPORTED_DIGESTS = {
      "SHA-256" => OpenSSL::Digest::SHA256,
      "SHA-384" => OpenSSL::Digest::SHA384,
      "SHA-512" => OpenSSL::Digest::SHA512
    }.freeze

    REJECTED_DIGESTS = %w[MD5 SHA-1].freeze

    attr_reader :digest_name

    def initialize(private_key, certificate, algorithm: "SHA-256")
      raise ArgumentError, "Digest #{algorithm} is not allowed" if REJECTED_DIGESTS.include?(algorithm)
      raise ArgumentError, "Unsupported digest: #{algorithm}" unless SUPPORTED_DIGESTS.key?(algorithm)

      @private_key = private_key
      @certificate = certificate
      @digest_name = algorithm
      @digest_class = SUPPORTED_DIGESTS[algorithm]
    end

    # Compute the Base64-encoded digest of data.
    def digest(data)
      Base64.strict_encode64(@digest_class.digest(data))
    end

    # Generate the SIGNATURE.SF content from manifest content.
    # Contains a digest of the entire manifest and per-entry section digests.
    def signature_file(manifest_content)
      lines = []
      lines << "Signature-Version: 1.0"
      lines << "#{@digest_name}-Digest-Manifest: #{digest(manifest_content)}"
      lines << ""

      # Compute per-entry section digests
      sections = extract_entry_sections(manifest_content)
      sections.each do |name, section_text|
        lines << "Name: #{name}"
        lines << "#{@digest_name}-Digest: #{digest(section_text)}"
        lines << ""
      end

      lines.join("\n")
    end

    # Create the PKCS#7 signature block over the SF content.
    def signature_block(sf_content)
      flags = OpenSSL::PKCS7::BINARY | OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::NOSMIMECAP
      pkcs7 = OpenSSL::PKCS7.sign(@certificate, @private_key, sf_content, [], flags)
      pkcs7.to_der
    end

    # File extension for the signature block based on key type.
    def block_extension
      case @private_key
      when OpenSSL::PKey::RSA then ".RSA"
      when OpenSSL::PKey::DSA then ".DSA"
      when OpenSSL::PKey::EC then ".EC"
      else ".RSA"
      end
    end

    private

    # Extract individual entry sections from manifest text.
    # Each section starts with "Name: " and ends at the next blank line.
    def extract_entry_sections(manifest_content)
      sections = {}
      # Split on double newline to get sections, keep the trailing newline
      parts = manifest_content.split(/(?=Name: )/m)
      parts.each do |part|
        next unless part.start_with?("Name: ")
        name_line = part.lines.first.chomp
        name = name_line.sub(/\AName: /, "")
        # Section text includes the trailing newline (important for digest)
        sections[name] = part
      end
      sections
    end
  end
end
