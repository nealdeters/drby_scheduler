require 'webmock/rspec'
require_relative '../../scripts/seed/clear_data'

RSpec.describe ClearData do
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
    it 'deletes season-schedule' do
      stub_request(:delete, "#{base_url}/season-schedule").to_return(status: 200)
      stub_request(:delete, "#{base_url}/season-standings").to_return(status: 404)
      stub_request(:delete, "#{base_url}/completed-seasons").to_return(status: 404)
      stub_request(:delete, "#{base_url}/current-season-number").to_return(status: 404)

      expect { ClearData.new.run }.to output(/Deleting season-schedule/).to_stdout
    end

    it 'handles 404 as not found' do
      stub_request(:delete, /#{base_url}\/.+/).to_return(status: 404)

      expect { ClearData.new.run }.to output(/Not found \(skipping\)/).to_stdout
    end

    it 'reports success for successful deletions' do
      stub_request(:delete, /#{base_url}\/.+/).to_return(status: 200)

      expect { ClearData.new.run }.to output(/OK/).to_stdout
    end
  end

  describe 'ClearService behavior' do
    it 'exposes keys_name' do
      instance = ClearData.new
      expect(instance.keys_name).to eq('season data')
    end

    it 'uses KEYS constant as keys' do
      instance = ClearData.new
      expect(instance.keys).to eq(ClearData::KEYS)
    end
  end

  describe 'KEYS constant' do
    it 'does not include roster' do
      expect(ClearData::KEYS).not_to include('roster')
    end

    it 'does not include tracks' do
      expect(ClearData::KEYS).not_to include('tracks')
    end

    it 'includes season-related keys only' do
      expect(ClearData::KEYS).to include('season-schedule')
      expect(ClearData::KEYS).to include('season-standings')
      expect(ClearData::KEYS).to include('completed-seasons')
      expect(ClearData::KEYS).to include('current-season-number')
    end
  end
end
