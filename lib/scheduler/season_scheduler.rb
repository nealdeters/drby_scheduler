require_relative '../models'
require_relative '../services'

class SeasonScheduler
  RACES_PER_SEASON = 1008
  RACE_INTERVAL_MINUTES = 10

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
    return false unless race

    race.completed = true
    race.results = results
    race.finish_times = finish_times

    update_standings_from_results(results)
    update_racer_health(results)

    save_schedule
    save_standings
    save_roster

    check_and_start_new_season if all_races_completed?

    true
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

    @roster.each do |racer|
      if result_ids.include?(racer.id)
        fatigue_rate = case racer.strategy
                       when 'aggressive' then rand(8..12)
                       when 'conservative' then rand(3..5)
                       else rand(5..8)
                       end

        if results.find { |r| r.id == racer.id }&.status == 'injured'
          fatigue_rate += 25
        end

        racer.health = [0, racer.health - fatigue_rate].max
      else
        recovery_rate = 3 + (racer.stamina_recovery / 100.0) * 12 + rand(0..3)
        racer.health = [100, racer.health + recovery_rate].min
      end
    end
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
      num_racers = rand(4..8)
      shuffled = @roster.shuffle
      selected_ids = shuffled.take(num_racers).map(&:id)

      race = RaceEvent.new(
        id: "#{season_prefix}-race-#{i}-#{now.to_i}",
        start_time: (start_time + (i * RACE_INTERVAL_MINUTES * 60)).to_i * 1000,
        seed: rand(1_000_000),
        track: @tracks[i % @tracks.length],
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

  def save_schedule
    @storage.save_schedule(@schedule.map(&:to_h))
  end

  def save_standings
    @storage.save_standings(@standings)
  end

  def save_roster
    @storage.save_roster(@roster.map(&:to_h))
  end

  def save_completed_seasons
    @storage.save_completed_seasons(@completed_seasons)
  end

  def save_season_number
    @storage.save_season_number(@current_season)
  end
end
