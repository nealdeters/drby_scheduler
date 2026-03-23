require_relative '../models'
require_relative '../services'
require_relative 'season_scheduler'
require_relative '../simulator/race_simulator'

class RaceOrchestrator
  CHECK_INTERVAL_SECONDS = 10

  def initialize(ably_api_key:, netlify_site_id:, netlify_auth_token:)
    @racers_storage = Services::NetlifyBlobsService.new(
      site_id: netlify_site_id,
      auth_token: netlify_auth_token,
      store_name: 'site:racers'
    )
    @tracks_storage = Services::NetlifyBlobsService.new(
      site_id: netlify_site_id,
      auth_token: netlify_auth_token,
      store_name: 'site:tracks'
    )
    @races_storage = Services::NetlifyBlobsService.new(
      site_id: netlify_site_id,
      auth_token: netlify_auth_token,
      store_name: 'site:races'
    )
    @ably = Services::AblyService.new(ably_api_key)
    @scheduler = SeasonScheduler.new(
      storage_service: @races_storage,
      racers_storage: @racers_storage,
      tracks_storage: @tracks_storage
    )
    @running = false
    @active_races = {}
  end

  def start
    puts "[Orchestrator] Starting DRBY Race Orchestrator..."
    @scheduler.load

    puts "[Orchestrator] Loaded season #{@scheduler.current_season}"
    puts "[Orchestrator] Schedule has #{@scheduler.schedule.length} races"
    puts "[Orchestrator] #{@scheduler.roster.length} racers in roster"

    recover_incomplete_races

    @running = true
    main_loop
  end

  def recover_incomplete_races
    now = Time.now.to_i * 1000
    
    incomplete_past_races = @scheduler.schedule.select do |race|
      !race.completed && race.start_time <= now
    end
    
    if incomplete_past_races.any?
      puts "[Orchestrator] Found #{incomplete_past_races.length} incomplete past races, marking as completed (no results - scheduler was not running)..."
      
      incomplete_past_races.each do |race|
        puts "[Orchestrator] Recovering race #{race.id} (started at #{Time.at(race.start_time / 1000)})"
        race.completed = true
        race.results = []
        race.finish_times = {}
      end
      
      @scheduler.save_schedule
      puts "[Orchestrator] Recovery complete. Schedule now has #{@scheduler.schedule.count(&:completed)} completed races."
    end
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
    puts "[Orchestrator] Race #{race_id} finished with #{results.length} results"
    
    if results.empty?
      puts "[Orchestrator] WARNING: Race #{race_id} finished with no results!"
    end

    race = @scheduler.schedule.find { |r| r.id == race_id }
    
    unless race
      puts "[Orchestrator] WARNING: Race #{race_id} not found in schedule! Saving directly to storage."
      save_race_directly(race_id, results)
      return
    end

    finish_times = results.each_with_object({}) do |racer, h|
      h[racer.id] = racer.finish_time if racer.finish_time
    end

    puts "[Orchestrator] Saving race #{race_id} with results: #{results.map(&:id)}, finish_times: #{finish_times}"
    
    @scheduler.complete_race(race_id, results, finish_times)
    
    puts "[Orchestrator] Verification - race #{race_id} in schedule: completed=#{race.completed}, results_count=#{race.results&.length || 0}"
    
    @scheduler.verify_race_saved(race_id)

    puts "[Orchestrator] Season #{@scheduler.current_season}: #{@scheduler.schedule.count(&:completed)}/#{@scheduler.schedule.length} races completed"
  rescue => e
    puts "[Orchestrator] ERROR in handle_race_finished for #{race_id}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end

  def save_race_directly(race_id, results)
    race = {
      'id' => race_id,
      'completed' => true,
      'results' => results.map(&:id),
      'finishTimes' => results.each_with_object({}) do |racer, h|
        h[racer.id] = racer.finish_time if racer.finish_time
      end
    }
    
    @races_storage.set_blob(race_id, race)
    puts "[Orchestrator] Saved race #{race_id} directly to storage"
    
    reload_and_update_schedule(race_id, race)
  end

  def reload_and_update_schedule(race_id, race)
    @scheduler.schedule.each do |r|
      if r.id == race_id
        r.completed = true
        r.results = race['results']
        r.finish_times = race['finishTimes']
        break
      end
    end
    @scheduler.save_schedule
    puts "[Orchestrator] Updated schedule with race #{race_id}"
  end
end
