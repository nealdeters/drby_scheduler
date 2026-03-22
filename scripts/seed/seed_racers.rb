#!/usr/bin/env ruby

require 'dotenv/load'
require_relative '../../lib/services/seed_service'

class SeedRacers
  include SeedService

  RACERS = [
    { 'id' => 'r1', 'name' => 'Lightning Bolt', 'color' => '#FF6B6B', 'baseSpeed' => 88, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'asphalt', 'lane' => 0, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 85, 'endurance' => 48, 'consistency' => 35, 'staminaRecovery' => 52 },
    { 'id' => 'r2', 'name' => 'Mud Slinger', 'color' => '#8B4513', 'baseSpeed' => 76, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'dirt', 'lane' => 1, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 78, 'endurance' => 45, 'consistency' => 40, 'staminaRecovery' => 48 },
    { 'id' => 'r3', 'name' => 'Green Machine', 'color' => '#22C55E', 'baseSpeed' => 82, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'grass', 'lane' => 2, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 60, 'endurance' => 58, 'consistency' => 62, 'staminaRecovery' => 55 },
    { 'id' => 'r4', 'name' => 'Silver Streak', 'color' => '#94A3B8', 'baseSpeed' => 86, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'asphalt', 'lane' => 3, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 65, 'endurance' => 62, 'consistency' => 55, 'staminaRecovery' => 68 },
    { 'id' => 'r5', 'name' => 'Thunder Bird', 'color' => '#F59E0B', 'baseSpeed' => 90, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'asphalt', 'lane' => 4, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 88, 'endurance' => 42, 'consistency' => 32, 'staminaRecovery' => 45 },
    { 'id' => 'r6', 'name' => 'Dirt Devil', 'color' => '#A0522D', 'baseSpeed' => 72, 'health' => 100, 'strategy' => 'conservative', 'trackPreference' => 'dirt', 'lane' => 5, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 38, 'endurance' => 82, 'consistency' => 78, 'staminaRecovery' => 70 },
    { 'id' => 'r7', 'name' => 'Road Runner', 'color' => '#3B82F6', 'baseSpeed' => 84, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'asphalt', 'lane' => 6, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 58, 'endurance' => 55, 'consistency' => 68, 'staminaRecovery' => 60 },
    { 'id' => 'r8', 'name' => 'Turbo Turtle', 'color' => '#10B981', 'baseSpeed' => 70, 'health' => 100, 'strategy' => 'conservative', 'trackPreference' => 'grass', 'lane' => 7, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 32, 'endurance' => 88, 'consistency' => 85, 'staminaRecovery' => 78 },
    { 'id' => 'r9', 'name' => 'Midnight Runner', 'color' => '#1E293B', 'baseSpeed' => 80, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'asphalt', 'lane' => 0, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 55, 'endurance' => 60, 'consistency' => 58, 'staminaRecovery' => 52 },
    { 'id' => 'r10', 'name' => 'Red Rocket', 'color' => '#EF4444', 'baseSpeed' => 90, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'asphalt', 'lane' => 1, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 92, 'endurance' => 40, 'consistency' => 30, 'staminaRecovery' => 42 },
    { 'id' => 'r11', 'name' => 'Yellow Jacket', 'color' => '#EAB308', 'baseSpeed' => 75, 'health' => 100, 'strategy' => 'conservative', 'trackPreference' => 'dirt', 'lane' => 2, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 42, 'endurance' => 78, 'consistency' => 72, 'staminaRecovery' => 65 },
    { 'id' => 'r12', 'name' => 'Purple Passion', 'color' => '#8B5CF6', 'baseSpeed' => 82, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'grass', 'lane' => 3, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 62, 'endurance' => 58, 'consistency' => 52, 'staminaRecovery' => 68 },
    { 'id' => 'r13', 'name' => 'Blue Thunder', 'color' => '#06B6D4', 'baseSpeed' => 85, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'asphalt', 'lane' => 4, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 68, 'endurance' => 52, 'consistency' => 60, 'staminaRecovery' => 58 },
    { 'id' => 'r14', 'name' => 'Iron Horse', 'color' => '#78716C', 'baseSpeed' => 72, 'health' => 100, 'strategy' => 'conservative', 'trackPreference' => 'dirt', 'lane' => 5, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 35, 'endurance' => 85, 'consistency' => 82, 'staminaRecovery' => 75 },
    { 'id' => 'r15', 'name' => 'Pink Panther', 'color' => '#EC4899', 'baseSpeed' => 83, 'health' => 100, 'strategy' => 'balanced', 'trackPreference' => 'grass', 'lane' => 6, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 58, 'endurance' => 65, 'consistency' => 55, 'staminaRecovery' => 62 },
    { 'id' => 'r16', 'name' => 'Golden Boy', 'color' => '#FCD34D', 'baseSpeed' => 88, 'health' => 100, 'strategy' => 'aggressive', 'trackPreference' => 'asphalt', 'lane' => 7, 'progress' => 0, 'laps' => 0, 'totalDistance' => 0, 'status' => 'waiting', 'currentSpeed' => 0, 'acceleration' => 80, 'endurance' => 52, 'consistency' => 38, 'staminaRecovery' => 55 }
  ].freeze

  def initialize
    super(store_name: 'site:racers')
    @data = RACERS
    @data_name = 'roster'
  end

  def data_label
    'racers'
  end
end

if __FILE__ == $0
  SeedRacers.new.run
end
