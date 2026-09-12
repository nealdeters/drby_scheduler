require_relative '../../lib/simulator/race_simulator'
require_relative '../../lib/models'

RSpec.describe 'Race pack margins' do
  def racer_hash(id:, name:, base:, pref:, strategy: 'balanced', health: 100)
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

  def run_ticks(sim, n)
    n.times do |i|
      sim.instance_variable_set(:@tick_count, i)
      sim.send(:tick, i * RaceSimulator::UPDATE_INTERVAL_MS)
    end
  end

  def gap_laps(sim)
    dists = sim.racers.reject { |r| %w[injured dnf].include?(r.status) }.map(&:total_distance)
    return 0 if dists.empty?
    (dists.max - dists.min) / sim.track.length.to_f
  end

  it 'keeps a mixed-speed asphalt field in a watchable bunch' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 3)
    racers = [
      racer_hash(id: 'fast', name: 'Fast', base: 92, pref: 'asphalt', strategy: 'aggressive'),
      racer_hash(id: 'mid', name: 'Mid', base: 80, pref: 'asphalt'),
      racer_hash(id: 'slow', name: 'Slow', base: 70, pref: 'dirt', strategy: 'conservative'),
      racer_hash(id: 'grass', name: 'Turf', base: 78, pref: 'grass')
    ]
    srand(29)
    sim = RaceSimulator.new(race_id: 'pack-1', track: track, racers: racers)
    allow(sim).to receive(:check_injury)
    max_gap = 0
    5200.times do |i|
      sim.instance_variable_set(:@tick_count, i)
      sim.send(:tick, i * RaceSimulator::UPDATE_INTERVAL_MS)
      g = gap_laps(sim)
      max_gap = g if g > max_gap
      break if sim.is_finished
    end
    expect(sim.is_finished).to be true
    expect(max_gap).to be < 0.12
    finish_ms = sim.racers.map { |r| r.finish_time }.compact
    expect(finish_ms.length).to eq(4)
    spread = finish_ms.max - finish_ms.min
    expect(spread).to be < 4_000
    expect(spread).to be > 200
  end

  it 'does not let a mismatched trailer fall a lap behind mid-race' do
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 2)
    racers = [
      racer_hash(id: 'a', name: 'A', base: 88, pref: 'asphalt'),
      racer_hash(id: 'b', name: 'B', base: 72, pref: 'grass', health: 70)
    ]
    srand(7)
    sim = RaceSimulator.new(race_id: 'pack-2', track: track, racers: racers)
    allow(sim).to receive(:check_injury)
    2500.times do |i|
      sim.instance_variable_set(:@tick_count, i)
      sim.send(:tick, i * RaceSimulator::UPDATE_INTERVAL_MS)
      expect(gap_laps(sim)).to be < 0.15
      break if sim.is_finished
    end
  end
end
