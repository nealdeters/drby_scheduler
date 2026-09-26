#!/usr/bin/env ruby

require_relative '../lib/scheduler/orchestrator'

class DrbyRunner
  def initialize
    @transport = ENV.fetch('DRBY_REALTIME_TRANSPORT', 'house_bus')
    @ably_key = ENV['ABLY_API_KEY']
    @house_bus_url = ENV.fetch('CENTRIFUGO_API_URL', ENV.fetch('CENTRIFUGO_URL', 'http://host.docker.internal:8002'))
    @house_bus_api_key = ENV['CENTRIFUGO_HTTP_API_KEY'] || ENV['CENTRIFUGO_API_KEY']
    @site_id = ENV.fetch('NETLIFY_SITE_ID')
    @auth_token = ENV.fetch('NETLIFY_AUTH_TOKEN')
  end

  def run
    puts "=" * 60
    puts "DRBY Race Orchestrator"
    puts "=" * 60
    puts "Netlify Site: #{@site_id[0..8]}..."
    puts "Realtime transport: #{@transport}"
    puts "=" * 60

    orchestrator = RaceOrchestrator.new(
      ably_api_key: @ably_key,
      house_bus_url: @house_bus_url,
      house_bus_api_key: @house_bus_api_key,
      realtime_transport: @transport,
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
