require_relative '../models'

class RaceSimulator
  UPDATE_INTERVAL_MS = 10
  MAX_DURATION_MS = 180_000

  STRATEGY_DECAY = {
    'aggressive' => 0.025,
    'balanced' => 0.012,
    'conservative' => 0.006
  }.freeze

  STRATEGY_VARIANCE = {
    'aggressive' => 0.15,
    'balanced' => 0.08,
    'conservative' => 0.04
  }.freeze

  attr_reader :race_id, :racers, :track, :total_distance, :tick_count, :is_finished

  def initialize(race_id:, track:, racers:)
    @race_id = race_id
    @track = track
    @total_distance = track.length * track.laps
    @tick_count = 0
    @is_finished = false
    @start_time = Time.now.to_i * 1000
    @last_published_tick = -1

    @racers = initialize_racers(racers)
    @dnf_racers = []
  end

  def run(ably_service:, on_progress: nil, on_finish: nil)
    puts "[Simulator] Starting race #{@race_id} with #{@racers.length} racers"

    ably_service.publish_race_started(@race_id, @racers, @track, 0) if ably_service

    race_start = Time.now.to_i * 1000

    while !@is_finished && (Time.now.to_i * 1000 - race_start) < MAX_DURATION_MS
      elapsed = Time.now.to_i * 1000 - race_start
      tick(elapsed)
      @tick_count += 1

      if @tick_count % 10 == 0
        ably_service.publish_race_progress(@race_id, @racers, @tick_count, @total_distance, elapsed) if ably_service
        on_progress&.call(@racers, @tick_count)
      end

      sleep(UPDATE_INTERVAL_MS / 1000.0)
    end

    elapsed = Time.now.to_i * 1000 - race_start

    if @is_finished
      puts "[Simulator] Race #{@race_id} finished naturally at tick #{@tick_count}, #{elapsed}ms"
    else
      puts "[Simulator] Race #{@race_id} reached max duration at tick #{@tick_count}, forcing finish"
    end

    results = @racers.select(&:finished?).sort_by { |r| r.finish_time || Float::INFINITY }
    non_finished = @racers.reject(&:finished?)
    non_finished.each_with_index do |racer, idx|
      racer.status = 'dnf'
      racer.position = results.length + idx + 1
    end
    all_results = results + non_finished

    dnf_with_positions = non_finished.map.with_index(results.length + 1) do |racer, idx|
      Racer.from_hash(racer.to_h.merge('position' => idx))
    end

    ably_service.publish_race_finished(@race_id, results, dnf_with_positions, @tick_count, elapsed) if ably_service
    on_finish&.call(all_results)

    @is_finished = true
    @is_finished
  end

  def get_results
    finished = @racers.select(&:finished?).sort_by { |r| r.finish_time || Float::INFINITY }
    dnf = @dnf_racers.map.with_index(finished.length + 1) { |r, i| r }
    finish_times = finished.each_with_object({}) { |r, h| h[r.id] = r.finish_time if r.finish_time }

    {
      results: finished + dnf,
      finish_times: finish_times
    }
  end

  def needs_continuation?
    !@is_finished && @tick_count > 0
  end

  private

  def initialize_racers(racers_data)
    racers = racers_data.map { |r| Racer.from_hash(r) }
    active = []
    dnf = []

    racers.each_with_index do |racer, idx|
      if racer.can_race?
        racer.lane = idx + 1
        racer.position = idx + 1
        racer.status = 'active'
        active << racer
      else
        racer.status = 'dnf'
        racer.lane = idx + 1
        racer.position = 0
        dnf << racer
      end
    end

    @dnf_racers = dnf
    puts "[Simulator] Race #{@race_id}: #{dnf.length} DNF (health <= 60), #{active.length} racing"

    active
  end

  def tick(elapsed)
    any_active_unfinished = false

    update_positions if @tick_count % 250 == 0

    @racers.each do |racer|
      next unless racer.active?

      process_racer_tick(racer, elapsed)
      any_active_unfinished = true unless racer.finished?
    end

    @is_finished = !any_active_unfinished
  end

  def update_positions
    sorted = @racers
              .select(&:active?)
              .sort_by { |r| -r.total_distance }

    sorted.each_with_index do |racer, idx|
      racer.position = idx + 1
    end
  end

  def process_racer_tick(racer, elapsed)
    race_progress = racer.total_distance.to_f / @total_distance

    decay_rate = STRATEGY_DECAY[racer.strategy] || STRATEGY_DECAY['balanced']
    endurance_mult = [0.2, (100 - racer.endurance) / 100.0].max
    racer.health = [0, racer.health - decay_rate * endurance_mult].max

    base_speed = racer.base_speed * (UPDATE_INTERVAL_MS / 1000.0)

    acceleration_boost = 0
    if race_progress < 0.1
      accel_factor = racer.acceleration / 100.0
      acceleration_boost = 0.3 * accel_factor * (1 - race_progress * 10)
    end

    track_penalty = calculate_track_penalty(racer)
    fatigue_penalty = [0, (100 - racer.health) / 200.0].max

    base_variance = STRATEGY_VARIANCE[racer.strategy] || STRATEGY_VARIANCE['balanced']
    consistency_mult = [0.3, (100 - racer.consistency) / 100.0].max
    variance_cap = base_variance * consistency_mult
    speed_adjustment = (rand - 0.5) * 2 * variance_cap

    final_speed = base_speed * (1 + acceleration_boost + speed_adjustment - fatigue_penalty - track_penalty)
    racer.current_speed = final_speed

    previous_laps = racer.laps
    racer.total_distance += final_speed
    current_lap_distance = racer.total_distance % @track.length
    racer.laps = (racer.total_distance / @track.length).to_i

    if racer.laps > previous_laps
      racer.progress = 0
      check_injury(racer)
    else
      racer.progress = current_lap_distance.to_f / @track.length
    end

    if racer.total_distance >= @total_distance
      racer.status = 'finished'
      racer.finish_time = elapsed
      racer.total_distance = @total_distance
      racer.laps = @track.laps
      racer.progress = 1
    end
  end

  def calculate_track_penalty(racer)
    case
    when racer.track_preference == 'asphalt' && @track.surface == 'dirt' then 0.25
    when racer.track_preference == 'dirt' && @track.surface == 'asphalt' then 0.25
    when racer.track_preference == 'grass' then -0.1
    else 0
    end
  end

  def check_injury(racer)
    injury_chance = 0.01 * (1 + ((100 - racer.health) / 100.0)**2 * 4)
    if rand < injury_chance && racer.health < 85
      racer.status = 'injured'
      racer.health = [0, racer.health - 25].max
    end
  end
end
