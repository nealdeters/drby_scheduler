require_relative '../../lib/scheduler/season_scheduler'
require_relative '../../lib/models'

RSpec.describe 'Recovery and rest-vs-gamble entry' do
  let(:mock_storage) do
    double('storage').tap do |s|
      allow(s).to receive(:get_schedule).and_return(nil)
      allow(s).to receive(:save_schedule).and_return(true)
      allow(s).to receive(:get_standings).and_return({})
      allow(s).to receive(:save_standings).and_return(true)
      allow(s).to receive(:get_roster).and_return([])
      allow(s).to receive(:save_roster).and_return(true)
      allow(s).to receive(:get_tracks).and_return(nil)
      allow(s).to receive(:get_completed_seasons).and_return([])
      allow(s).to receive(:save_completed_seasons).and_return(true)
      allow(s).to receive(:get_season_number).and_return(1)
      allow(s).to receive(:save_season_number).and_return(true)
      allow(s).to receive(:get_all_racers).and_return(roster_data)
      allow(s).to receive(:get_all_tracks).and_return(tracks_data)
      allow(s).to receive(:set_blob).and_return(true)
    end
  end

  let(:roster_data) do
    [
      { 'id' => 'r1', 'name' => 'Racer 1', 'color' => '#FF0000', 'baseSpeed' => 80, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'asphalt', 'acceleration' => 50, 'endurance' => 50, 'consistency' => 50, 'staminaRecovery' => 50 },
      { 'id' => 'r2', 'name' => 'Racer 2', 'color' => '#00FF00', 'baseSpeed' => 85, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'dirt', 'acceleration' => 60, 'endurance' => 40, 'consistency' => 50, 'staminaRecovery' => 50 },
      { 'id' => 'r3', 'name' => 'Racer 3', 'color' => '#0000FF', 'baseSpeed' => 75, 'health' => 100, 'strategy' => 'conservative', 'trackPreference' => 'asphalt', 'acceleration' => 40, 'endurance' => 60, 'consistency' => 60, 'staminaRecovery' => 80 },
      { 'id' => 'r4', 'name' => 'Racer 4', 'color' => '#FFFF00', 'baseSpeed' => 78, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'dirt', 'acceleration' => 55, 'endurance' => 55, 'consistency' => 50, 'staminaRecovery' => 40 },
      { 'id' => 'r5', 'name' => 'Racer 5', 'color' => '#FF00FF', 'baseSpeed' => 82, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'asphalt', 'acceleration' => 70, 'endurance' => 35, 'consistency' => 40, 'staminaRecovery' => 45 },
      { 'id' => 'r6', 'name' => 'Racer 6', 'color' => '#00FFFF', 'baseSpeed' => 77, 'health' => 100, 'strategy' => 'conservative', 'trackPreference' => 'grass', 'acceleration' => 45, 'endurance' => 70, 'consistency' => 65, 'staminaRecovery' => 70 }
    ]
  end

  let(:tracks_data) do
    [
      { 'id' => 't1', 'name' => 'Asphalt Park', 'surface' => 'asphalt', 'length' => 1000, 'laps' => 3 },
      { 'id' => 't2', 'name' => 'Dirt Dome', 'surface' => 'dirt', 'length' => 1000, 'laps' => 3 }
    ]
  end

  def build_scheduler
    described = SeasonScheduler.new(storage_service: mock_storage, racers_storage: mock_storage, tracks_storage: mock_storage)
    # Avoid generating 1008 races — stub schedule load with empty then inject roster/tracks
    allow(mock_storage).to receive(:get_schedule).and_return([])
    sch = described.load
    sch
  end

  describe 'sit recovery' do
    it 'never restores 0 to 100 in a single sit' do
      sch = build_scheduler
      wiped = sch.roster.first
      wiped.health = 0

      # Only this racer sits; pretend others raced so update path hits the else branch for wiped
      raced = sch.roster[1]
      raced.health = 40
      sch.update_racer_health([raced])

      expect(wiped.health).to be <= SeasonScheduler::SIT_RECOVERY_CAP
      expect(wiped.health).to be < 100
      expect(wiped.health).to be >= SeasonScheduler::SIT_RECOVERY_BASE
    end

    it 'needs multiple sits to climb from wiped to fresh' do
      sch = build_scheduler
      horse = sch.roster.first
      horse.health = 0
      sits = 0
      while horse.health < 100 && sits < 20
        raced = sch.roster[1]
        sch.update_racer_health([raced])
        sits += 1
      end
      expect(sits).to be >= 4
      expect(horse.health).to eq(100)
    end

    it 'keeps residual fatigue after a race finish (no free full recovery)' do
      sch = build_scheduler
      horse = sch.roster.first
      horse.health = 100
      finished = Models::Racer.from_hash(horse.to_h.merge('health' => 5, 'status' => 'finished'))
      sch.update_racer_health([finished])
      expect(sch.roster.first.health).to be < 5
      expect(sch.roster.first.health).to be >= 0
    end
  end

  describe 'rest vs gamble' do
    it 'gives healthy horses positive entry desire' do
      sch = build_scheduler
      track = Models::Track.from_hash(tracks_data[0])
      horse = sch.roster.find { |r| r.track_preference == 'asphalt' }
      horse.health = 95
      expect(sch.entry_desire(horse, track)).to be > 0.5
    end

    it 'usually prefers rest when health is very low' do
      sch = build_scheduler
      track = Models::Track.from_hash(tracks_data[1]) # dirt — mismatch for asphalt horse
      horse = sch.roster.find { |r| r.track_preference == 'asphalt' }
      horse.health = 20
      # Keep other horses healthy so soft-field gamble does not fire
      sch.roster.each { |r| r.health = 90 unless r.id == horse.id }
      desire = sch.entry_desire(horse, track)
      expect(desire).to be < 0
    end

    it 'selects a field within size bounds' do
      sch = build_scheduler
      track = Models::Track.from_hash(tracks_data[0])
      field = sch.select_field(track, 4)
      expect(field.length).to eq(4)
      expect(field.map(&:id).uniq.length).to eq(4)
    end
  end

  describe 'roster persistence' do
    it 'writes individual racer blobs so health does not snap back to 100' do
      sch = build_scheduler
      sch.roster.first.health = 33
      written = []
      allow(mock_storage).to receive(:set_blob) { |id, payload| written << [id, payload]; true }
      sch.send(:save_roster)
      match = written.find { |id, _| id == 'r1' }
      expect(match).not_to be_nil
      expect(match[1]['health']).to eq(33)
    end
  end
end
