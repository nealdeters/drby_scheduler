require_relative 'services/ably_service'
require_relative 'services/netlify_blobs_service'
require_relative 'services/seed_service'
require_relative 'services/clear_service'

module Services
  AblyService = ::AblyService
  NetlifyBlobsService = ::NetlifyBlobsService
  SeedService = ::SeedService
  ClearService = ::ClearService
end
