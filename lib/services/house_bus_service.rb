require 'json'
require 'net/http'
require 'uri'

# Server-side publisher for the local Centrifugo house bus.
# The API key never leaves the scheduler process; browsers receive only a
# short-lived subscribe token from the frontend's token endpoint.
class HouseBusService
  RACE_CHANNEL_PREFIX = 'house:race:'.freeze

  def initialize(api_url, api_key, timeout_seconds: 2)
    @api_url = api_url.to_s.sub(%r{/+$}, '')
    @api_key = api_key.to_s
    @timeout_seconds = timeout_seconds
  end

  def publish_race_started(race_id, racers, track, elapsed = 0)
    publish(race_id, 'started', {
      'raceId' => race_id,
      'timestamp' => now_ms,
      'elapsed' => elapsed,
      'racers' => racers.map(&:to_h),
      'progressMap' => racers.each_with_object({}) { |r, h| h[r.id] = 0 },
      'tickCount' => 0,
      'tickIncrement' => 1
    })
  end

  def publish_race_progress(race_id, racers, tick_count, total_distance = nil, elapsed = 0)
    denominator = if total_distance && total_distance > 0
      total_distance
    elsif racers.any?(&:total_distance)
      racers.map(&:total_distance).max || 1
    else
      1
    end

    progress_map = racers.each_with_object({}) do |racer, map|
      raw = racer.total_distance.to_f / denominator
      map[racer.id] = [[raw, 0].max, 1].min
    end

    publish(race_id, 'progress', {
      'raceId' => race_id,
      'timestamp' => now_ms,
      'elapsed' => elapsed,
      'racers' => racers.map(&:to_h),
      'progressMap' => progress_map,
      'tickCount' => tick_count,
      'tickIncrement' => 1
    })
  end

  def publish_race_finished(race_id, results, dnf_racers, tick_count, elapsed = 0)
    publish(race_id, 'finished', {
      'raceId' => race_id,
      'timestamp' => now_ms,
      'elapsed' => elapsed,
      'results' => results.map(&:to_h),
      'dnfRacers' => dnf_racers.map(&:to_h),
      'tickCount' => tick_count,
      'tickIncrement' => 1
    })
  end

  private

  def publish(race_id, type, data)
    return if @api_url.empty? || @api_key.empty?

    body = JSON.generate({ 'channel' => "#{RACE_CHANNEL_PREFIX}#{race_id}", 'data' => data.merge('type' => type) })
    uri = URI.parse("#{@api_url}/api/publish")
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['X-API-Key'] = @api_key
    request.body = body

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: @timeout_seconds, read_timeout: @timeout_seconds) do |http|
      http.request(request)
    end
    raise "HTTP #{response.code}: #{response.body.to_s[0, 240]}" unless response.is_a?(Net::HTTPSuccess)
  rescue => e
    puts "[HouseBus] Error publishing #{type} for race #{race_id}: #{e.message}"
  end

  def now_ms
    Time.now.to_i * 1000
  end
end
