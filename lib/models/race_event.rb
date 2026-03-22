class RaceEvent
  attr_reader :id, :start_time, :seed, :track, :racer_ids
  attr_accessor :completed, :results, :finish_times

  def initialize(id:, start_time:, seed:, track:, racer_ids:, completed: false)
    @id = id
    @start_time = start_time
    @seed = seed
    @track = track
    @racer_ids = racer_ids
    @completed = completed
    @results = nil
    @finish_times = nil
  end

  def self.from_hash(hash)
    track = hash['track'].is_a?(Hash) ? Track.from_hash(hash['track']) : hash['track']
    new(
      id: hash['id'],
      start_time: hash['startTime'],
      seed: hash['seed'],
      track: track,
      racer_ids: hash['racerIds'] || [],
      completed: hash['completed'] || false
    ).tap do |event|
      event.results = hash['results']
      event.finish_times = hash['finishTimes']
    end
  end

  def to_h
    {
      'id' => id,
      'startTime' => start_time,
      'seed' => seed,
      'track' => track.is_a?(Hash) ? track : track.to_h,
      'racerIds' => racer_ids,
      'completed' => completed,
      'results' => results,
      'finishTimes' => finish_times
    }.compact
  end
end
