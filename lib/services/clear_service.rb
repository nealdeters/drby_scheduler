require_relative '../services/netlify_blobs_service'

module ClearService
  attr_reader :keys, :keys_name

  def keys_label
    @keys_name || 'data'
  end

  def initialize(store_name: nil)
    @blob_service = NetlifyBlobsService.new(
      site_id: ENV.fetch('NETLIFY_SITE_ID'),
      auth_token: ENV.fetch('NETLIFY_AUTH_TOKEN'),
      store_name: store_name
    )
  end

  def run
    puts "Clearing #{keys.length} #{keys_label} from Netlify Blobs..."

    keys.each do |key|
      print "  Deleting #{key}... "
      if @blob_service.delete_blob(key)
        puts "OK"
      else
        puts "Not found (skipping)"
      end
    end

    puts "Done! #{keys_label.capitalize} cleared."
  end

  def list_keys
    @blob_service.list_blobs.keys
  end

  def delete(key)
    @blob_service.delete_blob(key)
  end
end