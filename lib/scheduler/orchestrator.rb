require_relative '../models'
require_relative '../services'
require_relative 'season_scheduler'
require_relative 'race_simulator'

class RaceOrchestrator
  CHECK_INTERVAL_SECONDS = 10

  def initialize(ably_api_key:, netlify_site_id:, netlify_auth_token:)
    @storage = Services::NetlifyBlobsService.new(
      site_id: netlify_site_id,
      auth_token: netlify_auth_token
    )
    @ably = Services::AblyService.new(ably_api_key)
    @scheduler = SeasonScheduler.new(storage_service: @storage)
    @running = false
    @active_races = {}
  end

  def start
    puts "[Orchestrator] Starting DRBY Race Orchestrator..."
    @scheduler.load

    puts "[Orchestrator] Loaded season #{@scheduler.current_season}"
    puts "[Orchestrator] Schedule has #{@scheduler.schedule.length} races"
    puts "[Orchestrator] #{@scheduler.roster.length} racers in roster"

    @running = true
    main_loop
  end

  def stop
    puts "[Orchestrator] Stopping..."
    @running = false
  end

  private

  def main_loop
    while @running
      begin
        check_and_run_pending_races
        sleep(CHECK_INTERVAL_SECONDS)
      rescue => e
        puts "[Orchestrator] Error in main loop: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        sleep(CHECK_INTERVAL_SECONDS)
      end
    end
  end

  def check_and_run_pending_races
    now = Time.now.to_i * 1000

    pending_races = @scheduler.schedule.select do |race|
      !race.completed && race.start_time <= now && !@active_races[race.id]
    end

    pending_races.each do |race|
      run_race(race)
    end

    if pending_races.any?
      puts "[Orchestrator] Started #{pending_races.length} race(s)"
    end
  end

  def run_race(race_event)
    race_id = race_event.id
    track = race_event.track.is_a?(Models::Track) ? race_event.track : Models::Track.from_hash(race_event.track)

    racer_data = race_event.racer_ids.map do |racer_id|
      racer = @scheduler.roster.find { |r| r.id == racer_id }
      next nil unless racer

      racer.to_h
    end.compact

    return unless racer_data.any?

    puts "[Orchestrator] Starting race #{race_id} on #{track.name}"

    simulator = RaceSimulator.new(
      race_id: race_id,
      track: track,
      racers: racer_data
    )

    @active_races[race_id] = simulator

    Thread.new do
      begin
        finished = simulator.run(
          ably_service: @ably,
          on_finish: ->(results) { handle_race_finished(race_id, results) }
        )

        unless finished
          puts "[Orchestrator] Race #{race_id} paused, will resume on next cycle"
        end
      rescue => e
        puts "[Orchestrator] Error running race #{race_id}: #{e.message}"
        puts e.backtrace.first(3).join("\n")
      ensure
        @active_races.delete(race_id)
      end
    end
  end

  def handle_race_finished(race_id, results)
    puts "[Orchestrator] Race #{race_id} finished!"

    race = @scheduler.schedule.find { |r| r.id == race_id }
    return unless race

    finish_times = results.each_with_object({}) do |racer, h|
      h[racer.id] = racer.finish_time if racer.finish_time
    end

    @scheduler.complete_race(race_id, results, finish_times)

    puts "[Orchestrator] Season #{@scheduler.current_season}: #{@scheduler.schedule.count(&:completed)}/#{@scheduler.schedule.length} races completed"
  end
end
