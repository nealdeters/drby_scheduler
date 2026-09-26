require_relative '../../lib/simulator/race_simulator'
require_relative '../../lib/models'

RSpec.describe 'inside-line traffic and passing' do
  def racer_hash(id:, base:, acceleration: 50, health: 100, lane: nil)
    {
      'id' => id,
      'name' => id,
      'color' => '#ffffff',
      'baseSpeed' => base,
      'health' => health,
      'strategy' => 'balanced',
      'trackPreference' => 'asphalt',
      'acceleration' => acceleration,
      'endurance' => 50,
      'consistency' => 100,
      'staminaRecovery' => 50,
      'lane' => lane
    }
  end

  def simulator(racers)
    track = Models::Track.new(id: 't1', name: 'Oval', surface: 'asphalt', length: 1000, laps: 2)
    RaceSimulator.new(race_id: 'traffic', track: track, racers: racers)
  end

  it 'moves an unobstructed horse toward the inside line one lane at a time' do
    sim = simulator([
      racer_hash(id: 'inside', base: 80),
      racer_hash(id: 'outer', base: 80),
      racer_hash(id: 'far-outer', base: 80)
    ])
    sim.racers[1].total_distance = 100
    sim.racers[2].total_distance = 200

    sim.send(:choose_lanes)
    expect(sim.racers[1].lane).to eq(1)
    expect(sim.racers[2].lane).to eq(2)
  end

  it 'goes around a slower horse instead of advancing through it' do
    sim = simulator([
      racer_hash(id: 'leader', base: 70),
      racer_hash(id: 'trailer', base: 95, acceleration: 100)
    ])
    leader, trailer = sim.racers
    leader.lane = 1
    trailer.lane = 1
    leader.total_distance = 30
    trailer.total_distance = 10
    leader.current_speed = 0.7
    trailer.current_speed = 0.95

    sim.send(:choose_lanes)
    expect(trailer.lane).to eq(2)
    expect(sim.send(:capped_course_step, trailer, 5)).to eq(5)
  end

  it 'keeps a committed passer outside until its nose clears the target' do
    sim = simulator([
      racer_hash(id: 'inside-leader', base: 80),
      racer_hash(id: 'outer-passer', base: 95, acceleration: 100)
    ])
    leader, passer = sim.racers
    leader.lane = 1
    passer.lane = 1
    leader.total_distance = 100
    passer.total_distance = 90

    sim.send(:choose_lanes)
    expect(passer.lane).to eq(2)
    expect(passer.passing_target_id).to eq('inside-leader')

    passer.total_distance = 105
    sim.send(:choose_lanes)
    expect(passer.lane).to eq(2)

    passer.total_distance = 119
    sim.send(:choose_lanes)
    expect(passer.lane).to eq(1)
    expect(passer.passing_target_id).to be_nil
  end

  it 'holds an outer lane until it has cleared the inside obstruction' do
    sim = simulator([
      racer_hash(id: 'inside-leader', base: 80),
      racer_hash(id: 'outer-passer', base: 95, acceleration: 100)
    ])
    leader, passer = sim.racers
    leader.lane = 1
    passer.lane = 2
    leader.total_distance = 100
    passer.total_distance = 90

    sim.send(:choose_lanes)
    expect(passer.lane).to eq(2)

    passer.total_distance = 130
    sim.send(:choose_lanes)
    expect(passer.lane).to eq(1)
  end

  it 'holds a horse behind the obstruction when it lacks passing push' do
    sim = simulator([
      racer_hash(id: 'leader', base: 80),
      racer_hash(id: 'tired', base: 70, acceleration: 0, health: 20)
    ])
    leader, trailer = sim.racers
    leader.lane = 1
    trailer.lane = 1
    leader.total_distance = 30
    trailer.total_distance = 10
    leader.current_speed = 0.8

    sim.send(:choose_lanes)
    expect(trailer.lane).to eq(1)
    expect(sim.send(:capped_course_step, trailer, 10)).to eq(8.0)
  end

  it 'never lets two active horses overlap in the same lane' do
    sim = simulator([
      racer_hash(id: 'a', base: 92, acceleration: 100),
      racer_hash(id: 'b', base: 84, acceleration: 70),
      racer_hash(id: 'c', base: 76, acceleration: 40),
      racer_hash(id: 'd', base: 68, acceleration: 20)
    ])

    500.times do |tick|
      sim.instance_variable_set(:@tick_count, tick)
      sim.send(:tick, tick * RaceSimulator::UPDATE_INTERVAL_MS)
      sim.racers.select(&:active?).group_by(&:lane).each_value do |horses|
        distances = horses.map(&:total_distance).sort.reverse
        distances.each_cons(2) do |front, behind|
          expect(front - behind).to be >= RaceSimulator::HORSE_LENGTH_M - 1e-9
        end
      end
    end
  end

  it 'records the longer physical path while using an outer lane' do
    sim = simulator([racer_hash(id: 'outer', base: 80)])
    expect(sim.send(:lane_path_ratio, 2)).to be > 1.0

    racer = sim.racers.first
    racer.lane = 2
    sim.instance_variable_set(:@tick_count, 0)
    sim.send(:process_racer_tick, racer, 0)

    expect(racer.travel_distance).to be > racer.total_distance
  end
end
