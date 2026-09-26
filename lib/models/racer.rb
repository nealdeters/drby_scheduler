class Racer
  attr_reader :id, :name, :color, :base_speed, :track_preference, :acceleration,
              :endurance, :consistency, :stamina_recovery, :lane

  attr_accessor :health, :strategy, :progress, :laps, :total_distance,
                :status, :current_speed, :finish_time, :position, :tick_count,
                :travel_distance, :passing_target_id, :lane_target, :lane_position,
                :lane_change, :lane_decision

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
    # Physical distance includes the extra path taken in an outer lane.
    @travel_distance = 0
    @passing_target_id = nil
    # lane is the committed target; lane_position is the physical lateral
    # position rendered by clients while a move is in progress.
    @lane_target = 0
    @lane_position = 0.0
    @lane_change = nil
    @lane_decision = nil
    @status = 'waiting'
    @current_speed = 0
    @finish_time = nil
    @position = nil
    @tick_count = 0
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
      'laneTarget' => lane_target || lane,
      'lanePosition' => lane_position || lane.to_f,
      'laneChange' => lane_change,
      'laneDecision' => lane_decision,
      'passingTargetId' => passing_target_id,
      'progress' => progress,
      'laps' => laps,
      'totalDistance' => total_distance,
      'travelDistance' => travel_distance,
      'status' => status,
      'currentSpeed' => current_speed,
      'finishTime' => finish_time,
      'position' => position,
      'tickCount' => tick_count
    }
  end

  # Test fixtures and legacy callers set lane directly. Keep the physical
  # position aligned for a direct assignment, but never override an active
  # server-owned transition.
  def lane=(value)
    @lane = value
    if !@lane_change && @lane_position.to_f.zero?
      @lane_position = value.to_f
    elsif !@lane_change && defined?(@previous_lane_for_assignment) && @previous_lane_for_assignment != value
      @lane_position = value.to_f
    end
    @previous_lane_for_assignment = value
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

  def is_finished?
    status == 'finished' || finish_time != nil
  end

  # Floor for starting a race. Depleted horses may still gamble in
  # (fatigue / injury risk bite hard); scheduler rest-vs-gamble decides who enters.
  MIN_RACE_HEALTH = 12

  def can_race?
    health.to_f > MIN_RACE_HEALTH
  end
end
