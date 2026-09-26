require_relative 'house_bus_service'
require_relative 'ably_service'

# One simulator-facing publisher with an explicit rollback switch.
# DRBY_REALTIME_TRANSPORT=ably restores the previous provider without code changes.
class RealtimeService
  def initialize(transport:, house_bus_url: nil, house_bus_api_key: nil, ably_api_key: nil)
    @publisher = case transport.to_s
                 when 'ably'
                   AblyService.new(ably_api_key || raise(ArgumentError, 'ABLY_API_KEY is required for Ably rollback'))
                 when 'house_bus', 'centrifugo', ''
                   HouseBusService.new(house_bus_url, house_bus_api_key)
                 else
                   raise ArgumentError, "Unknown realtime transport: #{transport}"
                 end
  end

  def publish_race_started(...) = @publisher.publish_race_started(...)
  def publish_race_progress(...) = @publisher.publish_race_progress(...)
  def publish_race_finished(...) = @publisher.publish_race_finished(...)
end
