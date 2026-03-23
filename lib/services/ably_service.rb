require 'ably'

class AblyService
  RACE_CHANNEL_PREFIX = 'race:'.freeze

  def initialize(api_key)
    @api_key = api_key
    @rest_client = Ably::Rest.new(api_key)
  end

  def publish_race_started(race_id, racers, track)
    channel = @rest_client.channels.get("#{RACE_CHANNEL_PREFIX}#{race_id}")
    begin
      channel.publish('race-update', {
        'type' => 'started',
        'raceId' => race_id,
        'timestamp' => Time.now.to_i * 1000,
        'racers' => racers.map(&:to_h),
        'progressMap' => racers.each_with_object({}) { |r, h| h[r.id] = 0 },
        'tickCount' => 0
      })
      puts "[Ably] Published started for race #{race_id}"
    rescue => e
      puts "[Ably] Error publishing started for race #{race_id}: #{e.message}"
    end
  end

  def publish_race_progress(race_id, racers, tick_count, total_distance = nil)
    channel = @rest_client.channels.get("#{RACE_CHANNEL_PREFIX}#{race_id}")
    
    progress_denominator = if total_distance && total_distance > 0
      total_distance
    elsif racers.any?(&:total_distance)
      racers.map(&:total_distance).max || 1
    else
      1
    end
    
    progress_map = racers.each_with_object({}) do |racer, map|
      map[racer.id] = [racer.total_distance.fdiv(progress_denominator), 1].min
    end

    begin
      channel.publish('race-update', {
        'type' => 'progress',
        'raceId' => race_id,
        'timestamp' => Time.now.to_i * 1000,
        'racers' => racers.map(&:to_h),
        'progressMap' => progress_map,
        'tickCount' => tick_count
      })
    rescue => e
      puts "[Ably] Error publishing progress for race #{race_id}: #{e.message}"
    end
  end

  def publish_race_finished(race_id, results, dnf_racers, tick_count)
    channel = @rest_client.channels.get("#{RACE_CHANNEL_PREFIX}#{race_id}")
    begin
      channel.publish('race-update', {
        'type' => 'finished',
        'raceId' => race_id,
        'timestamp' => Time.now.to_i * 1000,
        'results' => results.map(&:to_h),
        'dnfRacers' => dnf_racers.map(&:to_h),
        'tickCount' => tick_count
      })
      puts "[Ably] Published finished for race #{race_id}"
    rescue => e
      puts "[Ably] Error publishing finished for race #{race_id}: #{e.message}"
    end
  end
end
