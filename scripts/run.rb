#!/usr/bin/env ruby

require_relative '../lib/scheduler/orchestrator'

class DrbyRunner
  def initialize
    @ably_key = ENV.fetch('ABLY_API_KEY')
    @site_id = ENV.fetch('NETLIFY_SITE_ID')
    @auth_token = ENV.fetch('NETLIFY_AUTH_TOKEN')
  end

  def run
    puts "=" * 60
    puts "DRBY Race Orchestrator"
    puts "=" * 60
    puts "Netlify Site: #{@site_id[0..8]}..."
    puts "Ably Key: #{@ably_key[0..8]}..."
    puts "=" * 60

    orchestrator = RaceOrchestrator.new(
      ably_api_key: @ably_key,
      netlify_site_id: @site_id,
      netlify_auth_token: @auth_token
    )

    trap('INT') do
      puts "\nReceived SIGINT, shutting down..."
      orchestrator.stop
      exit 0
    end

    trap('TERM') do
      puts "\nReceived SIGTERM, shutting down..."
      orchestrator.stop
      exit 0
    end

    orchestrator.start
  end
end

DrbyRunner.new.run
