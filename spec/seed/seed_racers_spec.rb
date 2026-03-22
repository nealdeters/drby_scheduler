require 'webmock/rspec'
require_relative '../../scripts/seed/seed_racers'

RSpec.describe SeedRacers do
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
    it 'saves all racers to Netlify Blobs' do
      SeedRacers::RACERS.each do |racer|
        stub_request(:put, "#{base_url}/#{racer['id']}")
          .with(headers: { 'Authorization' => "Bearer #{auth_token}" })
          .to_return(status: 200, body: '{}')
      end

      expect { SeedRacers.new.run }.to output(/Seeding 10 racers/).to_stdout
    end

    it 'uses correct JSON structure for racers' do
      racer = SeedRacers::RACERS.first
      stub_request(:put, "#{base_url}/#{racer['id']}")
        .with(
          headers: { 'Authorization' => "Bearer #{auth_token}" },
          body: JSON.generate(racer)
        )
        .to_return(status: 200, body: '{}')

      SeedRacers::RACERS.drop(1).each do |r|
        stub_request(:put, "#{base_url}/#{r['id']}").to_return(status: 200)
      end

      expect { SeedRacers.new.run }.to output.to_stdout
    end

    it 'raises error on API failure' do
      stub_request(:put, /#{base_url}\/.+/).to_return(status: 500, body: 'Internal Server Error')

      expect { SeedRacers.new.run }.to raise_error(/Netlify API error/)
    end
  end

  describe 'RACERS constant' do
    it 'contains 10 racers' do
      expect(SeedRacers::RACERS.length).to eq(10)
    end

    it 'each racer has required fields' do
      SeedRacers::RACERS.each do |racer|
        expect(racer).to include('id')
        expect(racer).to include('name')
        expect(racer).to include('color')
        expect(racer).to include('baseSpeed')
        expect(racer).to include('health')
        expect(racer).to include('strategy')
      end
    end

    it 'all racers have unique ids' do
      ids = SeedRacers::RACERS.map { |r| r['id'] }
      expect(ids.uniq.length).to eq(10)
    end

    it 'all racers start with full health' do
      SeedRacers::RACERS.each do |racer|
        expect(racer['health']).to eq(100)
      end
    end
  end

  describe 'SeedService behavior' do
    it 'uses roster as data_name' do
      seeder = SeedRacers.new
      expect(seeder.data_name).to eq('roster')
    end

    it 'displays racers as data_label' do
      seeder = SeedRacers.new
      expect(seeder.data_label).to eq('racers')
    end

    it 'uses RACERS as data' do
      seeder = SeedRacers.new
      expect(seeder.data).to eq(SeedRacers::RACERS)
    end
  end
end
