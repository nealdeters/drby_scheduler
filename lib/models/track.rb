class Track
  attr_reader :id, :name, :surface, :length, :laps

  def initialize(id:, name:, surface:, length:, laps:)
    @id = id
    @name = name
    @surface = surface
    @length = length
    @laps = laps
  end

  def self.from_hash(hash)
    new(
      id: hash['id'],
      name: hash['name'],
      surface: hash['surface'],
      length: hash['length'],
      laps: hash['laps']
    )
  end

  def to_h
    {
      'id' => id,
      'name' => name,
      'surface' => surface,
      'length' => length,
      'laps' => laps
    }
  end

  def total_distance
    length * laps
  end
end
