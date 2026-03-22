require_relative '../../lib/models/track'

RSpec.describe Track do
  describe '#initialize' do
    it 'creates a track with given values' do
      track = described_class.new(
        id: 't1',
        name: 'Test Track',
        surface: 'asphalt',
        length: 1500,
        laps: 5
      )

      expect(track.id).to eq('t1')
      expect(track.name).to eq('Test Track')
      expect(track.surface).to eq('asphalt')
      expect(track.length).to eq(1500)
      expect(track.laps).to eq(5)
    end
  end

  describe '#from_hash' do
    it 'creates a track from a hash' do
      hash = {
        'id' => 't1',
        'name' => 'Test Track',
        'surface' => 'dirt',
        'length' => 1200,
        'laps' => 4
      }

      track = described_class.from_hash(hash)

      expect(track.id).to eq('t1')
      expect(track.surface).to eq('dirt')
      expect(track.length).to eq(1200)
    end
  end

  describe '#to_h' do
    it 'converts track to hash' do
      track = described_class.new(
        id: 't1',
        name: 'Test Track',
        surface: 'asphalt',
        length: 1500,
        laps: 5
      )

      hash = track.to_h

      expect(hash['id']).to eq('t1')
      expect(hash['name']).to eq('Test Track')
      expect(hash['surface']).to eq('asphalt')
    end
  end

  describe '#total_distance' do
    it 'calculates total distance correctly' do
      track = described_class.new(
        id: 't1',
        name: 'Test Track',
        surface: 'asphalt',
        length: 1500,
        laps: 5
      )

      expect(track.total_distance).to eq(7500)
    end
  end
end
