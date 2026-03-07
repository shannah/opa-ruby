# frozen_string_literal: true

require "opa"
require "openssl"
require "stringio"
require "tmpdir"

module TestHelpers
  def generate_test_keypair(algorithm: :rsa)
    case algorithm
    when :rsa
      key = OpenSSL::PKey::RSA.generate(2048)
    when :ec
      key = OpenSSL::PKey::EC.generate("prime256v1")
    else
      raise "Unsupported algorithm: #{algorithm}"
    end

    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=OPA Test Signer")
    cert.issuer = cert.subject
    cert.public_key = key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.add_extension(ef.create_extension("basicConstraints", "CA:FALSE", true))
    cert.add_extension(ef.create_extension("subjectKeyIdentifier", "hash"))

    cert.sign(key, OpenSSL::Digest.new("SHA256"))

    [key, cert]
  end
end

RSpec.configure do |config|
  config.include TestHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
