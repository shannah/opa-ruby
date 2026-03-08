# frozen_string_literal: true

require "opa/cli"

RSpec.describe OPA::CLI do
  let(:tmpdir) { Dir.mktmpdir }
  let(:prompt_file) { File.join(tmpdir, "prompt.md") }
  let(:output_file) { File.join(tmpdir, "prompt.opa") }

  before do
    File.write(prompt_file, "# Test Prompt\nDo the thing.")
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  def cli(*args)
    OPA::CLI.new(args.flatten)
  end

  def capture_stdout(&block)
    original = $stdout
    $stdout = StringIO.new
    block.call
    $stdout.string
  ensure
    $stdout = original
  end

  def capture_stderr(&block)
    original = $stderr
    $stderr = StringIO.new
    block.call
    $stderr.string
  ensure
    $stderr = original
  end

  describe "--help" do
    it "prints usage and returns 0" do
      output = capture_stdout { expect(cli("--help").run).to eq(0) }
      expect(output).to include("Usage: opa <command>")
      expect(output).to include("pack")
      expect(output).to include("verify")
      expect(output).to include("inspect")
    end

    it "prints usage when no arguments given" do
      output = capture_stdout { expect(cli.run).to eq(0) }
      expect(output).to include("Usage: opa <command>")
    end
  end

  describe "--version" do
    it "prints version and returns 0" do
      output = capture_stdout { expect(cli("--version").run).to eq(0) }
      expect(output).to include("opa-ruby #{OPA::VERSION}")
    end
  end

  describe "unknown command" do
    it "returns 1 with error message" do
      output = capture_stderr { expect(cli("bogus").run).to eq(1) }
      expect(output).to include("Unknown command: bogus")
    end
  end

  describe "pack" do
    it "creates an unsigned archive" do
      output = capture_stdout do
        expect(cli("pack", prompt_file, "-o", output_file).run).to eq(0)
      end
      expect(output).to include("Created #{output_file}")
      expect(File.exist?(output_file)).to be true

      verifier = OPA::Verifier.new(output_file)
      expect(verifier.prompt).to eq("# Test Prompt\nDo the thing.")
      expect(verifier).not_to be_signed
    end

    it "sets title in manifest" do
      capture_stdout do
        cli("pack", prompt_file, "-o", output_file, "-t", "My Task").run
      end
      verifier = OPA::Verifier.new(output_file)
      expect(verifier.manifest["Title"]).to eq("My Task")
    end

    it "adds data files" do
      data_file = File.join(tmpdir, "report.csv")
      File.write(data_file, "a,b\n1,2")

      capture_stdout do
        cli("pack", prompt_file, "-o", output_file, "-d", data_file).run
      end
      verifier = OPA::Verifier.new(output_file)
      expect(verifier.data_entries["data/report.csv"]).to eq("a,b\n1,2")
    end

    it "adds session file" do
      session_file = File.join(tmpdir, "session.json")
      File.write(session_file, '{"messages":[]}')

      capture_stdout do
        cli("pack", prompt_file, "-o", output_file, "-s", session_file).run
      end
      verifier = OPA::Verifier.new(output_file)
      expect(verifier.session).to eq('{"messages":[]}')
    end

    it "creates a signed archive" do
      key, cert = generate_test_keypair
      key_file = File.join(tmpdir, "key.pem")
      cert_file = File.join(tmpdir, "cert.pem")
      File.write(key_file, key.to_pem)
      File.write(cert_file, cert.to_pem)

      capture_stdout do
        cli("pack", prompt_file, "-o", output_file, "-k", key_file, "-c", cert_file).run
      end
      verifier = OPA::Verifier.new(output_file)
      expect(verifier).to be_signed
      expect(verifier.verify!(certificate: cert)).to be true
    end

    it "returns 1 when prompt file is missing" do
      output = capture_stderr do
        expect(cli("pack", "/nonexistent/file.md").run).to eq(1)
      end
      expect(output).to include("not found")
    end

    it "returns 1 when no prompt file given" do
      output = capture_stderr do
        expect(cli("pack").run).to eq(1)
      end
      expect(output).to include("Usage")
    end

    it "returns 1 when --key given without --cert" do
      key, _cert = generate_test_keypair
      key_file = File.join(tmpdir, "key.pem")
      File.write(key_file, key.to_pem)

      output = capture_stderr do
        expect(cli("pack", prompt_file, "-k", key_file).run).to eq(1)
      end
      expect(output).to include("--key and --cert are required")
    end

    it "defaults output to prompt basename with .opa extension" do
      Dir.chdir(tmpdir) do
        capture_stdout { cli("pack", prompt_file).run }
        expect(File.exist?(File.join(Dir.pwd, "prompt.opa"))).to be true
      end
    end
  end

  describe "verify" do
    it "verifies a signed archive" do
      key, cert = generate_test_keypair
      archive = OPA::Archive.new
      archive.prompt = "test"
      archive.sign(key, cert)
      archive.write(output_file)

      cert_file = File.join(tmpdir, "cert.pem")
      File.write(cert_file, cert.to_pem)

      output = capture_stdout do
        expect(cli("verify", output_file, "-c", cert_file).run).to eq(0)
      end
      expect(output).to include("Signature valid")
    end

    it "returns 1 for unsigned archive" do
      archive = OPA::Archive.new
      archive.prompt = "test"
      archive.write(output_file)

      output = capture_stderr do
        expect(cli("verify", output_file).run).to eq(1)
      end
      expect(output).to include("not signed")
    end

    it "returns 1 when archive file is missing" do
      output = capture_stderr do
        expect(cli("verify", "/nonexistent.opa").run).to eq(1)
      end
      expect(output).to include("not found")
    end
  end

  describe "inspect" do
    it "displays archive metadata" do
      archive = OPA::Archive.new
      archive.manifest["Title"] = "Inspect Test"
      archive.prompt = "# Hello\nLine 2"
      archive.write(output_file)

      output = capture_stdout do
        expect(cli("inspect", output_file).run).to eq(0)
      end
      expect(output).to include("Archive: #{output_file}")
      expect(output).to include("Signed: no")
      expect(output).to include("Title: Inspect Test")
      expect(output).to include("# Hello")
    end

    it "shows signed status" do
      key, cert = generate_test_keypair
      archive = OPA::Archive.new
      archive.prompt = "test"
      archive.sign(key, cert)
      archive.write(output_file)

      output = capture_stdout do
        cli("inspect", output_file).run
      end
      expect(output).to include("Signed: yes")
    end

    it "lists entries for signed archives" do
      key, cert = generate_test_keypair
      archive = OPA::Archive.new
      archive.prompt = "test"
      archive.add_data("notes.txt", "hello")
      archive.sign(key, cert)
      archive.write(output_file)

      output = capture_stdout do
        cli("inspect", output_file).run
      end
      expect(output).to include("Entries:")
      expect(output).to include("prompt.md")
      expect(output).to include("data/notes.txt")
    end

    it "returns 1 when archive file is missing" do
      output = capture_stderr do
        expect(cli("inspect", "/nonexistent.opa").run).to eq(1)
      end
      expect(output).to include("not found")
    end
  end
end
