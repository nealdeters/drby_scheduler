require_relative '../../lib/simulator/race_simulator'
require_relative '../../lib/models'

RSpec.describe RaceSimulator do
  let(:track) { Models::Track.new(id: 't1', name: 'Test Track', surface: 'asphalt', length: 1000, laps: 3) }
  let(:racers) do
    [
      { 'id' => 'r1', 'name' => 'Racer 1', 'color' => '#FF0000', 'baseSpeed' => 80, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'asphalt', 'acceleration' => 50, 'endurance' => 50, 'consistency' => 50, 'staminaRecovery' => 50 },
      { 'id' => 'r2', 'name' => 'Racer 2', 'color' => '#00FF00', 'baseSpeed' => 85, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'asphalt', 'acceleration' => 60, 'endurance' => 40, 'consistency' => 50, 'staminaRecovery' => 50 }
    ]
  end

  describe '#initialize' do
    it 'creates a simulator with the given race id' do
      simulator = described_class.new(race_id: 'race-1', track: track, racers: racers)
      expect(simulator.race_id).to eq('race-1')
    end

    it 'initializes racers correctly' do
      simulator = described_class.new(race_id: 'race-1', track: track, racers: racers)
      expect(simulator.racers.length).to eq(2)
      expect(simulator.racers.all?(&:active?)).to be true
    end

    it 'marks unhealthy racers as DNF' do
      unhealthy_racers = [
        racers[0].merge('health' => 50),
        racers[1].merge('health' => 55)
      ]
      simulator = described_class.new(race_id: 'race-1', track: track, racers: unhealthy_racers)
      expect(simulator.racers.length).to eq(0)
    end

    it 'calculates total distance from track' do
      simulator = described_class.new(race_id: 'race-1', track: track, racers: racers)
      expect(simulator.total_distance).to eq(3000)
    end
  end

  describe '#needs_continuation?' do
    it 'returns false initially' do
      simulator = described_class.new(race_id: 'race-1', track: track, racers: racers)
      expect(simulator.needs_continuation?).to be false
    end
  end
end
