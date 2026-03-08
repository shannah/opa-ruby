# frozen_string_literal: true

require "optparse"
require "opa"

module OPA
  class CLI
    COMMANDS = %w[pack verify inspect].freeze

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      if @argv.empty? || %w[-h --help help].include?(@argv.first)
        print_usage
        return 0
      end

      if %w[-v --version].include?(@argv.first)
        $stdout.puts "opa-ruby #{OPA::VERSION}"
        return 0
      end

      command = @argv.shift
      unless COMMANDS.include?(command)
        $stderr.puts "Unknown command: #{command}"
        $stderr.puts "Run 'opa --help' for usage."
        return 1
      end

      send("run_#{command}")
    rescue StandardError => e
      $stderr.puts "Error: #{e.message}"
      1
    end

    private

    def run_pack
      options = { title: nil, data: [], session: nil, key: nil, cert: nil, algorithm: "SHA-256", output: nil }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: opa pack PROMPT_FILE [options]"
        opts.on("-o", "--output FILE", "Output .opa file (default: <prompt_basename>.opa)") { |v| options[:output] = v }
        opts.on("-t", "--title TITLE", "Archive title") { |v| options[:title] = v }
        opts.on("-d", "--data FILE", "Add a data file (repeatable)") { |v| options[:data] << v }
        opts.on("-s", "--session FILE", "Session history JSON file") { |v| options[:session] = v }
        opts.on("-k", "--key FILE", "Private key PEM file for signing") { |v| options[:key] = v }
        opts.on("-c", "--cert FILE", "Certificate PEM file for signing") { |v| options[:cert] = v }
        opts.on("--algorithm ALG", "Digest algorithm (SHA-256, SHA-384, SHA-512)") { |v| options[:algorithm] = v }
      end
      parser.parse!(@argv)

      prompt_file = @argv.shift
      unless prompt_file
        $stderr.puts parser.help
        return 1
      end

      unless File.exist?(prompt_file)
        $stderr.puts "Prompt file not found: #{prompt_file}"
        return 1
      end

      archive = Archive.new
      archive.manifest["Prompt-File"] = File.basename(prompt_file)
      archive.manifest["Created-By"] = "opa-ruby/#{OPA::VERSION}"
      archive.manifest["Title"] = options[:title] if options[:title]
      archive.prompt = File.read(prompt_file)

      options[:data].each do |data_file|
        unless File.exist?(data_file)
          $stderr.puts "Data file not found: #{data_file}"
          return 1
        end
        archive.add_data(File.basename(data_file), File.read(data_file))
      end

      if options[:session]
        unless File.exist?(options[:session])
          $stderr.puts "Session file not found: #{options[:session]}"
          return 1
        end
        archive.add_session(File.read(options[:session]))
      end

      if options[:key] || options[:cert]
        unless options[:key] && options[:cert]
          $stderr.puts "Both --key and --cert are required for signing."
          return 1
        end
        key = OpenSSL::PKey.read(File.read(options[:key]))
        cert = OpenSSL::X509::Certificate.new(File.read(options[:cert]))
        archive.sign(key, cert, algorithm: options[:algorithm])
      end

      output = options[:output] || File.basename(prompt_file, File.extname(prompt_file)) + ".opa"
      archive.write(output)
      $stdout.puts "Created #{output}"
      0
    end

    def run_verify
      options = { cert: nil }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: opa verify ARCHIVE [options]"
        opts.on("-c", "--cert FILE", "Certificate PEM file to verify against") { |v| options[:cert] = v }
      end
      parser.parse!(@argv)

      archive_file = @argv.shift
      unless archive_file
        $stderr.puts parser.help
        return 1
      end

      unless File.exist?(archive_file)
        $stderr.puts "Archive not found: #{archive_file}"
        return 1
      end

      verifier = Verifier.new(archive_file)

      unless verifier.signed?
        $stderr.puts "Archive is not signed."
        return 1
      end

      cert = nil
      if options[:cert]
        cert = OpenSSL::X509::Certificate.new(File.read(options[:cert]))
      end

      verifier.verify!(certificate: cert)
      $stdout.puts "Signature valid."
      0
    rescue SignatureError => e
      $stderr.puts "Verification failed: #{e.message}"
      1
    end

    def run_inspect
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: opa inspect ARCHIVE"
      end
      parser.parse!(@argv)

      archive_file = @argv.shift
      unless archive_file
        $stderr.puts parser.help
        return 1
      end

      unless File.exist?(archive_file)
        $stderr.puts "Archive not found: #{archive_file}"
        return 1
      end

      verifier = Verifier.new(archive_file)
      manifest = verifier.manifest

      $stdout.puts "Archive: #{archive_file}"
      $stdout.puts "Signed: #{verifier.signed? ? "yes" : "no"}"
      $stdout.puts ""
      $stdout.puts "Manifest Attributes:"
      manifest.main_attributes.each do |key, value|
        $stdout.puts "  #{key}: #{value}"
      end

      if manifest.entries.any?
        $stdout.puts ""
        $stdout.puts "Entries:"
        manifest.entries.each_key do |name|
          $stdout.puts "  #{name}"
        end
      end

      prompt = verifier.prompt
      if prompt
        $stdout.puts ""
        $stdout.puts "Prompt:"
        prompt.each_line.first(5).each { |l| $stdout.puts "  #{l}" }
        $stdout.puts "  ..." if prompt.lines.size > 5
      end

      0
    end

    def print_usage
      $stdout.puts <<~USAGE
        opa-ruby #{OPA::VERSION} - Open Prompt Archive tool

        Usage: opa <command> [options]

        Commands:
          pack      Create an OPA archive from a prompt file
          verify    Verify a signed OPA archive
          inspect   Show archive contents and metadata

        Options:
          -v, --version    Show version
          -h, --help       Show this help

        Run 'opa <command> --help' for command-specific options.
      USAGE
    end
  end
end
