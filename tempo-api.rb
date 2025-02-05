# > bundle exec rackup
# > curl http://localhost:9292?id=7823783
# > curl "http://localhost:9292?today=3&tomorrow=0"

require 'sinatra'
require 'zache'
require 'httpx'
require 'active_support/core_ext/time'
require 'active_support/core_ext/integer'
require 'sinatra/activerecord'

$cache = Zache.new

# https://www.api-couleur-tempo.fr/api/docs?ui=re_doc#tag/JourTempo [inconnu, bleu, blanc, rouge] (+vert pour EJP)
COLORS = [[0, 0, 0], [12, 105, 255], [220, 190, 160], [255, 0, 0], [80, 200, 35]]
COLOR_NAMES = %w(Inconnu Bleu Blanc Rouge Vert)
UNKNOWN = 0
TEMPO_HP_START = 6
TEMPO_HP_END = 22
# 7h - 25h en France, mais j'utilise une timezone Londre pour simplifier
EJP_HP_START = 6
EJP_HP_END = 24
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
  tempo_day = (time - TEMPO_HP_START.hours).to_date
  $cache.get("api-couleur-tempo/#{tempo_day}", lifetime: 600) do
    # Alternative: https://www.services-rte.com/cms/open_data/v1/tempoLight
    HTTPX.with(timeout: { connection_timeout: 5, request_timeout: 10 })
      .get("https://www.api-couleur-tempo.fr/api/jourTempo/#{tempo_day}").json.fetch('codeJour', UNKNOWN)
  end
end

def ejp_color_for time
  ejp_day = time.to_date
  $cache.get("EJP/#{ejp_day}", lifetime: 600) do
    puts "> Request EJP for #{ejp_day} (no cache)"
    response = HTTPX.with(timeout: { connection_timeout: 5, request_timeout: 10 },
      headers: {"Accept": "application/json", "application-origine-controlee" => "site_RC", "situation-usage" => "Jours Effacement"})
      .get("https://api-commerce.edf.fr/commerce/activet/v1/calendrier-jours-effacement", params: {
        dateApplicationBorneInf: ejp_day.strftime("%Y-%-m-%-d"),
        dateApplicationBorneSup: ejp_day.strftime("%Y-%-m-%-d"),
        option: 'EJP', identifiantConsommateur: "src"
      })
    case response
    in [200, [*, %w[content-type application/json], *], *]
      puts "> #{response.status} #{response.body}"
      statut = response.json.dig('content', 'options', 0, 'calendrier', 0, 'statut')
      code = (statut == "EJP" ? 3 : 4) # 3 = rouge, 4 = vert
      code = 0 if ejp_day > Date.today && time.hour < 15 && statut == 'NON_EJP' # inconnu
      puts "> #{statut} → #{code}"
      code
    in {status: 100..}
      puts "> Error #{response.status} #{response.body}"
      UNKNOWN
    in {error: error}
      puts "> #{error.class}: #{error}"
      UNKNOWN
    end
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
    color = COLORS[index]
    color = [100, 100, 100] if index == 0 # black would not be readable on black
    "<span style='color: rgb(#{color.join(', ')});'>● #{COLOR_NAMES[index]}</span>"
  end
end

get "/" do
  device_id = params[:id]
  now = Time.now.in_time_zone('Europe/Paris')
  puts "[#{now}] New request from #{request.ip} (device_id: #{device_id}, user-agent: #{request.user_agent})"
  device = Device.find_or_create_by(id: device_id.to_i) if device_id.to_i > 0
  puts "[#{now}] Device #{device.id} (mode: #{device.mode}, created: #{device.created_at}, last_update: #{device.updated_at})" if device
  device&.touch
  case params[:mode] || device&.mode
  when 'ejp'
    # Timezone 1h en avance sur la France, pour simplifier la gestion de la fin à 1h (ca passe a minuit)
    now = now.in_time_zone('Europe/London')
    today = params[:today]&.to_i || ejp_color_for(now)
    tomorrow = params[:tomorrow]&.to_i || ejp_color_for(now.tomorrow)
    hp = now.hour.between?(EJP_HP_START, EJP_HP_END-1)
    end_of_today = now.change(hour: EJP_HP_END)
    end_of_tomorrow = end_of_today + 1.day
    no_data = (tomorrow == UNKNOWN ? end_of_today : end_of_tomorrow)
    puts "[#{now}] EJP HP: #{hp}, Today: #{COLOR_NAMES[today]} (→ #{end_of_today}), Tomorrow: #{COLOR_NAMES[tomorrow]} (→ #{end_of_tomorrow})"
    actions = [
      updateLEDs(today, tomorrow, timing: "initial", fx: (hp && today == 3 ? "breathingRingHalf" : "none"), brightness: (hp ? 1 : 0.5)),
      { action: "syncAPI", timing: (now + SYNC_INTERVAL * 3600 + rand(3600)).utc.iso8601 },
      { action: "error_noData", timing: no_data.utc.iso8601 }
    ]
    if !hp
      actions << updateLEDs(today, tomorrow, timing: now.change(hour: EJP_HP_START).utc.iso8601, fx: (today == 3 ? "breathingRingHalf" : "none"))
    end
    if tomorrow != UNKNOWN
      actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.utc.iso8601, brightness: 0.5)
      actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.change(hour: EJP_HP_START).utc.iso8601, fx: (tomorrow == 3 ? "breathingRingHalf" : "none"))
    end
  else
    today = params[:today]&.to_i || tempo_color_for(now)
    tomorrow = params[:tomorrow]&.to_i || tempo_color_for(now.tomorrow)
    hp = now.hour.between?(TEMPO_HP_START, TEMPO_HP_END-1)
    end_of_today = (now.hour < TEMPO_HP_START ? now.change(hour: TEMPO_HP_START) : now.tomorrow.change(hour: TEMPO_HP_START))
    end_of_tomorrow = end_of_today + 1.day
    no_data = (tomorrow == UNKNOWN ? end_of_today : end_of_tomorrow)
    puts "[#{now}] Tempo HP: #{hp}, Today: #{COLOR_NAMES[today]} (→ #{end_of_today}), Tomorrow: #{COLOR_NAMES[tomorrow]} (→ #{end_of_tomorrow})"
    actions = [
      updateLEDs(today, tomorrow, timing: "initial", fx: (hp && today == 3 ? "breathingRingHalf" : "none"), brightness: (hp ? 1 : 0.5)),
      { action: "syncAPI", timing: (now + SYNC_INTERVAL * 3600 + rand(3600)).utc.iso8601 },
      { action: "error_noData", timing: no_data.utc.iso8601 }
    ]
    if hp
      actions << updateLEDs(today, tomorrow, timing: now.change(hour: TEMPO_HP_END).utc.iso8601, brightness: 0.5)
    end
    if tomorrow != UNKNOWN
      actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.utc.iso8601, fx: (tomorrow == 3 ? "breathingRingHalf" : "none"))
      actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.change(hour: TEMPO_HP_END).utc.iso8601, brightness: 0.5)
    end
  end
  content_type :json
  { time: now.utc.iso8601, actions: actions }.to_json.tap { puts "[#{now}] Response: #{_1}" }
end

get '/admin' do
  protected!
  @now = Time.now.in_time_zone('Europe/Paris')
  erb :admin, layout: :main
end

get '/devices/:id/change_mode' do
  protected!
  device = Device.find_or_create_by(id: params[:id])
  if device.mode == 'tempo'
    device.update(mode: 'ejp')
  else
    device.update(mode: 'tempo')
  end
  redirect '/admin'
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
  <header><h1><%= $icon ||= File.read('icon.svg') %> TempOrb Admin</h1></header>
  <main><%= yield %></main>
  <footer style="color: #888">
    <div style="float: right"><%= @now %></div>
    TEMPO: <%= color_display(tempo_color_for(@now)) %> / <%= color_display(tempo_color_for(@now.tomorrow)) %><br>
    EJP: <%= color_display(ejp_color_for(@now)) %> / <%= color_display(ejp_color_for(@now.tomorrow)) %>
  </footer>
</body>
</html>

@@ admin
<table>
  <tr><th>Device ID</th><th>Mode</th><th>First Poll</th><th>Last Poll / Update</th></tr>
  <% Device.all.each do |device| %>
    <tr>
      <td><%= device.id.to_s(16).upcase %></td>
      <td><strong><%= device.mode.upcase %></strong> <a href="/devices/<%= device.id %>/change_mode">⇄</a></td>
      <td><%= device.created_at.in_time_zone('Europe/Paris') %></td>
      <td><%= device.updated_at.in_time_zone('Europe/Paris') %></td>
    </tr>
  <% end %>
</table>
