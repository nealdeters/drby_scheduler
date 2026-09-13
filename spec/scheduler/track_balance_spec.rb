require_relative '../../lib/scheduler/season_scheduler'
require_relative '../../lib/models'

RSpec.describe 'Season 3+ track rotation' do
  let(:roster_data) do
    prefs = %w[asphalt asphalt asphalt asphalt asphalt asphalt asphalt asphalt dirt dirt dirt dirt grass grass grass grass]
    names = [
      'Lightning Bolt', 'Kenny', 'Thunder Bird', 'Road Runner',
      'Frederico', "Carmella's Dream", 'Blue Thunder', 'Golden Boy',
      'Mud Slinger', 'Dirt Devil', 'Yellow Jacket', 'Iron Horse',
      'Green Machine', 'Turbo Turtle', 'Purple Passion', 'Spiral Ham'
    ]
    names.each_with_index.map do |name, i|
      {
        'id' => "r#{i + 1}",
        'name' => name,
        'color' => '#ffffff',
        'baseSpeed' => 80,
        'health' => 100,
        'strategy' => 'balanced',
        'trackPreference' => prefs[i],
        'acceleration' => 50,
        'endurance' => 50,
        'consistency' => 50,
        'staminaRecovery' => 50
      }
    end
  end

  let(:tracks_data) do
    [
      { 'id' => 't1', 'name' => 'Oval Circuit', 'surface' => 'asphalt', 'length' => 1000, 'laps' => 3 },
      { 'id' => 't2', 'name' => 'Dirt Derby', 'surface' => 'dirt', 'length' => 800, 'laps' => 5 },
      { 'id' => 't3', 'name' => 'Grasslands', 'surface' => 'grass', 'length' => 1200, 'laps' => 2 }
    ]
  end

  let(:mock_storage) do
    double('storage').tap do |s|
      allow(s).to receive(:get_schedule).and_return([])
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

  def build_scheduler(season:)
    sch = SeasonScheduler.new(storage_service: mock_storage, racers_storage: mock_storage, tracks_storage: mock_storage)
    sch.load
    sch.instance_variable_set(:@current_season, season)
    sch.instance_variable_set(:@schedule, [])
    sch
  end

  it 'keeps Spiral Ham off most oval fields in season 2 (affinity)' do
    sch = build_scheduler(season: 2)
    oval = Models::Track.from_hash(tracks_data[0])
    pink = 0
    40.times do
      field = sch.select_field(oval, 6)
      pink += 1 if field.any? { |r| r.id == 'r16' }
    end
    expect(pink).to be <= 8
  end

  it 'puts every horse including Spiral Ham on oval in season 3' do
    sch = build_scheduler(season: 3)
    oval = Models::Track.from_hash(tracks_data[0])
    seen = Hash.new(0)
    48.times do
      field = sch.select_field(oval, 6)
      field.each { |r| seen[r.id] += 1 }
      # Simulate completed so the next pick rebalances
      sch.schedule << Models::RaceEvent.new(
        id: "s3-test-#{sch.schedule.length}",
        start_time: 0,
        seed: 1,
        track: oval,
        racer_ids: field.map(&:id),
        completed: true
      )
    end
    roster_data.each do |row|
      expect(seen[row['id']]).to be >= 4
    end
    expect(seen['r16']).to be >= 4
  end

  it 'does not use track preference as an entry bonus in season 3' do
    sch = build_scheduler(season: 3)
    oval = Models::Track.from_hash(tracks_data[0])
    pink = sch.roster.find { |r| r.id == 'r16' }
    bolt = sch.roster.find { |r| r.id == 'r1' }
    pink.health = 90
    bolt.health = 90
    expect(sch.entry_desire(pink, oval)).to be_within(0.001).of(sch.entry_desire(bolt, oval))
  end
end
