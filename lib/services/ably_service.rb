require 'ably'

class AblyService
  RACE_CHANNEL_PREFIX = 'race:'.freeze

  def initialize(api_key)
    @api_key = api_key
    @rest_client = Ably::Rest.new(api_key)
  end

  def publish_race_started(race_id, racers, track)
    channel = @rest_client.channels.get("#{RACE_CHANNEL_PREFIX}#{race_id}")
    channel.publish('race-update', {
      'type' => 'started',
      'raceId' => race_id,
      'timestamp' => Time.now.to_i * 1000,
      'racers' => racers.map(&:to_h),
      'progressMap' => racers.each_with_object({}) { |r, h| h[r.id] = 0 },
      'tickCount' => 0
    })
    puts "[Ably] Published started for race #{race_id}"
  end

  def publish_race_progress(race_id, racers, tick_count)
    channel = @rest_client.channels.get("#{RACE_CHANNEL_PREFIX}#{race_id}")
    progress_map = racers.each_with_object({}) do |racer, map|
      map[racer.id] = [racer.total_distance.fdiv(racers.first.total_distance > 0 ? racers.first.total_distance : 1), 1].min
    end

    channel.publish('race-update', {
      'type' => 'progress',
      'raceId' => race_id,
      'timestamp' => Time.now.to_i * 1000,
      'racers' => racers.map(&:to_h),
      'progressMap' => progress_map,
      'tickCount' => tick_count
    })
  end

  def publish_race_finished(race_id, results, dnf_racers, tick_count)
    channel = @rest_client.channels.get("#{RACE_CHANNEL_PREFIX}#{race_id}")
    channel.publish('race-update', {
      'type' => 'finished',
      'raceId' => race_id,
      'timestamp' => Time.now.to_i * 1000,
      'results' => results.map(&:to_h),
      'dnfRacers' => dnf_racers.map(&:to_h),
      'tickCount' => tick_count
    })
    puts "[Ably] Published finished for race #{race_id}"
  end
end
