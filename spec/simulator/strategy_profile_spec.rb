require_relative '../../lib/simulator/race_simulator'
require_relative '../../lib/models'

RSpec.describe 'Strategy pace profiles' do
  def racer_hash(id:, name:, strategy:, base: 80, pref: 'asphalt', health: 100)
    {
      'id' => id,
      'name' => name,
      'color' => '#ffffff',
      'baseSpeed' => base,
      'health' => health,
      'strategy' => strategy,
      'trackPreference' => pref,
      'acceleration' => 50,
      'endurance' => 50,
      'consistency' => 50,
      'staminaRecovery' => 50
    }
  end

  def identical_field
    [
      racer_hash(id: 'agg', name: 'Agg', strategy: 'aggressive'),
      racer_hash(id: 'bal', name: 'Bal', strategy: 'balanced'),
      racer_hash(id: 'con', name: 'Con', strategy: 'conservative')
    ]
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

  def gap_laps(sim)
    dists = sim.racers.reject { |r| %w[injured dnf].include?(r.status) }.map(&:total_distance)
    return 0 if dists.empty?
    (dists.max - dists.min) / sim.track.length.to_f
  end

  it 'gives aggressive a watchable jump at ~10% race distance' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    srand(11)
    sim = RaceSimulator.new(race_id: 'strat-break', track: track, racers: identical_field)
    allow(sim).to receive(:check_injury)

    target = sim.total_distance * 0.10
    run_until(sim, ->(s) { s.racers.map(&:total_distance).max >= target })

    r = by_id(sim)
    agg_laps = r['agg'].total_distance / track.length.to_f
    bal_laps = r['bal'].total_distance / track.length.to_f
    con_laps = r['con'].total_distance / track.length.to_f
    expect(agg_laps).to be > bal_laps
    expect(con_laps).to be <= bal_laps
    expect(r['con'].total_distance).to be < r['agg'].total_distance
    gap = agg_laps - bal_laps
    expect(gap).to be > 0.03
    expect(gap).to be < 0.10
    # Conservative holds with the pack — not detached, not the early leader.
    expect(r['con'].position).not_to eq(1)
    expect((bal_laps - con_laps).abs).to be < 0.04
  end

  it 'keeps a mixed field in a pack at ~50% even with strategy lines' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    racers = [
      racer_hash(id: 'fast', name: 'Fast', strategy: 'aggressive', base: 92),
      racer_hash(id: 'mid', name: 'Mid', strategy: 'balanced', base: 80),
      racer_hash(id: 'slow', name: 'Slow', strategy: 'conservative', base: 70, pref: 'dirt'),
      racer_hash(id: 'grass', name: 'Turf', strategy: 'balanced', base: 78, pref: 'grass')
    ]
    srand(29)
    sim = RaceSimulator.new(race_id: 'strat-mid', track: track, racers: racers)
    allow(sim).to receive(:check_injury)

    max_gap = 0
    target = sim.total_distance * 0.50
    6000.times do |i|
      sim.instance_variable_set(:@tick_count, i)
      sim.send(:tick, i * RaceSimulator::UPDATE_INTERVAL_MS)
      g = gap_laps(sim)
      max_gap = g if g > max_gap
      break if sim.racers.map(&:total_distance).min >= target || sim.is_finished
    end
    expect(max_gap).to be < 0.12

    r = by_id(sim)
    lead = sim.racers.map(&:total_distance).max
    con_back = (lead - r['slow'].total_distance) / track.length.to_f
    expect(con_back).to be < 0.12
    # Conservative is in the pack, not ahead by a break-sized gap.
    con_lead = (r['slow'].total_distance - sim.racers.map(&:total_distance).min) / track.length.to_f
    expect(con_lead).to be < 0.08 if r['slow'].position == 1
  end

  it 'lets a fresh conservative charge past balanced and gassed aggressive in the last 20%' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    srand(13)
    sim = RaceSimulator.new(race_id: 'strat-late', track: track, racers: identical_field)
    allow(sim).to receive(:check_injury)

    late = sim.total_distance * 0.80
    run_until(sim, ->(s) { s.racers.map(&:total_distance).max >= late })

    r0 = by_id(sim)
    expect(r0['con'].health).to be > r0['agg'].health
    expect(r0['con'].health).to be > 40

    start = {
      'agg' => r0['agg'].total_distance,
      'bal' => r0['bal'].total_distance,
      'con' => r0['con'].total_distance
    }
    450.times do |j|
      i = sim.tick_count + 1 + j
      sim.instance_variable_set(:@tick_count, i)
      sim.send(:tick, i * RaceSimulator::UPDATE_INTERVAL_MS)
    end
    r1 = by_id(sim)
    agg_gain = r1['agg'].total_distance - start['agg']
    bal_gain = r1['bal'].total_distance - start['bal']
    con_gain = r1['con'].total_distance - start['con']
    expect(con_gain).to be > agg_gain
    expect(con_gain).to be > bal_gain
    # Balanced late must not look like a closer charge vs conservative.
    expect(bal_gain).to be < con_gain * 0.90
    expect(r1['con'].current_speed).to be > r1['bal'].current_speed
    expect(r1['con'].current_speed).to be > r1['agg'].current_speed
  end
end
