#!/usr/bin/env ruby

require 'dotenv/load'
require_relative '../../lib/services/netlify_blobs_service'

class ClearBlob
  OLD_STORES = %w[site:racers site:tracks site:races].freeze

  def initialize
    @services = OLD_STORES.map do |store|
      svc = NetlifyBlobsService.new(
        site_id: ENV.fetch('NETLIFY_SITE_ID'),
        auth_token: ENV.fetch('NETLIFY_AUTH_TOKEN'),
        store_name: store
      )
      [store, svc]
    end.to_h
  end

  def run
    total_deleted = 0
    
    @services.each do |store_name, service|
      keys = service.list_blobs.keys
      
      if keys.empty?
        puts "#{store_name}: empty"
        next
      end

      puts "#{store_name}: Found #{keys.length} blobs, deleting..."
      
      keys.each do |key|
        print "  Deleting #{key}... "
        if service.delete_blob(key)
          puts "OK"
          total_deleted += 1
        else
          puts "Failed"
        end
      end
    end

    puts "Done! #{total_deleted} blobs cleared from old stores."
  end
end

if __FILE__ == $0
  ClearBlob.new.run
end
