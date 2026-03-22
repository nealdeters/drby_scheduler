require 'webmock/rspec'
require_relative '../../lib/services/seed_service'

RSpec.describe SeedService do
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
      include SeedService

      def initialize
        super
        @data = [{ 'id' => 'd1', 'name' => 'Test Item' }]
        @data_name = 'test-items'
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
    it 'outputs seeding message' do
      stub_request(:put, /#{base_url}\/.+/)
        .to_return(status: 200, body: '{}')

      expect { dummy_class.new.run }.to output(/Seeding 1 test-items/).to_stdout
    end

    it 'outputs item details' do
      stub_request(:put, /#{base_url}\/.+/)
        .to_return(status: 200, body: '{}')

      expect { dummy_class.new.run }.to output(/Test Item/).to_stdout
    end

    it 'outputs done message' do
      stub_request(:put, /#{base_url}\/.+/)
        .to_return(status: 200, body: '{}')

      expect { dummy_class.new.run }.to output(/Done! Test-items saved to Netlify/).to_stdout
    end
  end

  describe '#save' do
    it 'makes PUT request for each item with its ID as key' do
      stubbed_request = stub_request(:put, "#{base_url}/d1")
        .with(
          headers: { 'Authorization' => "Bearer #{auth_token}" },
          body: JSON.generate({ 'id' => 'd1', 'name' => 'Test Item' })
        )
        .to_return(status: 200, body: '{}')

      dummy_class.new.save
      expect(stubbed_request).to have_been_made
    end

    it 'raises error on API failure' do
      stub_request(:put, /#{base_url}\/.+/)
        .to_return(status: 500, body: 'Internal Server Error')

      expect { dummy_class.new.save }.to raise_error(/Netlify API error/)
    end
  end

  describe 'attr_readers' do
    it 'exposes data' do
      instance = dummy_class.new
      expect(instance.data).to eq([{ 'id' => 'd1', 'name' => 'Test Item' }])
    end

    it 'exposes data_name' do
      instance = dummy_class.new
      expect(instance.data_name).to eq('test-items')
    end

    it 'exposes base_url' do
      instance = dummy_class.new
      expect(instance.base_url).to eq(base_url)
    end

    it 'exposes data_label' do
      instance = dummy_class.new
      expect(instance.data_label).to eq('test-items')
    end
  end
end
