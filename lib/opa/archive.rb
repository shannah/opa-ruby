# frozen_string_literal: true

require "zip"
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
      buffer = StringIO.new
      build_zip(buffer)
      io.write(buffer.string)
    end

    def build_zip(io)
      Zip::OutputStream.write_buffer(io) do |zip|
        # Compute digests for all entries if signing
        entry_digests = {}
        @entries.each do |path, content|
          data = content.is_a?(IO) ? content.read : content
          entry_digests[path] = data
        end

        # Build manifest with digests if signing
        if @signer
          entry_digests.each do |path, data|
            digest = @signer.digest(data)
            @manifest.add_entry(path, { "#{@signer.digest_name}-Digest" => digest })
          end
        end

        manifest_content = @manifest.to_s

        # Write manifest
        zip.put_next_entry("META-INF/MANIFEST.MF")
        zip.write(manifest_content)

        # Write signature files if signing
        if @signer
          sf_content = @signer.signature_file(manifest_content)
          zip.put_next_entry("META-INF/SIGNATURE.SF")
          zip.write(sf_content)

          sig_block = @signer.signature_block(sf_content)
          zip.put_next_entry("META-INF/SIGNATURE#{@signer.block_extension}")
          zip.write(sig_block)
        end

        # Write all content entries
        entry_digests.each do |path, data|
          zip.put_next_entry(path)
          zip.write(data)
        end
      end
    end
  end
end
