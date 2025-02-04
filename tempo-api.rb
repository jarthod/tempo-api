# > bundle exec rackup
# > curl http://localhost:9292
# > curl "http://localhost:9292?today=3&tomorrow=0"

require 'sinatra'
require 'zache'
require 'http'
require 'active_support/core_ext/time'
require 'active_support/core_ext/integer'
require 'sinatra/activerecord'

$cache = Zache.new

# https://www.api-couleur-tempo.fr/api/docs?ui=re_doc#tag/JourTempo [inconnu, bleu, blanc, rouge]
COLORS = [[0, 0, 0], [12, 105, 255], [220, 190, 160], [255, 0, 0]]
UNKNOWN = 0
HP_START = 6
HP_END = 22
SYNC_INTERVAL = 1 # hours

set :database, {adapter: "sqlite3", database: "data/db.sqlite3"}

# Define a simple model
class Device < ActiveRecord::Base
end

# Create the users table if it doesn't exist
# unless ActiveRecord::Base.connection.table_exists?(:devices)
#   ActiveRecord::Schema.define do
#     create_table :devices do |t|
#       t.string :name
#       t.string :name
#       t.timestamps
#     end
#   end
# end

def updateLEDs today, tomorrow, timing:, fx: "none", brightness: 1
  { action: "updateLEDs", timing: timing, topLEDs: {RGB: COLORS[today].map { (_1 * brightness).to_i }, FX: fx}, bottomLEDs: {RGB: COLORS[tomorrow].map { (_1 * brightness).to_i }, FX: "none"}}
end

def color_for time
  tempo_day = (time - HP_START.hours).to_date
  $cache.get(tempo_day, lifetime: 600) do
    HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/#{tempo_day}").parse.fetch('codeJour', UNKNOWN)
  end
end

get "/" do
  headers_list = request.env.select { |k, v| k.start_with?('HTTP_') }.map { |k, v| "- #{k}: #{v}" }.join("\n")
  puts "Request headers:\n#{headers_list}"

  now = Time.now.in_time_zone('Europe/Paris')
  today = params[:today]&.to_i || color_for(now)
  tomorrow = params[:tomorrow]&.to_i || color_for(now.tomorrow)
  hp = now.hour.between?(HP_START, HP_END-1)
  end_of_today = (now.hour < HP_START ? now.change(hour: HP_START) : now.tomorrow.change(hour: HP_START))
  end_of_tomorrow = end_of_today + 1.day
  no_data = (tomorrow == UNKNOWN ? end_of_today : end_of_tomorrow)
  puts "[#{now}] HP: #{hp}, Today: #{today} (→ #{end_of_today}), Tomorrow: #{tomorrow} (→ #{end_of_tomorrow})"
  actions = [
    updateLEDs(today, tomorrow, timing: "initial", fx: (hp && today == 3 ? "breathingRingHalf" : "none"), brightness: (hp ? 1 : 0.5)),
    { action: "syncAPI", timing: (now + SYNC_INTERVAL * 3600 + rand(3600)).utc.iso8601 },
    { action: "error_noData", timing: no_data.utc.iso8601 }
  ]
  if hp
    actions << updateLEDs(today, tomorrow, timing: now.change(hour: HP_END).utc.iso8601, brightness: 0.5)
  end
  if tomorrow != UNKNOWN
    actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.utc.iso8601, fx: (tomorrow == 3 ? "breathingRingHalf" : "none"))
    actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.change(hour: HP_END).utc.iso8601, brightness: 0.5)
  end
  { time: now.utc.iso8601, actions: actions }.to_json.tap { puts _1 }
end