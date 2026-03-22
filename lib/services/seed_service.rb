require_relative '../services/netlify_blobs_service'

module SeedService
  attr_reader :data, :data_name

  def data_label
    @data_name
  end

  def initialize(store_name: nil)
    @blob_service = NetlifyBlobsService.new(
      site_id: ENV.fetch('NETLIFY_SITE_ID'),
      auth_token: ENV.fetch('NETLIFY_AUTH_TOKEN'),
      store_name: store_name
    )
  end

  def run
    puts "Seeding #{data.length} #{data_label} to Netlify Blobs..."

    data.each do |item|
      puts "  - #{item['name']} (#{item['id']})"
    end

    save
    puts "Done! #{data_label.capitalize} saved to Netlify."
  end

  def save
    data.each do |item|
      @blob_service.set_blob(item['id'], item)
    end
  end
end