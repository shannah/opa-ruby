# opa-ruby

A Ruby library and CLI for building, signing, and verifying [Open Prompt Archive (OPA)](https://github.com/shannah/opa-spec) files.

OPA archives are ZIP-based packages that bundle AI agent prompts with session history, data assets, and execution metadata into portable, distributable archives.

## Installation

Add to your Gemfile:

```ruby
gem "opa-ruby"
```

Or install directly:

```bash
gem install opa-ruby
```

**Zero external dependencies** — uses only Ruby stdlib (`zlib`, `openssl`).

## Library Usage

### Creating an archive

```ruby
require "opa"

archive = OPA::Archive.new
archive.manifest["Title"] = "My Task"
archive.manifest["Execution-Mode"] = "batch"
archive.prompt = "Summarize the attached data."
archive.add_data("report.csv", File.read("report.csv"))

archive.write("my_task.opa")
```

### Signing an archive

```ruby
key  = OpenSSL::PKey::RSA.new(File.read("key.pem"))
cert = OpenSSL::X509::Certificate.new(File.read("cert.pem"))

archive = OPA::Archive.new
archive.prompt = "Do the thing."
archive.sign(key, cert, algorithm: "SHA-256")
archive.write("signed.opa")
```

Supported digest algorithms: SHA-256, SHA-384, SHA-512. MD5 and SHA-1 are rejected per spec.

### Reading and verifying an archive

```ruby
verifier = OPA::Verifier.new("signed.opa")

verifier.signed?            # => true
verifier.prompt             # => "Do the thing."
verifier.manifest["Title"]  # => "My Task"
verifier.data_entries       # => { "data/report.csv" => "..." }

# Verify signature (raises OPA::SignatureError on failure)
cert = OpenSSL::X509::Certificate.new(File.read("cert.pem"))
verifier.verify!(certificate: cert)
```

## CLI Usage

The `opa` command provides three subcommands:

### pack

Create an OPA archive from a prompt file.

```bash
opa pack prompt.md                                  # basic archive
opa pack prompt.md -t "My Task" -o task.opa         # with title and output path
opa pack prompt.md -d data.csv -d config.json       # with data files
opa pack prompt.md -s session.json                  # with session history
opa pack prompt.md -k key.pem -c cert.pem           # signed archive
opa pack prompt.md -k key.pem -c cert.pem --algorithm SHA-512
```

### verify

Verify a signed archive's integrity.

```bash
opa verify archive.opa                    # verify using embedded certificate
opa verify archive.opa -c cert.pem       # verify against a specific certificate
```

### inspect

Display archive metadata and contents.

```bash
opa inspect archive.opa
```

## Core Classes

| Class | Purpose |
|---|---|
| `OPA::Archive` | Builds `.opa` ZIP archives with manifest, prompt, data, and session entries |
| `OPA::Verifier` | Reads archives, extracts entries, and verifies signatures |
| `OPA::Signer` | JAR-format signing (SIGNATURE.SF + PKCS#7 block) |
| `OPA::Manifest` | META-INF/MANIFEST.MF parser and generator |
| `OPA::CLI` | Command-line interface |

## Development

```bash
bundle install
rake spec
```

## License

MIT
