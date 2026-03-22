require_relative '../../lib/models/racer'

RSpec.describe Racer do
  describe '#initialize' do
    it 'creates a racer with default values' do
      racer = described_class.new(
        id: 'r1',
        name: 'Test Racer',
        color: '#FF0000'
      )

      expect(racer.id).to eq('r1')
      expect(racer.name).to eq('Test Racer')
      expect(racer.color).to eq('#FF0000')
      expect(racer.health).to eq(100)
      expect(racer.status).to eq('waiting')
      expect(racer.progress).to eq(0)
    end

    it 'creates a racer with custom values' do
      racer = described_class.new(
        id: 'r1',
        name: 'Test Racer',
        color: '#FF0000',
        base_speed: 85,
        health: 75,
        strategy: 'aggressive',
        acceleration: 80
      )

      expect(racer.base_speed).to eq(85)
      expect(racer.health).to eq(75)
      expect(racer.strategy).to eq('aggressive')
      expect(racer.acceleration).to eq(80)
    end
  end

  describe '#from_hash' do
    it 'creates a racer from a hash' do
      hash = {
        'id' => 'r1',
        'name' => 'Test Racer',
        'color' => '#FF0000',
        'baseSpeed' => 85,
        'health' => 75,
        'strategy' => 'aggressive'
      }

      racer = described_class.from_hash(hash)

      expect(racer.id).to eq('r1')
      expect(racer.name).to eq('Test Racer')
      expect(racer.health).to eq(75)
    end
  end

  describe '#to_h' do
    it 'converts racer to hash' do
      racer = described_class.new(
        id: 'r1',
        name: 'Test Racer',
        color: '#FF0000',
        base_speed: 85
      )

      hash = racer.to_h

      expect(hash['id']).to eq('r1')
      expect(hash['name']).to eq('Test Racer')
      expect(hash['baseSpeed']).to eq(85)
    end
  end

  describe '#can_race?' do
    it 'returns true when health > 60' do
      racer = described_class.new(id: 'r1', name: 'Test', color: '#FF0000', health: 70)
      expect(racer.can_race?).to be true
    end

    it 'returns false when health <= 60' do
      racer = described_class.new(id: 'r1', name: 'Test', color: '#FF0000', health: 60)
      expect(racer.can_race?).to be false
    end

    it 'returns false when health < 60' do
      racer = described_class.new(id: 'r1', name: 'Test', color: '#FF0000', health: 50)
      expect(racer.can_race?).to be false
    end
  end

  describe '#active?' do
    it 'returns true when status is active' do
      racer = described_class.new(id: 'r1', name: 'Test', color: '#FF0000')
      racer.status = 'active'
      expect(racer.active?).to be true
    end

    it 'returns false when status is not active' do
      racer = described_class.new(id: 'r1', name: 'Test', color: '#FF0000')
      racer.status = 'finished'
      expect(racer.active?).to be false
    end
  end
end
