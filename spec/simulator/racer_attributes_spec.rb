require_relative '../../lib/simulator/race_simulator'
require_relative '../../lib/models'

RSpec.describe 'In-race attributes, health, and preferred track' do
  def racer_hash(id:, name:, strategy: 'balanced', base: 80, pref: 'asphalt',
                 health: 100, acceleration: 50, endurance: 50, consistency: 50,
                 stamina_recovery: 50)
    {
      'id' => id,
      'name' => name,
      'color' => '#ffffff',
      'baseSpeed' => base,
      'health' => health,
      'strategy' => strategy,
      'trackPreference' => pref,
      'acceleration' => acceleration,
      'endurance' => endurance,
      'consistency' => consistency,
      'staminaRecovery' => stamina_recovery
    }
  end

  def by_id(sim)
    sim.racers.each_with_object({}) { |r, h| h[r.id] = r }
  end

  def run_until(sim, pred, max_ticks: 8000)
    max_ticks.times do |i|
      sim.instance_variable_set(:@tick_count, i)
      sim.send(:tick, i * RaceSimulator::UPDATE_INTERVAL_MS)
      return i if pred.call(sim)
      break if sim.is_finished
    end
    nil
  end

  def gap_laps(a, b, track)
    (a.total_distance - b.total_distance) / track.length.to_f
  end

  it 'puts the preferred-surface horse ahead of a mismatch at ~50%, still packed' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    racers = [
      racer_hash(id: 'pref', name: 'Pref', pref: 'asphalt'),
      racer_hash(id: 'miss', name: 'Miss', pref: 'dirt')
    ]
    srand(41)
    sim = RaceSimulator.new(race_id: 'attr-track', track: track, racers: racers)
    allow(sim).to receive(:check_injury)

    target = sim.total_distance * 0.50
    run_until(sim, ->(s) { s.racers.map(&:total_distance).min >= target })

    r = by_id(sim)
    expect(r['pref'].total_distance).to be > r['miss'].total_distance
    g = gap_laps(r['pref'], r['miss'], track)
    expect(g).to be > 0.012
    expect(g).to be < 0.12
  end

  it 'makes a fresh horse (health 100) ahead of a depleted one (health 40) with the same strategy' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    racers = [
      racer_hash(id: 'fresh', name: 'Fresh', health: 100),
      racer_hash(id: 'tired', name: 'Tired', health: 40)
    ]
    srand(17)
    sim = RaceSimulator.new(race_id: 'attr-health', track: track, racers: racers)
    allow(sim).to receive(:check_injury)

    target = sim.total_distance * 0.50
    run_until(sim, ->(s) { s.racers.map(&:total_distance).min >= target })

    r = by_id(sim)
    expect(r['fresh'].total_distance).to be > r['tired'].total_distance
    g = gap_laps(r['fresh'], r['tired'], track)
    expect(g).to be > 0.012
    expect(g).to be < 0.12
  end

  it 'lets high acceleration show vs low acceleration by ~10% race distance' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    racers = [
      racer_hash(id: 'hi', name: 'HiAccel', acceleration: 92),
      racer_hash(id: 'lo', name: 'LoAccel', acceleration: 12)
    ]
    srand(23)
    sim = RaceSimulator.new(race_id: 'attr-accel', track: track, racers: racers)
    allow(sim).to receive(:check_injury)

    target = sim.total_distance * 0.10
    run_until(sim, ->(s) { s.racers.map(&:total_distance).max >= target })

    r = by_id(sim)
    expect(r['hi'].total_distance).to be > r['lo'].total_distance
    g = gap_laps(r['hi'], r['lo'], track)
    expect(g).to be > 0.008
    expect(g).to be < 0.10
  end

  it 'lets high endurance hold form vs low endurance at ~80%' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    racers = [
      racer_hash(id: 'hi', name: 'HiEnd', endurance: 92),
      racer_hash(id: 'lo', name: 'LoEnd', endurance: 18)
    ]
    srand(31)
    sim = RaceSimulator.new(race_id: 'attr-endurance', track: track, racers: racers)
    allow(sim).to receive(:check_injury)

    target = sim.total_distance * 0.80
    run_until(sim, ->(s) { s.racers.map(&:total_distance).min >= target })

    r = by_id(sim)
    expect(r['hi'].health).to be > r['lo'].health
    expect(r['hi'].health).to be > r['lo'].health + 8
    faded = r['hi'].total_distance >= r['lo'].total_distance ||
            r['hi'].current_speed > r['lo'].current_speed
    expect(faded).to be true
    g = (r['hi'].total_distance - r['lo'].total_distance).abs / track.length.to_f
    expect(g).to be < 0.12
  end

  it 'does not give a grass-preference horse a speed bonus on dirt' do
    dirt = Models::Track.new(id: 'd1', name: 'Dirt', surface: 'dirt', length: 1000, laps: 3)
    grass = Models::Track.new(id: 'g1', name: 'Turf', surface: 'grass', length: 1000, laps: 3)
    horse = Racer.from_hash(racer_hash(id: 'turf', name: 'Turf', pref: 'grass'))

    dirt_sim = RaceSimulator.new(race_id: 'grass-dirt', track: dirt, racers: [racer_hash(id: 'turf', name: 'Turf', pref: 'grass')])
    grass_sim = RaceSimulator.new(race_id: 'grass-grass', track: grass, racers: [racer_hash(id: 'turf', name: 'Turf', pref: 'grass')])
    asphalt_sim = RaceSimulator.new(
      race_id: 'grass-asphalt',
      track: Models::Track.new(id: 'a1', name: 'Asphalt', surface: 'asphalt', length: 1000, laps: 3),
      racers: [racer_hash(id: 'turf', name: 'Turf', pref: 'grass')]
    )

    dirt_pen = dirt_sim.send(:calculate_track_penalty, horse)
    grass_pen = grass_sim.send(:calculate_track_penalty, horse)
    asphalt_pen = asphalt_sim.send(:calculate_track_penalty, horse)

    expect(dirt_pen).to be > 0
    expect(asphalt_pen).to be > 0
    expect(grass_pen).to be < 0
    expect(dirt_pen).to eq(RaceSimulator::TRACK_MISMATCH_PENALTY)
    expect(asphalt_pen).to eq(RaceSimulator::TRACK_MISMATCH_PENALTY)
    expect(grass_pen).to eq(-RaceSimulator::TRACK_PREF_BONUS)
  end

  it 'applies pairwise mismatch across asphalt, dirt, and grass' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 1)
    sim = RaceSimulator.new(
      race_id: 'pair',
      track: track,
      racers: [racer_hash(id: 'x', name: 'X', pref: 'asphalt')]
    )
    asphalt = Racer.from_hash(racer_hash(id: 'a', name: 'A', pref: 'asphalt'))
    dirt = Racer.from_hash(racer_hash(id: 'd', name: 'D', pref: 'dirt'))
    grass = Racer.from_hash(racer_hash(id: 'g', name: 'G', pref: 'grass'))

    expect(sim.send(:calculate_track_penalty, asphalt)).to eq(-RaceSimulator::TRACK_PREF_BONUS)
    expect(sim.send(:calculate_track_penalty, dirt)).to eq(RaceSimulator::TRACK_MISMATCH_PENALTY)
    expect(sim.send(:calculate_track_penalty, grass)).to eq(RaceSimulator::TRACK_MISMATCH_PENALTY)
  end
end
