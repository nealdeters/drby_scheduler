require_relative '../../lib/scheduler/season_scheduler'
require_relative '../../lib/models'

RSpec.describe SeasonScheduler do
  let(:mock_storage) do
    double('storage').tap do |s|
      allow(s).to receive(:get_schedule) { nil }
      allow(s).to receive(:save_schedule) { true }
      allow(s).to receive(:get_standings) { {} }
      allow(s).to receive(:save_standings) { true }
      allow(s).to receive(:get_roster) { [] }
      allow(s).to receive(:save_roster) { true }
      allow(s).to receive(:get_tracks) { nil }
      allow(s).to receive(:save_tracks) { true }
      allow(s).to receive(:get_completed_seasons) { [] }
      allow(s).to receive(:save_completed_seasons) { true }
      allow(s).to receive(:get_season_number) { 1 }
      allow(s).to receive(:save_season_number) { true }
    end
  end

  let(:roster_data) do
    [
      { 'id' => 'r1', 'name' => 'Racer 1', 'color' => '#FF0000', 'baseSpeed' => 80, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'asphalt', 'acceleration' => 50, 'endurance' => 50, 'consistency' => 50, 'staminaRecovery' => 50 },
      { 'id' => 'r2', 'name' => 'Racer 2', 'color' => '#00FF00', 'baseSpeed' => 85, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'dirt', 'acceleration' => 60, 'endurance' => 40, 'consistency' => 50, 'staminaRecovery' => 50 },
      { 'id' => 'r3', 'name' => 'Racer 3', 'color' => '#0000FF', 'baseSpeed' => 75, 'health' => 100, 'strategy' => 'conservative', 'trackPreference' => 'asphalt', 'acceleration' => 40, 'endurance' => 60, 'consistency' => 60, 'staminaRecovery' => 60 }
    ]
  end

  before do
    allow(mock_storage).to receive(:get_roster).and_return(roster_data)
  end

  describe '#load' do
    it 'loads roster from storage' do
      scheduler = described_class.new(storage_service: mock_storage).load
      expect(scheduler.roster.length).to eq(3)
    end

    it 'loads default tracks' do
      scheduler = described_class.new(storage_service: mock_storage).load
      expect(scheduler.tracks.length).to eq(5)
    end
  end

  describe '#generate_schedule' do
    it 'generates 1008 races' do
      scheduler = described_class.new(storage_service: mock_storage).load
      expect(scheduler.schedule.length).to eq(1008)
    end

    it 'sets correct start time to nearest 10-minute boundary' do
      scheduler = described_class.new(storage_service: mock_storage).load
      first_race = scheduler.schedule.first
      start_time = Time.at(first_race.start_time / 1000)
      expect(start_time.min % 10).to eq(0)
      expect(start_time.sec).to eq(0)
    end

    it 'assigns racers to each race' do
      scheduler = described_class.new(storage_service: mock_storage).load
      scheduler.schedule.each do |race|
        expect(race.racer_ids.length).to be_between(1, roster_data.length)
      end
    end
  end

  describe '#complete_race' do
    it 'marks race as completed' do
      scheduler = described_class.new(storage_service: mock_storage).load
      race_id = scheduler.schedule.first.id
      results = [Models::Racer.from_hash(roster_data[0])]
      
      scheduler.complete_race(race_id, results, { 'r1' => 5000 })
      
      completed_race = scheduler.schedule.find { |r| r.id == race_id }
      expect(completed_race.completed).to be true
    end
  end

  describe '#update_standings_from_results' do
    it 'awards 5 points to first place' do
      scheduler = described_class.new(storage_service: mock_storage).load
      results = [Models::Racer.from_hash(roster_data[0])]
      
      scheduler.update_standings_from_results(results)
      
      expect(scheduler.standings['r1']).to eq(5)
    end

    it 'awards 3 points to second place' do
      scheduler = described_class.new(storage_service: mock_storage).load
      results = [
        Models::Racer.from_hash(roster_data[0]),
        Models::Racer.from_hash(roster_data[1])
      ]
      
      scheduler.update_standings_from_results(results)
      
      expect(scheduler.standings['r1']).to eq(5)
      expect(scheduler.standings['r2']).to eq(3)
    end

    it 'awards 1 point to third place' do
      scheduler = described_class.new(storage_service: mock_storage).load
      results = [
        Models::Racer.from_hash(roster_data[0]),
        Models::Racer.from_hash(roster_data[1]),
        Models::Racer.from_hash(roster_data[2])
      ]
      
      scheduler.update_standings_from_results(results)
      
      expect(scheduler.standings['r1']).to eq(5)
      expect(scheduler.standings['r2']).to eq(3)
      expect(scheduler.standings['r3']).to eq(1)
    end
  end
end
