# frozen_string_literal: true

require_relative "lib/opa/version"

Gem::Specification.new do |spec|
  spec.name = "opa-ruby"
  spec.version = OPA::VERSION
  spec.authors = ["OPA Ruby Contributors"]
  spec.summary = "A Ruby library for generating OPA (Open Policy Agent) Rego policy files"
  spec.description = "Provides a DSL for programmatically building and generating OPA Rego policies from Ruby."
  spec.homepage = "https://github.com/shannah/opa-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
