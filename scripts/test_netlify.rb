require 'dotenv/load'
require './lib/services/netlify_blobs_service'

site_id = ENV['NETLIFY_SITE_ID']
auth_token = ENV['NETLIFY_AUTH_TOKEN']

service = NetlifyBlobsService.new(site_id: site_id, auth_token: auth_token, store_name: 'production')

puts service.with_store('site:roster').list_blobs
# puts service.with_store('site:tracks').get_blob('t1')