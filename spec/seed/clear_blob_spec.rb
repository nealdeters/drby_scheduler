require 'webmock/rspec'
require_relative '../../scripts/seed/clear_blob'

RSpec.describe ClearBlob do
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
    it 'deletes all data blobs from store' do
      stub_request(:get, base_url)
        .to_return(status: 200, body: JSON.generate({ 'r1' => '{}', 't1' => '{}' }))

      stub_request(:delete, /#{base_url}\/.+/)
        .to_return(status: 200)

      expect { ClearBlob.new.run }.to output(/Found 2 keys/).to_stdout
    end

    it 'handles empty store' do
      stub_request(:get, base_url)
        .to_return(status: 200, body: JSON.generate({}))

      expect { ClearBlob.new.run }.to output(/No blobs found/).to_stdout
    end

    it 'reports success for successful deletions' do
      stub_request(:get, base_url)
        .to_return(status: 200, body: JSON.generate({ 'r1' => '{}' }))

      stub_request(:delete, "#{base_url}/r1")
        .to_return(status: 200)

      expect { ClearBlob.new.run }.to output(/OK/).to_stdout
    end
  end

  describe 'ClearService behavior' do
    it 'uses list_keys to fetch all keys' do
      stub_request(:get, base_url)
        .to_return(status: 200, body: JSON.generate({ 'key1' => '{}' }))

      instance = ClearBlob.new
      expect(instance.send(:list_keys)).to eq(['key1'])
    end

    it 'exposes keys_name' do
      instance = ClearBlob.new
      expect(instance.keys_name).to eq('all data')
    end
  end
end
