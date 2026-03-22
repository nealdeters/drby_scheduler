require 'webmock/rspec'
require_relative '../../scripts/seed/seed_tracks'

RSpec.describe SeedTracks do
  let(:site_id) { 'test-site-123' }
  let(:auth_token) { 'test-auth-token' }
  let(:base_url) { "https://api.netlify.com/api/v1/sites/#{site_id}/blobs" }

  before do
    ENV['NETLIFY_SITE_ID'] = site_id
    ENV['NETLIFY_AUTH_TOKEN'] = auth_token
  end

  after do
    ENV.delete('NETLIFY_SITE_ID')
    ENV.delete('NETLIFY_AUTH_TOKEN')
  end

  describe '#run' do
    it 'saves all tracks to Netlify Blobs' do
      SeedTracks::TRACKS.each do |track|
        stub_request(:put, "#{base_url}/#{track['id']}")
          .with(headers: { 'Authorization' => "Bearer #{auth_token}" })
          .to_return(status: 200, body: '{}')
      end

      expect { SeedTracks.new.run }.to output(/Seeding 8 tracks/).to_stdout
    end

    it 'raises error on API failure' do
      stub_request(:put, /#{base_url}\/.+/).to_return(status: 500, body: 'Internal Server Error')

      expect { SeedTracks.new.run }.to raise_error(/Netlify API error/)
    end
  end

  describe 'TRACKS constant' do
    it 'contains 8 tracks' do
      expect(SeedTracks::TRACKS.length).to eq(8)
    end

    it 'each track has required fields' do
      SeedTracks::TRACKS.each do |track|
        expect(track).to include('id')
        expect(track).to include('name')
        expect(track).to include('surface')
        expect(track).to include('length')
        expect(track).to include('laps')
      end
    end

    it 'all tracks have unique ids' do
      ids = SeedTracks::TRACKS.map { |t| t['id'] }
      expect(ids.uniq.length).to eq(8)
    end

    it 'has a mix of surfaces' do
      surfaces = SeedTracks::TRACKS.map { |t| t['surface'] }
      expect(surfaces).to include('dirt')
      expect(surfaces).to include('asphalt')
      expect(surfaces).to include('grass')
    end

    it 'all tracks have positive length and laps' do
      SeedTracks::TRACKS.each do |track|
        expect(track['length']).to be > 0
        expect(track['laps']).to be > 0
      end
    end
  end

  describe 'SeedService behavior' do
    it 'uses tracks as data_name' do
      seeder = SeedTracks.new
      expect(seeder.data_name).to eq('tracks')
    end

    it 'uses TRACKS as data' do
      seeder = SeedTracks.new
      expect(seeder.data).to eq(SeedTracks::TRACKS)
    end
  end
end
