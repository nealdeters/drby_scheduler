#!/usr/bin/env ruby

require 'dotenv/load'
require_relative '../../lib/services/clear_service'

class ClearData
  include ClearService

  KEYS = %w[
    season-schedule
    season-standings
    completed-seasons
    current-season-number
  ].freeze

  def initialize
    super(store_name: 'site:races')
    @keys = KEYS
    @keys_name = 'season data'
  end
end

if __FILE__ == $0
  ClearData.new.run
end
