# frozen_string_literal: true

require "digest"

module OPA
  # Builds OPA archive (.opa) files.
  # An OPA archive is a ZIP file containing a manifest, prompt file,
  # and optional session history and data assets.
  class Archive
    attr_reader :manifest

    def initialize
      @manifest = Manifest.new
      @entries = {} # path => content (String or IO)
    end

    def prompt=(content)
      prompt_path = @manifest["Prompt-File"] || "prompt.md"
      @entries[prompt_path] = content
    end

    def add_data(path, content)
      full_path = "data/#{path}"
      @entries[full_path] = content
    end

    def add_session(content)
      session_path = @manifest["Session-File"] || "session/history.json"
      @entries[session_path] = content
    end

    def add_entry(path, content)
      @entries[path] = content
    end

    # Sign the archive with a private key and certificate.
    # Must be called before #write.
    def sign(private_key, certificate, algorithm: "SHA-256")
      @signer = Signer.new(private_key, certificate, algorithm: algorithm)
    end

    def write(io_or_path)
      if io_or_path.is_a?(String)
        File.open(io_or_path, "wb") { |f| write_to_stream(f) }
      else
        write_to_stream(io_or_path)
      end
    end

    private

    def write_to_stream(io)
      zip = ZipIO::Writer.new

      # Resolve all entry content
      entry_data = {}
      @entries.each do |path, content|
        entry_data[path] = content.is_a?(IO) ? content.read : content
      end

      # Build manifest with digests if signing
      if @signer
        entry_data.each do |path, data|
          digest = @signer.digest(data)
          @manifest.add_entry(path, { "#{@signer.digest_name}-Digest" => digest })
        end
      end

      manifest_content = @manifest.to_s

      # Write manifest
      zip.add_entry("META-INF/MANIFEST.MF", manifest_content)

      # Write signature files if signing
      if @signer
        sf_content = @signer.signature_file(manifest_content)
        zip.add_entry("META-INF/SIGNATURE.SF", sf_content)

        sig_block = @signer.signature_block(sf_content)
        zip.add_entry("META-INF/SIGNATURE#{@signer.block_extension}", sig_block)
      end

      # Write all content entries
      entry_data.each do |path, data|
        zip.add_entry(path, data)
      end

      io.write(zip.to_bytes)
    end
  end
end
