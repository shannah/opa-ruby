# frozen_string_literal: true

require "zip"
require "openssl"
require "base64"
require "digest"

module OPA
  # Reads and verifies OPA archives.
  # Supports signature verification using JAR-format signing.
  class Verifier
    SUPPORTED_DIGESTS = Signer::SUPPORTED_DIGESTS
    REJECTED_DIGESTS = Signer::REJECTED_DIGESTS

    attr_reader :manifest, :entries

    def initialize(io_or_path)
      @raw_entries = {}
      if io_or_path.is_a?(String)
        File.open(io_or_path, "rb") { |f| read_zip(f) }
      else
        read_zip(io_or_path)
      end
    end

    def signed?
      @raw_entries.key?("META-INF/SIGNATURE.SF")
    end

    # Verify the archive signature. Returns true if valid.
    # Raises OPA::SignatureError on failure.
    def verify!(certificate: nil)
      raise SignatureError, "Archive is not signed" unless signed?

      sf_content = @raw_entries["META-INF/SIGNATURE.SF"]
      sf_attrs = parse_sf(sf_content)

      # Find and verify the signature block
      block_entry = find_signature_block
      raise SignatureError, "No signature block file found" unless block_entry

      block_data = @raw_entries[block_entry]
      verify_pkcs7_signature(block_data, sf_content, certificate)

      # Verify manifest digest
      manifest_content = @raw_entries["META-INF/MANIFEST.MF"]
      digest_name = detect_digest_algorithm(sf_attrs[:main])
      verify_digest(digest_name, manifest_content, sf_attrs[:main]["#{digest_name}-Digest-Manifest"],
                    "Manifest digest mismatch")

      # Verify individual entry digests
      sf_attrs[:entries].each do |name, attrs|
        entry_digest_name = detect_digest_algorithm(attrs)
        manifest_section = extract_manifest_section(manifest_content, name)
        raise SignatureError, "No manifest section for #{name}" unless manifest_section

        verify_digest(entry_digest_name, manifest_section, attrs["#{entry_digest_name}-Digest"],
                      "Section digest mismatch for #{name}")
      end

      # Verify manifest entry digests against actual content
      @manifest.entries.each do |name, attrs|
        entry_digest_name = detect_digest_algorithm(attrs)
        next unless entry_digest_name

        expected = attrs["#{entry_digest_name}-Digest"]
        next unless expected

        actual_content = @raw_entries[name]
        raise SignatureError, "Missing entry: #{name}" unless actual_content

        verify_digest(entry_digest_name, actual_content, expected,
                      "Content digest mismatch for #{name}")
      end

      true
    end

    # Read a specific entry from the archive.
    def read_entry(path)
      @raw_entries[path]
    end

    def prompt
      prompt_path = @manifest["Prompt-File"] || "prompt.md"
      @raw_entries[prompt_path]
    end

    def session
      session_path = @manifest["Session-File"] || "session/history.json"
      @raw_entries[session_path]
    end

    def data_entries
      prefix = @manifest["Data-Root"] || "data/"
      @raw_entries.select { |k, _| k.start_with?(prefix) }
    end

    private

    def read_zip(io)
      data = io.read
      Zip::InputStream.open(StringIO.new(data)) do |zip|
        while (entry = zip.get_next_entry)
          next if entry.directory?
          path = entry.name
          validate_path!(path)
          @raw_entries[path] = zip.read
        end
      end

      manifest_content = @raw_entries["META-INF/MANIFEST.MF"]
      raise "Missing META-INF/MANIFEST.MF" unless manifest_content

      @manifest = Manifest.parse(manifest_content)
    end

    def validate_path!(path)
      raise SignatureError, "Path traversal detected: #{path}" if path.include?("..") || path.start_with?("/")
    end

    def find_signature_block
      %w[.RSA .DSA .EC].each do |ext|
        key = "META-INF/SIGNATURE#{ext}"
        return key if @raw_entries.key?(key)
      end
      nil
    end

    def verify_pkcs7_signature(block_data, sf_content, certificate)
      pkcs7 = OpenSSL::PKCS7.new(block_data)

      store = OpenSSL::X509::Store.new
      if certificate
        store.add_cert(certificate)
      else
        # Extract the certificate from the PKCS7 structure
        pkcs7.certificates&.each { |c| store.add_cert(c) }
      end

      flags = OpenSSL::PKCS7::BINARY | OpenSSL::PKCS7::NOVERIFY
      flags = OpenSSL::PKCS7::BINARY if certificate

      unless pkcs7.verify(certificate ? [certificate] : [], store, sf_content, flags)
        raise SignatureError, "Digital signature verification failed"
      end
    end

    def parse_sf(content)
      main_attrs = {}
      entries = {}

      sections = content.split(/(?=Name: )/m)
      main_section = sections.shift || ""

      main_section.each_line do |line|
        line = line.chomp
        next if line.empty?
        if line =~ /\A([A-Za-z0-9_-]+):\s*(.*)\z/
          main_attrs[Regexp.last_match(1)] = Regexp.last_match(2)
        end
      end

      sections.each do |section|
        attrs = {}
        name = nil
        section.each_line do |line|
          line = line.chomp
          next if line.empty?
          if line =~ /\A([A-Za-z0-9_-]+):\s*(.*)\z/
            key, val = Regexp.last_match(1), Regexp.last_match(2)
            if key == "Name"
              name = val
            else
              attrs[key] = val
            end
          end
        end
        entries[name] = attrs if name
      end

      { main: main_attrs, entries: entries }
    end

    def detect_digest_algorithm(attrs)
      SUPPORTED_DIGESTS.each_key do |name|
        return name if attrs.any? { |k, _| k.include?(name) }
      end
      raise SignatureError, "No supported digest algorithm found"
    end

    def verify_digest(algorithm, data, expected_b64, message)
      raise SignatureError, "Rejected digest algorithm: #{algorithm}" if REJECTED_DIGESTS.include?(algorithm)

      digest_class = SUPPORTED_DIGESTS[algorithm]
      raise SignatureError, "Unsupported digest: #{algorithm}" unless digest_class

      actual = Base64.strict_encode64(digest_class.digest(data))
      raise SignatureError, "#{message}: expected #{expected_b64}, got #{actual}" unless actual == expected_b64
    end

    def extract_manifest_section(manifest_content, name)
      parts = manifest_content.split(/(?=Name: )/m)
      parts.find { |p| p.start_with?("Name: #{name}\n") || p.start_with?("Name: #{name}\r\n") }
    end
  end

  class SignatureError < StandardError; end
end
