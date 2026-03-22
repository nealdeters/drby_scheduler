require 'httparty'
require 'net/http'
require 'uri'
require 'erb'
require 'json'

class NetlifyBlobsService
  STORE_NAME = 'races'.freeze
  SCHEDULE_KEY = 'season-schedule'.freeze
  STANDINGS_KEY = 'season-standings'.freeze
  ROSTER_KEY = 'roster'.freeze
  COMPLETED_SEASONS_KEY = 'completed-seasons'.freeze
  SEASON_NUMBER_KEY = 'current-season-number'.freeze
  TRACKS_KEY = 'tracks'.freeze
  RACERS_KEY = 'racers'.freeze

  def initialize(site_id:, auth_token:, store_name: nil)
    @site_id = site_id
    @auth_token = auth_token
    @store_name = store_name
    
    if store_name
      @base_url = "https://app.netlify.com/access-control/bb-api/api/v1/blobs/#{@site_id}/#{@store_name}"
      @list_url = "https://app.netlify.com/access-control/bb-api/api/v1/blobs/#{@site_id}/#{@store_name}?directories=true"
    else
      @base_url = "https://api.netlify.com/api/v1/sites/#{@site_id}/blobs"
      @list_url = @base_url
    end
  end

  def with_store(store_name)
    self.class.new(site_id: @site_id, auth_token: @auth_token, store_name: store_name)
  end

  def get_schedule
    get(SCHEDULE_KEY)
  end

  def save_schedule(schedule)
    set(SCHEDULE_KEY, JSON.generate(schedule))
  end

  def get_standings
    get(STANDINGS_KEY) || {}
  end

  def save_standings(standings)
    set(STANDINGS_KEY, JSON.generate(standings))
  end

  def get_roster
    get(ROSTER_KEY) || []
  end

  def save_roster(roster)
    set(ROSTER_KEY, JSON.generate(roster))
  end

  def get_completed_seasons
    get(COMPLETED_SEASONS_KEY) || []
  end

  def save_completed_seasons(seasons)
    set(COMPLETED_SEASONS_KEY, JSON.generate(seasons))
  end

  def get_season_number
    data = get(SEASON_NUMBER_KEY)
    return 1 unless data

    parsed = JSON.parse(data)
    parsed.is_a?(Integer) ? parsed : (parsed['number'] || 1)
  end

  def save_season_number(number)
    set(SEASON_NUMBER_KEY, JSON.generate(number))
  end

  def get_tracks
    data = get(TRACKS_KEY)
    data.is_a?(Array) ? data : []
  end

  def save_tracks(tracks)
    set(TRACKS_KEY, JSON.generate(tracks))
  end

  def get_racers
    data = get(RACERS_KEY)
    data.is_a?(Array) ? data : []
  end

  def save_racers(racers)
    set(RACERS_KEY, JSON.generate(racers))
  end

  def get_blob(key)
    get(key)
  end

  def set_blob(key, value)
    set(key, JSON.generate(value))
  end

  def delete_blob(key)
    delete(key)
  end

def list_blobs
    response = HTTParty.get(
      @list_url,
      headers: {
        'Authorization' => "Bearer #{@auth_token}",
        'Content-Type' => 'application/json'
      }
    )

    return [] unless response.success?

    parsed = JSON.parse(response.body)
    if parsed.is_a?(Hash) && parsed['blobs']
      parsed['blobs'].map { |b| [b['key'], b] }.to_h
    else
      {}
    end
  end

  private

  def get(key)
    url = @store_name ? "#{@base_url}/#{key}" : "#{@base_url}/#{key}"
    response = HTTParty.get(
      url,
      headers: {
        'Authorization' => "Bearer #{@auth_token}",
        'Content-Type' => 'application/json'
      }
    )

    return nil if response.code == 404

    raise "Netlify API error: #{response.code}" unless response.success?

    body = response.body
    return nil if body.nil? || body.empty?

    parsed = JSON.parse(body)
    
    if parsed.is_a?(Hash) && parsed['url']
      fetch_from_url(parsed['url'])
    else
      parsed
    end
  end

  def fetch_from_url(url)
    s3_uri = URI.parse(url)
    http = Net::HTTP.new(s3_uri.host, s3_uri.port)
    http.use_ssl = true
    req = Net::HTTP::Get.new(s3_uri)
    response = http.request(req)
    return nil if response.code == '404'
    raise "Failed to fetch blob content: #{response.code}" unless response.code == '200'

    content = response.body
    return nil if content.nil? || content.empty?

    JSON.parse(content)
  rescue JSON::ParserError
    content
  end

  def set(key, value)
    response = HTTParty.put(
      "#{@base_url}/#{key}",
      headers: {
        'Authorization' => "Bearer #{@auth_token}",
        'Content-Type' => 'application/json'
      },
      body: value
    )

    raise "Netlify API error: #{response.code}: #{response.body}" unless response.success?

    body = response.body
    if body && !body.empty?
      parsed = JSON.parse(body)
      if parsed.is_a?(Hash) && parsed['url']
        upload_to_s3(parsed['url'], value)
        return true
      end
    end
    true
  end

  def upload_to_s3(s3_url, content)
    uri = URI.parse(s3_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Put.new(uri)
    req['Content-Type'] = 'application/json'
    req.body = content

    response = http.request(req)
    raise "S3 upload failed: #{response.code}" unless response.code == '200'
    true
  end

  def delete(key)
    response = HTTParty.delete(
      "#{@base_url}/#{key}",
      headers: {
        'Authorization' => "Bearer #{@auth_token}"
      }
    )

    return false unless response.success?

    body = response.body
    if body && !body.empty?
      parsed = JSON.parse(body)
      if parsed.is_a?(Hash) && parsed['url']
        delete_from_s3(parsed['url'])
        return true
      end
    end
    true
  end

  def delete_from_s3(s3_url)
    uri = URI.parse(s3_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Delete.new(uri)
    response = http.request(req)
    raise "S3 delete failed: #{response.code}" unless ['200', '204'].include?(response.code)
    true
  end

  def JSON
    ::JSON
  end
end
