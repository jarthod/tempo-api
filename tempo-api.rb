# > bundle exec rackup
# > curl http://localhost:9292?id=7823783
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
COLOR_NAMES = %w(Inconnu Bleu Blanc Rouge)
UNKNOWN = 0
HP_START = 6
HP_END = 22
SYNC_INTERVAL = 1 # hours

set :database, {adapter: "sqlite3", database: "data/db.sqlite3"}

class Device < ActiveRecord::Base
  validates :mode, presence: true, inclusion: { in: %w(tempo ejp) }
end

unless ActiveRecord::Base.connection.table_exists?(:devices)
  ActiveRecord::Schema.define do
    create_table :devices do |t|
      t.string :mode, null: false, default: 'tempo'
      t.timestamps
    end
  end
end

def updateLEDs today, tomorrow, timing:, fx: "none", brightness: 1
  { action: "updateLEDs", timing: timing, topLEDs: {RGB: COLORS[today].map { (_1 * brightness).to_i }, FX: fx}, bottomLEDs: {RGB: COLORS[tomorrow].map { (_1 * brightness).to_i }, FX: "none"}}
end

def tempo_color_for time
  tempo_day = (time - HP_START.hours).to_date
  $cache.get(tempo_day, lifetime: 600) do
    HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/#{tempo_day}").parse.fetch('codeJour', UNKNOWN)
  end
end

def protected!
  auth = Rack::Auth::Basic::Request.new(request.env)
  unless auth.provided? && auth.basic? && auth.credentials == ['admin', '*$dmB25$TxNUup5yE6TC2Dv!']
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    halt 401, 'Not authorized'
  end
end

helpers do
  def color_display index
    "<span style='color: rgb(#{COLORS[index].join(', ')});'>● #{COLOR_NAMES[index]}</span>"
  end
end

get "/" do
  device_id = params[:id]
  now = Time.now.in_time_zone('Europe/Paris')
  puts "[#{now}] New request from #{request.ip} (device_id: #{device_id}, user-agent: #{request.user_agent})"
  device = Device.find_or_create_by(id: device_id.to_i) if device_id.to_i > 0
  puts "[#{now}] Device #{device.id} (mode: #{device.mode}, created: #{device.created_at}, last_update: #{device.updated_at})" if device
  device&.touch
  today = params[:today]&.to_i || tempo_color_for(now)
  tomorrow = params[:tomorrow]&.to_i || tempo_color_for(now.tomorrow)
  hp = now.hour.between?(HP_START, HP_END-1)
  end_of_today = (now.hour < HP_START ? now.change(hour: HP_START) : now.tomorrow.change(hour: HP_START))
  end_of_tomorrow = end_of_today + 1.day
  no_data = (tomorrow == UNKNOWN ? end_of_today : end_of_tomorrow)
  puts "[#{now}] Tempo HP: #{hp}, Today: #{today} (→ #{end_of_today}), Tomorrow: #{tomorrow} (→ #{end_of_tomorrow})"
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
  { time: now.utc.iso8601, actions: actions }.to_json.tap { puts "[#{now}] Response: #{_1}" }
end

get '/admin' do
  protected!
  @now = Time.now.in_time_zone('Europe/Paris')
  @today = tempo_color_for(@now)
  @tomorrow = tempo_color_for(@now.tomorrow)
  erb :admin, layout: :main
end

# Views
__END__
@@ main
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TempOrb Admin</title>
  <link rel="stylesheet" href="https://fonts.xz.style/serve/inter.css">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@exampledev/new.css@1.1.2/new.min.css">
</head>
<body>
  <header><h1>TempOrb Admin</h1></header>
  <main><%= yield %></main>
  <footer style="color: #888">
    <div style="float: right"><%= @now %></div>
    TEMPO: <%= color_display(@today) %> / <%= color_display(@tomorrow) %>
  </footer>
</body>
</html>

@@ admin
<table>
  <tr><th>Device ID</th><th>Mode</th><th>Last Poll</th></tr>
  <% Device.all.each do |device| %>
    <tr><td><%= device.id %></td><td><%= device.mode %></td><td><%= device.updated_at.in_time_zone('Europe/Paris') %></td></tr>
  <% end %>
</table>
