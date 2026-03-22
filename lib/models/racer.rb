class Racer
  attr_reader :id, :name, :color, :base_speed, :track_preference, :acceleration,
              :endurance, :consistency, :stamina_recovery

  attr_accessor :health, :strategy, :lane, :progress, :laps, :total_distance,
                :status, :current_speed, :finish_time, :position

  STRATEGIES = %w[aggressive conservative balanced].freeze
  SURFACES = %w[asphalt dirt grass].freeze

  def initialize(id:, name:, color:, base_speed: 80, health: 100,
                 strategy: 'balanced', track_preference: 'asphalt',
                 acceleration: 50, endurance: 50, consistency: 50,
                 stamina_recovery: 50)
    @id = id
    @name = name
    @color = color
    @base_speed = base_speed
    @health = health
    @strategy = strategy
    @track_preference = track_preference
    @acceleration = acceleration
    @endurance = endurance
    @consistency = consistency
    @stamina_recovery = stamina_recovery

    @lane = 0
    @progress = 0
    @laps = 0
    @total_distance = 0
    @status = 'waiting'
    @current_speed = 0
    @finish_time = nil
    @position = nil
  end

  def self.from_hash(hash)
    new(
      id: hash['id'],
      name: hash['name'],
      color: hash['color'],
      base_speed: hash['baseSpeed'],
      health: hash['health'],
      strategy: hash['strategy'],
      track_preference: hash['trackPreference'],
      acceleration: hash['acceleration'],
      endurance: hash['endurance'],
      consistency: hash['consistency'],
      stamina_recovery: hash['staminaRecovery']
    )
  end

  def to_h
    {
      'id' => id,
      'name' => name,
      'color' => color,
      'baseSpeed' => base_speed,
      'health' => health,
      'strategy' => strategy,
      'trackPreference' => track_preference,
      'acceleration' => acceleration,
      'endurance' => endurance,
      'consistency' => consistency,
      'staminaRecovery' => stamina_recovery,
      'lane' => lane,
      'progress' => progress,
      'laps' => laps,
      'totalDistance' => total_distance,
      'status' => status,
      'currentSpeed' => current_speed,
      'finishTime' => finish_time,
      'position' => position
    }
  end

  def active?
    status == 'active'
  end

  def dnf?
    status == 'dnf'
  end

  def finished?
    status == 'finished'
  end

  def can_race?
    health > 60
  end
end
