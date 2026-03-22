require_relative 'season_scheduler'
require_relative 'race_simulator'
require_relative 'orchestrator'

module Scheduler
  SeasonScheduler = ::SeasonScheduler
  RaceSimulator = ::RaceSimulator
  RaceOrchestrator = ::RaceOrchestrator
end
