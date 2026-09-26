require_relative '../../lib/services/house_bus_service'
require 'webmock/rspec'

RSpec.describe HouseBusService do
  let(:publisher) { described_class.new('http://bus.test:8002', 'bus-secret') }
  let(:racer) do
    Struct.new(:id) do
      def to_h
        { 'id' => id, 'lane' => 1 }
      end
      def total_distance
        0
      end
    end.new('r1')
  end

  it 'publishes a race update to a race-scoped house channel' do
    stub = stub_request(:post, 'http://bus.test:8002/api/publish')
      .with(
        headers: { 'X-API-Key' => 'bus-secret' },
        body: hash_including('channel' => 'house:race:s1-race-1', 'data' => hash_including('type' => 'started'))
      )
      .to_return(status: 200, body: '{}')

    publisher.publish_race_started('s1-race-1', [racer], nil)

    expect(stub).to have_been_requested
  end
end
