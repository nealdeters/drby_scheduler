#!/usr/bin/env ruby
# One-shot: rename 4 existing racers in place. Does not add/remove roster
# entries or touch health / speed / standings / results.

require 'json'
require_relative '../../lib/services/netlify_blobs_service'

RENAMES = {
  'r15' => { 'name' => 'Spiral Ham' },
  'r10' => { 'name' => "Carmella's Dream", 'color' => '#E11D2E' },
  'r9' => { 'name' => 'Frederico', 'color' => '#111111' },
  'r4' => { 'name' => 'Kenny', 'color' => '#F5F5F5' }
}.freeze

site_id = ENV.fetch('NETLIFY_SITE_ID')
token = ENV.fetch('NETLIFY_AUTH_TOKEN')

racers = NetlifyBlobsService.new(site_id: site_id, auth_token: token, store_name: 'site:racers')
races = NetlifyBlobsService.new(site_id: site_id, auth_token: token, store_name: 'site:races')

RENAMES.each do |id, patch|
  blob = racers.get_blob(id)
  raise "missing racer blob #{id}" unless blob.is_a?(Hash)
  before = "#{blob['name']} #{blob['color']} health=#{blob['health']} pts_key=#{id}"
  blob['name'] = patch['name']
  blob['color'] = patch['color'] if patch.key?('color')
  racers.set_blob(id, blob)
  after = "#{blob['name']} #{blob['color']} health=#{blob['health']}"
  puts "  #{id}: #{before} -> #{after}"
end

roster = races.get_roster
if roster.is_a?(Array) && roster.any?
  roster.each do |row|
    next unless row.is_a?(Hash)
    patch = RENAMES[row['id']]
    next unless patch
    row['name'] = patch['name']
    row['color'] = patch['color'] if patch.key?('color')
  end
  races.save_roster(roster)
  puts "  updated races roster snapshot (#{roster.length})"
end

completed = races.get_completed_seasons
if completed.is_a?(Array)
  changed = false
  completed.each do |season|
    winner = season.is_a?(Hash) ? season['winner'] : nil
    next unless winner.is_a?(Hash)
    patch = RENAMES[winner['id']]
    next unless patch
    winner['name'] = patch['name']
    winner['color'] = patch['color'] if patch.key?('color')
    changed = true
    puts "  season #{season['number'] || season['id']} winner -> #{winner['name']}"
  end
  races.save_completed_seasons(completed) if changed
end

puts 'done (ids/stats unchanged, no horses added)'
