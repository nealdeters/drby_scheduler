require_relative '../models'

class RaceSimulator
  UPDATE_INTERVAL_MS = 10
  MAX_DURATION_MS = 300_000

  # Per-tick health drain (10ms ticks). Tuned so mid/long races leave
  # finishers meaningfully below 100 and strategies stay distinct.
  STRATEGY_DECAY = {
    'aggressive' => 0.055,
    'balanced' => 0.032,
    'conservative' => 0.018
  }.freeze

  # Speed noise per tick — enough for pack reshuffles without chaos.
  STRATEGY_VARIANCE = {
    'aggressive' => 0.14,
    'balanced' => 0.09,
    'conservative' => 0.05
  }.freeze

  # Pack compression: keep the field in a readable bunch (a few lengths,
  # not strung around the oval) while still allowing a winner.
  # Preferred surface is a small bonus; any other surface is a real penalty.
  # Grass bonus applies only on grass — never on dirt/asphalt.
  TRACK_PREF_BONUS = 0.035
  TRACK_MISMATCH_PENALTY = 0.048
  # Min speed vs own base — tired horses still run with the pack.
  SPEED_FLOOR_RATIO = 0.84
  # Fatigue scale at empty health (tired**1.25 * scale). Soft early, still
  # bites at mid health so a 40 is slower than a 100 from tick 0.
  FATIGUE_SCALE = 0.18
  HEALTH_PACE_SCALE = 0.08
  # Catch-up holds the oval together but must not erase attr/track/health
  # gaps. Do not raise CATCHUP_MAX_BOOST.
  CATCHUP_START_LAPS = 0.032
  CATCHUP_FULL_LAPS = 0.064
  CATCHUP_MAX_BOOST = 0.50
  ACCEL_WINDOW = 0.14
  ACCEL_BOOST_SCALE = 0.20
  ENDURANCE_HOLD_START = 0.55
  ENDURANCE_HOLD_SCALE = 0.10
  STAMINA_DRAIN_RELIEF = 0.16
  STAMINA_TICK_RECOVER = 0.005
  CONSISTENCY_WEAVE = 0.045
  # Front-runners may open a watchable lead before rubber-band.
  BREAK_PROGRESS = 0.12
  BREAK_CATCHUP_START_LAPS = 0.07
  # Late charge can show; still catch a parade-sized hole.
  LATE_CATCHUP_START_LAPS = 0.09
  LATE_CATCHUP_MAX_BOOST = 0.22
  # Early / mid / late pace shape by declared strategy.
  # aggressive: jump the break, spend for the lead, fade.
  # balanced: even early, opportunistic mid bursts, not a closer.
  # conservative: hold with the pack, charge last ~15–20%.
  STRATEGY_PACE = {
    'aggressive' => { early: 0.18, mid: 0.02, late: -0.05 }.freeze,
    'balanced' => { early: 0.0, mid: 0.03, late: 0.0 }.freeze,
    'conservative' => { early: -0.02, mid: 0.0, late: 0.20 }.freeze
  }.freeze
  # Extra late kick. Conservative only; balanced bursts are mid-race.
  STRATEGY_CLOSING = {
    'aggressive' => 0.0,
    'balanced' => 0.0,
    'conservative' => 1.70
  }.freeze
  CONSERVATIVE_KICK_START = 0.80
  BALANCED_BURST_WINDOWS = [[0.28, 0.38], [0.44, 0.54]].freeze

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

  def reset_tick_count
    @tick_count = 0
  end

  def run(ably_service:, on_progress: nil, on_finish: nil)
    puts "[Simulator] Starting race #{@race_id} with #{@racers.length} racers"

    ably_service.publish_race_started(@race_id, @racers, @track, 0) if ably_service

    race_start = Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000

    while !@is_finished && (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000 - race_start) < MAX_DURATION_MS
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000 - race_start).to_i
      tick(elapsed)
      @tick_count += 1

      if @tick_count % 5 == 0
        ably_service.publish_race_progress(@race_id, @racers, @tick_count, @total_distance, elapsed) if ably_service
        on_progress&.call(@racers, @tick_count)
      end

      sleep(UPDATE_INTERVAL_MS / 1000.0)
    end

    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000 - race_start).to_i

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
    
    puts "[Simulator] Calling on_finish callback with #{all_results.length} results"
    on_finish&.call(all_results, @tick_count)
    puts "[Simulator] on_finish callback completed"

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
    puts "[Simulator] Race #{@race_id}: #{dnf.length} DNF (health <= #{Racer::MIN_RACE_HEALTH}), #{active.length} racing"

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
    endurance_mult = endurance_drain_mult(racer)
    # Front-runners pay a stamina tax so early leads can fade.
    lead_pressure = lead_pressure_for(racer, race_progress)
    # Pushing hard (high current speed vs base) also burns more.
    pace_pressure = pace_pressure_for(racer)

    recovery = (racer.stamina_recovery.to_f / 100.0).clamp(0.0, 1.0)
    health_drain = decay_rate * endurance_mult * (1.0 + lead_pressure + pace_pressure)
    health_drain *= (1.0 - STAMINA_DRAIN_RELIEF * recovery)
    racer.health = [0, racer.health - health_drain].max
    # Tiny in-race recover when not pushing — not a second health bar.
    if pace_pressure <= 0 && lead_pressure <= 0 && race_progress > 0.04 && race_progress < 0.80
      racer.health = [100.0, racer.health + STAMINA_TICK_RECOVER * recovery].min
    end

    base_speed = racer.base_speed * (UPDATE_INTERVAL_MS / 1000.0)

    acceleration_boost = acceleration_boost_for(racer, race_progress)
    strategy_pace = strategy_pace_for(racer, race_progress)
    mid_burst = mid_burst_for(racer, race_progress)
    # Late-race closing kick for trailers with gas left — enables comebacks.
    closing_boost = closing_boost_for(racer, race_progress)
    endurance_hold = endurance_hold_for(racer, race_progress)
    # Soft rubber-band for deep trailers (pack compression).
    catch_up_boost = catch_up_boost_for(racer)

    track_penalty = calculate_track_penalty(racer)
    health_pace = health_pace_for(racer)
    # Nonlinear fatigue: bites at mid health, harsh when gassed.
    tired = [(100 - racer.health) / 100.0, 0].max
    fatigue_penalty = (tired ** 1.25) * FATIGUE_SCALE

    base_variance = STRATEGY_VARIANCE[racer.strategy] || STRATEGY_VARIANCE['balanced']
    # Low consistency wanders in the pack; high consistency holds a line.
    consistency = (racer.consistency.to_f / 100.0).clamp(0.0, 1.0)
    consistency_mult = [0.22, 1.0 - consistency].max
    variance_cap = base_variance * consistency_mult * (0.55 + (1.0 - consistency) * 0.90)
    # Slightly more upside variance late so packs reshuffle.
    late_mult = race_progress > 0.55 ? 1.25 : 1.0
    speed_adjustment = (rand - 0.5) * 2 * variance_cap * late_mult
    weave = Math.sin(@tick_count * 0.017 + racer.lane.to_f * 1.7) * CONSISTENCY_WEAVE * (1.0 - consistency)

    final_speed = base_speed * (1 + acceleration_boost + strategy_pace + mid_burst + closing_boost + endurance_hold + catch_up_boost + health_pace + speed_adjustment + weave - fatigue_penalty - track_penalty)
    final_speed = [final_speed, base_speed * SPEED_FLOOR_RATIO].max
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

  def lead_pressure_for(racer, race_progress)
    pos = racer.position.to_i
    return 0 if pos <= 0 || race_progress < 0.08

    case pos
    when 1 then 0.55 + race_progress * 0.35
    when 2 then 0.28 + race_progress * 0.2
    when 3 then 0.12
    else 0
    end
  end

  def pace_pressure_for(racer)
    base = racer.base_speed * (UPDATE_INTERVAL_MS / 1000.0)
    return 0 if base <= 0 || racer.current_speed.to_f <= 0

    ratio = racer.current_speed / base
    return 0 if ratio < 1.05

    ((ratio - 1.05) * 0.8).clamp(0.0, 0.45)
  end

  def strategy_pace_for(racer, race_progress)
    profile = STRATEGY_PACE[racer.strategy] || STRATEGY_PACE['balanced']
    early = profile[:early]
    mid = profile[:mid]
    late = profile[:late]
    rp = race_progress.to_f
    strat = racer.strategy

    case strat
    when 'aggressive'
      if rp < BREAK_PROGRESS
        early
      elsif rp < 0.22
        t = ((rp - BREAK_PROGRESS) / (0.22 - BREAK_PROGRESS)).clamp(0.0, 1.0)
        early + (mid - early) * t
      elsif rp < 0.70
        mid
      else
        t = ((rp - 0.70) / 0.30).clamp(0.0, 1.0)
        mid + (late - mid) * t
      end
    when 'conservative'
      # Hold with the pack until the last ~15–20%, then charge.
      if rp < CONSERVATIVE_KICK_START
        early
      elsif rp < 0.85
        t = ((rp - CONSERVATIVE_KICK_START) / (0.85 - CONSERVATIVE_KICK_START)).clamp(0.0, 1.0)
        early + (late - early) * t
      else
        late
      end
    else
      # Balanced: even early, slight mid cruise (bursts are extra), no late charge.
      if rp < BREAK_PROGRESS
        early
      elsif rp < 0.22
        t = ((rp - BREAK_PROGRESS) / (0.22 - BREAK_PROGRESS)).clamp(0.0, 1.0)
        early + (mid - early) * t
      elsif rp < 0.58
        mid
      else
        late
      end
    end
  end

  # Opportunistic mid-race speed for balanced only — not a planned closer.
  # Triangle pulses so it reads as a burst, not a second race shape.
  def mid_burst_for(racer, race_progress)
    return 0 unless racer.strategy == 'balanced'
    return 0 if racer.health.to_f < 45
    return 0 if racer.position.to_i == 1

    rp = race_progress.to_f
    BALANCED_BURST_WINDOWS.each do |a, b|
      next unless rp >= a && rp < b
      span = b - a
      t = (rp - a) / span
      pulse = t < 0.5 ? t * 2.0 : (1.0 - t) * 2.0
      return 0.11 * pulse
    end
    0
  end

  def closing_boost_for(racer, race_progress)
    strat_mult = STRATEGY_CLOSING[racer.strategy] || 0.0
    return 0 if strat_mult <= 0

    kick_start = racer.strategy == 'conservative' ? CONSERVATIVE_KICK_START : 0.70
    return 0 if race_progress < kick_start

    pos = racer.position.to_i
    field = [@racers.length, 1].max
    return 0 if pos <= 0

    # Conservative charges if they still have gas; others only from off the lead.
    if racer.strategy != 'conservative'
      return 0 if pos < 2
    end

    # Health + endurance gate the kick — gassed horses cannot surge.
    gas = racer.health / 100.0
    return 0 if gas < 0.35

    endurance = racer.endurance / 100.0
    depth = (pos - 1).to_f / field
    late = ((race_progress - kick_start) / (1.0 - kick_start)).clamp(0.0, 1.0)
    (0.05 + depth * 0.14 * gas * (0.45 + endurance * 0.55) * late) * strat_mult
  end

  # Soft catch-up when behind the current *live* leader.
  # Finished horses are not a moving target — freeze-at-finish is enough;
  # do not yo-yo trailers around the last lap after the race is decided.
  def catch_up_boost_for(racer)
    return 0 if racer.finished?
    live = @racers.reject(&:finished?)
    leader_dist = live.map(&:total_distance).max
    return 0 if leader_dist.nil? || @track.length.to_f <= 0 || @total_distance.to_f <= 0

    leader_progress = leader_dist / @total_distance.to_f
    start = CATCHUP_START_LAPS
    full = CATCHUP_FULL_LAPS
    max_boost = CATCHUP_MAX_BOOST
    # Do not erase the break. Still catch a mismatch that would string the oval.
    if leader_progress < BREAK_PROGRESS
      start = BREAK_CATCHUP_START_LAPS
      full = start + (CATCHUP_FULL_LAPS - CATCHUP_START_LAPS)
    elsif leader_progress >= CONSERVATIVE_KICK_START
      # Do not rubber-band a closer's charge into an even line.
      start = LATE_CATCHUP_START_LAPS
      full = start + (CATCHUP_FULL_LAPS - CATCHUP_START_LAPS)
      max_boost = LATE_CATCHUP_MAX_BOOST
    end

    behind_laps = (leader_dist - racer.total_distance) / @track.length.to_f
    return 0 if behind_laps < start

    span = full - start
    t = ((behind_laps - start) / span).clamp(0.0, 1.0)
    max_boost * t
  end

  def calculate_track_penalty(racer)
    pref = racer.track_preference.to_s
    surface = @track.surface.to_s
    return 0 if pref.empty? || surface.empty?

    if pref == surface
      -TRACK_PREF_BONUS
    else
      TRACK_MISMATCH_PENALTY
    end
  end

  def endurance_drain_mult(racer)
    # High endurance drains slowly; low endurance fades early.
    [0.22, (100.0 - racer.endurance.to_f) / 100.0].max
  end

  def health_pace_for(racer)
    # Depleted horses are slower from the gun, not only once empty.
    frac = (racer.health.to_f / 100.0).clamp(0.0, 1.0)
    (frac - 1.0) * HEALTH_PACE_SCALE
  end

  def acceleration_boost_for(racer, race_progress)
    return 0 if race_progress >= ACCEL_WINDOW

    accel_factor = (racer.acceleration.to_f / 100.0).clamp(0.0, 1.5)
    fade = (1.0 - race_progress / ACCEL_WINDOW).clamp(0.0, 1.0)
    ACCEL_BOOST_SCALE * accel_factor * fade
  end

  def endurance_hold_for(racer, race_progress)
    return 0 if race_progress < ENDURANCE_HOLD_START

    t = ((race_progress - ENDURANCE_HOLD_START) / (1.0 - ENDURANCE_HOLD_START)).clamp(0.0, 1.0)
    ((racer.endurance.to_f / 100.0) - 0.5) * ENDURANCE_HOLD_SCALE * t
  end

  def check_injury(racer)
    injury_chance = 0.012 * (1 + ((100 - racer.health) / 100.0)**2 * 5)
    if rand < injury_chance && racer.health < 80
      racer.status = 'injured'
      racer.health = [0, racer.health - 28].max
    end
  end
end
