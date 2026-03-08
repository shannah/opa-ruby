#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Sample: Generate an OPA archive that bundles a pirate-themed AI news
# summarizer prompt together with a live Google News RSS feed snapshot.
#
# Usage:
#   ruby samples/pirate_news.rb
#
# This produces pirate_news.opa in the current directory.
#

require "net/http"
require "uri"
require "openssl"
require_relative "../lib/opa"

RSS_URL = "https://news.google.com/rss/search?q=artificial+intelligence&hl=en-US&gl=US&ceid=US:en"

# -- Fetch the RSS feed -------------------------------------------------------

puts "Fetching AI news RSS feed..."
uri = URI(RSS_URL)
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_PEER
# Some systems have CRL checking issues; fall back to relaxed verification
begin
  response = http.request(Net::HTTP::Get.new(uri)).body
rescue OpenSSL::SSL::SSLError => e
  warn "  SSL strict mode failed (#{e.message.split("state=").last}), retrying without CRL check..."
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  response = http.request(Net::HTTP::Get.new(uri)).body
end
puts "  Fetched #{response.bytesize} bytes."

# -- Build the prompt ----------------------------------------------------------

prompt = <<~PROMPT
  You are a salty, wise pirate captain who also happens to be a keen observer
  of the technology world.  You have been given an RSS feed of the latest
  headlines about Artificial Intelligence (see `data/ai_news.xml`).

  Your tasks:

  1. **Summarize** every headline in the feed in the voice of a pirate.
     Use pirate slang, nautical metaphors, and plenty of "Arrr!"s.
     Keep each summary to 1–2 sentences.

  2. **Pick one article** that would be of most interest to someone who is
     passionate about AI — explain *why* it matters, still in pirate voice.

  3. **Output** the entire report as a single, self-contained HTML page:
     - Use semantic HTML5 (`<article>`, `<section>`, `<header>`, etc.).
     - Include a `<style>` block with a pirate-themed dark colour scheme
       (think weathered parchment, deep ocean blues, gold accents).
     - The chosen "top pick" article should be visually highlighted.
     - Include the original article links from the RSS feed as clickable
       `<a>` tags so the reader can navigate to the source.

  Output only the HTML — no commentary, no markdown fences.
PROMPT

# -- Assemble the archive -----------------------------------------------------

archive = OPA::Archive.new
archive.manifest["Title"]          = "Pirate AI News Summarizer"
archive.manifest["Created-By"]     = "opa-ruby/#{OPA::VERSION} (sample)"
archive.manifest["Prompt-File"]    = "prompt.md"
archive.manifest["Execution-Mode"] = "batch"
archive.manifest["Agent-Hint"]     = "claude-sonnet-4-6"

archive.prompt = prompt
archive.add_data("ai_news.xml", response)

output_path = "pirate_news.opa"
archive.write(output_path)

puts "Created #{output_path}"
puts ""
puts "Archive contents:"
puts "  prompt.md        – pirate summarizer prompt"
puts "  data/ai_news.xml – live RSS snapshot (#{response.lines.size} lines)"
puts ""
puts "To inspect:  ruby -Ilib bin/opa inspect #{output_path}"
