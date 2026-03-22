#!/usr/bin/env ruby

require 'dotenv/load'
require_relative '../../lib/services/seed_service'

class SeedTracks
  include SeedService

  TRACKS = [
    { 'id' => 't1', 'name' => 'Oval Circuit', 'surface' => 'asphalt', 'length' => 1000, 'laps' => 3 },
    { 'id' => 't2', 'name' => 'Dirt Derby', 'surface' => 'dirt', 'length' => 800, 'laps' => 5 },
    { 'id' => 't3', 'name' => 'Grasslands', 'surface' => 'grass', 'length' => 1200, 'laps' => 2 }
  ].freeze

  def initialize
    super(store_name: 'site:tracks')
    @data = TRACKS
    @data_name = 'tracks'
  end

  def data_label
    'tracks'
  end
end

if __FILE__ == $0
  SeedTracks.new.run
end
