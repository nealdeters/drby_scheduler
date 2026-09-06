require_relative '../models'
require_relative '../services'

class SeasonScheduler
  RACES_PER_SEASON = 1008
  RACE_INTERVAL_MINUTES = 10

  # --- Sit-out recovery (per completed race interval) ---
  # One sit must never fully refill: from ~0, full freshness takes several rests.
  # Chunk ≈ 15–28 pts/sit → ~4–7 sits from wiped to fresh.
  SIT_RECOVERY_BASE = 15
  SIT_RECOVERY_STAMINA_SCALE = 9   # * (stamina_recovery / 100)
  SIT_RECOVERY_JITTER = 4         # + rand(0..JITTER)
  SIT_RECOVERY_CAP = 28           # hard cap so 0→100 in one sit is impossible

  # Post-race residual fatigue on top of finishing in-race health.
  # Keeps finishers meaningfully depleted into the next cycle.
  RESIDUAL_FATIGUE = {
    'aggressive' => 8..14,
    'conservative' => 4..8,
    'balanced' => 6..11
  }.freeze
  RESIDUAL_INJURY_BONUS = 22

  # --- Rest vs gamble field selection ---
  MIN_FIELD = 4
  MAX_FIELD = 8
  # Below this, entry desire collapses unless a strong gamble hook fires.
  LOW_HEALTH_REST_THRESHOLD = 55
  # Absolute refuse-to-enter floor (also see Racer::MIN_RACE_HEALTH).
  HARD_REST_HEALTH = 12

  def initialize(storage_service:, racers_storage: nil, tracks_storage: nil)
    @storage = storage_service
    @racers_storage = racers_storage || storage_service
    @tracks_storage = tracks_storage || storage_service
    @roster = []
    @tracks = []
    @schedule = []
    @standings = {}
    @current_season = 1
    @completed_seasons = []
  end

  def load
    load_roster
    load_tracks
    load_or_create_schedule
    load_standings
    load_completed_seasons
    self
  end

  def roster
    @roster
  end

  def tracks
    @tracks
  end

  def schedule
    @schedule
  end

  def standings
    @standings
  end

  def current_season
    @current_season
  end

  def next_pending_race
    now = Time.now.to_i * 1000
    @schedule.find { |race| !race.completed && race.start_time <= now }
  end

  def all_races_completed?
    @schedule.all?(&:completed)
  end

  def complete_race(race_id, results, finish_times)
    race = @schedule.find { |r| r.id == race_id }
    unless race
      puts "[Scheduler] ERROR: Race #{race_id} not found in schedule during complete_race!"
      return false
    end

    race.completed = true
    race.results = results.map(&:id)
    race.finish_times = finish_times
    
    puts "[Scheduler] Marked race #{race_id} as completed with #{results.length} results"

    update_standings_from_results(results)
    update_racer_health(results)

    puts "[Scheduler] Saving schedule..."
    save_schedule
    puts "[Scheduler] Schedule saved successfully"
    save_standings
    save_roster

    check_and_start_new_season if all_races_completed?

    true
  rescue => e
    puts "[Scheduler] ERROR saving race #{race_id}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    raise
  end

  def update_standings_from_results(results)
    return if results.empty?

    @standings[results[0].id] ||= 0
    @standings[results[1]&.id] ||= 0
    @standings[results[2]&.id] ||= 0

    @standings[results[0].id] += 5
    @standings[results[1]&.id] += 3 if results[1]
    @standings[results[2]&.id] += 1 if results[2]
  end

  def update_racer_health(results)
    result_ids = results.map(&:id)
    by_id = results.each_with_object({}) { |r, h| h[r.id] = r }

    @roster.each do |racer|
      if result_ids.include?(racer.id)
        raced = by_id[racer.id]
        # Carry actual in-race finishing health onto the roster so drain sticks.
        # Never snap back to full after racing — residual fatigue stays meaningful.
        finishing = raced.respond_to?(:health) ? raced.health.to_f : racer.health.to_f
        range = RESIDUAL_FATIGUE[racer.strategy] || RESIDUAL_FATIGUE['balanced']
        residual = rand(range)
        residual += RESIDUAL_INJURY_BONUS if raced&.status == 'injured'
        racer.health = [0.0, finishing - residual].max.round(2)
      else
        # Partial sit recovery only — one sit cannot refill 0→100.
        racer.health = [100.0, racer.health.to_f + sit_recovery_amount(racer)].min.round(2)
      end
    end
  end

  # Public so orchestrator can rebuild the field at race time from live health.
  def assign_field_for_race!(race, target_size: nil)
    track = normalize_track(race.track)
    max_size = [@roster.length, MAX_FIELD].min
    min_size = [MIN_FIELD, max_size].min
    raw = target_size || race.racer_ids&.length || (min_size > max_size ? max_size : rand(min_size..max_size))
    size = raw.to_i.clamp(min_size, max_size)

    selected = select_field(track, size)
    race.racer_ids = selected.map(&:id)
    race
  end

  def select_field(track, size)
    return [] if @roster.empty?

    scored = @roster.map do |racer|
      desire = entry_desire(racer, track)
      [racer, desire]
    end

    # Willing = positive desire; if too few, allow least-negative as desperate fills.
    willing = scored.select { |_, d| d > 0.0 }
    if willing.length < MIN_FIELD
      willing = scored.reject { |_, d| d <= -1.0 }.sort_by { |_, d| -d }.first(size)
    end

    # Rank by desire with light noise so ties are not static; take top `size`.
    ranked = willing.sort_by { |_, d| -(d + rand * 0.08) }
    ranked.first(size).map(&:first)
  end

  # Strategic entry score: healthy horses enter normally; depleted ones usually
  # rest but sometimes gamble on soft fields / preferred tracks / points need.
  def entry_desire(racer, track)
    health = racer.health.to_f
    return -1.0 if health <= HARD_REST_HEALTH

    desire = health / 100.0

    # Track affinity hooks (prefer match, soft-penalize mismatch).
    surface = track_surface(track)
    pref = racer.track_preference.to_s
    if surface && pref == surface
      desire += 0.18
    elsif surface && pref != 'grass' && pref != surface
      desire -= 0.10
    elsif pref == 'grass'
      desire += 0.05
    end

    # Points standing: trailers are hungrier to race for points.
    pts = (@standings[racer.id] || 0).to_f
    max_pts = @standings.values.map(&:to_f).max || 0.0
    if max_pts > 0
      trailing = 1.0 - (pts / max_pts)
      desire += trailing * 0.12
    end

    # Soft-field gamble estimate: if many roster mates are also depleted,
    # a low-health horse may risk it (weaker expected competition).
    depleted_share = @roster.count { |r| r.health.to_f < LOW_HEALTH_REST_THRESHOLD }.to_f / [@roster.length, 1].max
    soft_field = depleted_share >= 0.45

    if health < LOW_HEALTH_REST_THRESHOLD
      # Default: prefer rest. Gamble only with a clear hook.
      rest_bias = (LOW_HEALTH_REST_THRESHOLD - health) / LOW_HEALTH_REST_THRESHOLD
      desire -= 0.55 * rest_bias

      gamble = 0.0
      gamble += 0.28 if soft_field
      gamble += 0.22 if surface && pref == surface
      gamble += 0.12 if max_pts > 0 && pts < max_pts * 0.5
      # Small random spark so gambles are occasional, not spam.
      gamble += rand * 0.10
      desire += gamble

      # Still often negative → sits this race out.
    end

    desire
  end

  def start_new_season
    season_to_save = {
      'id' => "season-#{@current_season}-#{Time.now.to_i}",
      'number' => @current_season,
      'completedAt' => Time.now.iso8601,
      'winner' => determine_winner,
      'totalRaces' => @schedule.count(&:completed),
      'finalStandings' => @standings.dup,
      'races' => @schedule.select(&:completed).map(&:to_h)
    }

    @completed_seasons << season_to_save

    @current_season += 1
    reset_standings
    reset_racer_health
    generate_new_schedule

    save_completed_seasons
    save_season_number
    save_standings
    save_roster
    save_schedule

    true
  end

  def save_race_tick_count(race_id, tick_count = nil)
    race = @schedule.find { |r| r.id == race_id }
    unless race
      puts "[Scheduler] WARNING: Race #{race_id} not found when saving tick_count"
      return false
    end
    race.tick_count = tick_count unless tick_count.nil?
    save_schedule
    puts "[Scheduler] Saved tick_count=#{race.tick_count.inspect} for race #{race_id}"
    true
  rescue => e
    puts "[Scheduler] ERROR saving tick_count for #{race_id}: #{e.message}"
    false
  end

  def save_schedule
    @storage.save_schedule(@schedule.map(&:to_h))
  end

  def verify_race_saved(race_id)
    saved_data = @storage.get_schedule
    saved_race = saved_data.find { |r| r['id'] == race_id } if saved_data
    if saved_race
      puts "[Scheduler] Verified race #{race_id} in storage: completed=#{saved_race['completed']}, results_count=#{saved_race['results']&.length || 0}"
      true
    else
      puts "[Scheduler] ERROR: Race #{race_id} not found in storage after save!"
      false
    end
  rescue => e
    puts "[Scheduler] ERROR verifying race #{race_id}: #{e.message}"
    false
  end

  private

  def load_roster
    data = @racers_storage.get_all_racers
    @roster = data.map { |r| Racer.from_hash(r) }
    puts "[Scheduler] Loaded #{@roster.length} racers"
  end

  def load_tracks
    data = @tracks_storage.get_all_tracks
    if data && data.is_a?(Array) && !data.empty?
      @tracks = data.map { |t| Track.from_hash(t) }
    else
      @tracks = []
    end
    puts "[Scheduler] Loaded #{@tracks.length} tracks"
  end

  def load_or_create_schedule
    data = @storage.get_schedule
    if data && data.is_a?(Array) && !data.empty?
      @schedule = data.map { |r| RaceEvent.from_hash(r) }
      @current_season = extract_season_number
      puts "[Scheduler] Loaded schedule with #{@schedule.length} races, season #{@current_season}"
    else
      generate_new_schedule
      save_schedule
      puts "[Scheduler] Generated new schedule with #{@schedule.length} races"
    end
  end

  def load_standings
    data = @storage.get_standings
    @standings = data.is_a?(Hash) ? data : {}
    puts "[Scheduler] Loaded standings for #{@standings.length} racers"
  end

  def load_completed_seasons
    data = @storage.get_completed_seasons
    @completed_seasons = data.is_a?(Array) ? data : []
    puts "[Scheduler] Loaded #{@completed_seasons.length} completed seasons"
  end

  def extract_season_number
    return 1 if @schedule.empty?

    first_race = @schedule.first.id
    match = first_race.match(/s(\d+)-/)
    match ? match[1].to_i : 1
  end

  def generate_new_schedule
    @schedule = []

    if @roster.empty? || @tracks.empty?
      puts "[Scheduler] Cannot generate schedule: #{@roster.empty? ? 'no racers' : 'no tracks'}"
      return
    end

    now = Time.now
    next_minute = ((now.min / 10) + 1) * 10
    if next_minute >= 60
      start_time = Time.new(now.year, now.month, now.day, now.hour + 1, 0, 0, '+00:00')
    else
      start_time = Time.new(now.year, now.month, now.day, now.hour, next_minute, 0, '+00:00')
    end

    if start_time <= now
      start_time += 60 * 10
    end

    season_prefix = "s#{@current_season}"

    RACES_PER_SEASON.times do |i|
      max_size = [@roster.length, MAX_FIELD].min
      min_size = [MIN_FIELD, max_size].min
      num_racers = min_size >= max_size ? max_size : rand(min_size..max_size)
      track = @tracks[i % @tracks.length]
      # Placeholder field at schedule time; live rest-vs-gamble reassigns at race start.
      selected_ids = select_field(track, num_racers).map(&:id)

      race = RaceEvent.new(
        id: "#{season_prefix}-race-#{i}-#{now.to_i}",
        start_time: (start_time + (i * RACE_INTERVAL_MINUTES * 60)).to_i * 1000,
        seed: rand(1_000_000),
        track: track,
        racer_ids: selected_ids
      )

      @schedule << race
    end
  end

  def reset_standings
    @standings = {}
    @roster.each { |r| @standings[r.id] = 0 }
  end

  def reset_racer_health
    @roster.each { |r| r.health = 100 }
  end

  def determine_winner
    return nil if @standings.empty?

    winner_id = @standings.max_by { |_, points| points }[0]
    winner = @roster.find { |r| r.id == winner_id }
    return nil unless winner

    {
      'id' => winner.id,
      'name' => winner.name,
      'color' => winner.color,
      'points' => @standings[winner_id]
    }
  end

  def check_and_start_new_season
    return if @schedule.empty?

    puts "[Scheduler] All races completed, starting new season..."
    start_new_season
  end
  def save_standings
    @storage.save_standings(@standings)
  end

  def save_roster
    payload = @roster.map(&:to_h)
    # Legacy aggregate key on the races store (kept for compatibility).
    @storage.save_roster(payload) if @storage.respond_to?(:save_roster)

    # CRITICAL: load_roster reads individual blobs from site:racers via
    # get_all_racers. Health must be written there or every restart (and any
    # UI reading racer blobs) snaps sitters back to seeded 100 — the old
    # "one sit → 0% to 100%" bug.
    if @racers_storage.respond_to?(:set_blob)
      @roster.each do |racer|
        @racers_storage.set_blob(racer.id, racer.to_h)
      end
    end
  end

  def sit_recovery_amount(racer)
    stamina = racer.stamina_recovery.to_f
    raw = SIT_RECOVERY_BASE + (stamina / 100.0) * SIT_RECOVERY_STAMINA_SCALE + rand(0..SIT_RECOVERY_JITTER)
    [raw, SIT_RECOVERY_CAP].min
  end

  def normalize_track(track)
    return track if track.is_a?(Track)
    return Track.from_hash(track) if track.is_a?(Hash)
    track
  end

  def track_surface(track)
    t = normalize_track(track)
    return nil unless t
    t.respond_to?(:surface) ? t.surface : t['surface']
  end

  def save_completed_seasons
    @storage.save_completed_seasons(@completed_seasons)
  end

  def save_season_number
    @storage.save_season_number(@current_season)
  end

end
