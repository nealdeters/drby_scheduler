require 'webmock/rspec'
require_relative '../../lib/services/clear_service'

RSpec.describe ClearService do
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

  let(:dummy_class) do
    Class.new do
      include ClearService

      def initialize
        super
        @keys = ['test-key-1', 'test-key-2']
        @keys_name = 'test data'
      end
    end
  end

  describe '#initialize' do
    it 'sets up base_url from environment variables' do
      instance = dummy_class.new
      expect(instance.base_url).to eq(base_url)
    end
  end

  describe '#run' do
    it 'outputs clearing message' do
      stub_request(:delete, /#{base_url}\/.+/).to_return(status: 200)

      expect { dummy_class.new.run }.to output(/Clearing 2 test data/).to_stdout
    end

    it 'outputs success for successful deletions' do
      stub_request(:delete, /#{base_url}\/.+/).to_return(status: 200)

      expect { dummy_class.new.run }.to output(/OK/).to_stdout
    end

    it 'outputs not found for 404 responses' do
      stub_request(:delete, /#{base_url}\/.+/).to_return(status: 404)

      expect { dummy_class.new.run }.to output(/Not found \(skipping\)/).to_stdout
    end
  end

  describe '#delete' do
    it 'makes DELETE request to correct endpoint' do
      stubbed_request = stub_request(:delete, "#{base_url}/test-key-1")
        .with(headers: { 'Authorization' => "Bearer #{auth_token}" })
        .to_return(status: 200)

      dummy_class.new.delete('test-key-1')
      expect(stubbed_request).to have_been_made
    end

    it 'URL encodes special characters' do
      stubbed_request = stub_request(:delete, /#{base_url}\/.+/)
        .to_return(status: 200)

      dummy_class.new.delete('key with spaces')
      expect(stubbed_request).to have_been_made
    end
  end

  describe '#list_keys' do
    it 'makes GET request to base_url' do
      stub_request(:get, base_url)
        .with(headers: { 'Authorization' => "Bearer #{auth_token}" })
        .to_return(status: 200, body: JSON.generate({ 'key1' => '{}', 'key2' => '{}' }))

      expect(dummy_class.new.list_keys).to eq(%w[key1 key2])
    end

    it 'returns empty array on failure' do
      stub_request(:get, base_url).to_return(status: 500)

      expect(dummy_class.new.list_keys).to eq([])
    end
  end

  describe 'attr_readers' do
    it 'exposes keys' do
      instance = dummy_class.new
      expect(instance.keys).to eq(['test-key-1', 'test-key-2'])
    end

    it 'exposes keys_name' do
      instance = dummy_class.new
      expect(instance.keys_name).to eq('test data')
    end

    it 'exposes base_url' do
      instance = dummy_class.new
      expect(instance.base_url).to eq(base_url)
    end
  end

  describe '#keys_label' do
    it 'defaults to data when keys_name not set' do
      klass = Class.new do
        include ClearService
      end
      instance = klass.new
      expect(instance.keys_label).to eq('data')
    end

    it 'uses keys_name when set' do
      instance = dummy_class.new
      expect(instance.keys_label).to eq('test data')
    end
  end
end
