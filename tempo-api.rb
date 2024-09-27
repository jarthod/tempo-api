# > bundle exec rackup
# > curl http://localhost:9292
# > curl "http://localhost:9292?today=3&tomorrow=0"

require 'sinatra'
require 'zache'
require 'http'
require 'active_support/core_ext/time'

$cache = Zache.new

# https://www.api-couleur-tempo.fr/api/docs?ui=re_doc#tag/JourTempo [inconnu, bleu, blanc, rouge]
COLORS = [[0, 0, 0], [0, 0, 255], [255, 255, 255], [255, 0, 0]]
UNKNOWN = 0
HP_START = 6
HP_END = 22
SYNC_INTERVAL = 1 # hours

def updateLEDs today, tomorrow, timing:, fx: "none"
  { action: "updateLEDs", timing: timing, LEDs: [{RGB: COLORS[today], FX: fx}]*3 + [{RGB: COLORS[tomorrow], FX: "none"}]}
end

get "/" do
  now = Time.now.in_time_zone('Europe/Paris')
  today = params[:today]&.to_i || $cache.get(:today, lifetime: 600) { HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/today").parse['codeJour'] }
  tomorrow = params[:tomorrow]&.to_i || $cache.get(:tomorrow, lifetime: 600) { HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/tomorrow").parse['codeJour'] }
  hp = now.hour.between?(HP_START, HP_END-1)
  end_of_today = (now.hour < HP_START ? now.change(hour: HP_START) : now.tomorrow.change(hour: HP_START))
  end_of_tomorrow = end_of_today.advance(days: 1)
  no_data = (tomorrow == UNKNOWN ? end_of_today : end_of_tomorrow)
  puts "HP: #{hp}, Today: #{today} (→ #{end_of_today}), Tomorrow: #{tomorrow} (→ #{end_of_tomorrow})"
  actions = [
    updateLEDs(today, tomorrow, timing: "initial", fx: (hp ? "none" : "breathingSlow")),
    { action: "syncAPI", timing: (now + SYNC_INTERVAL * 3600 + rand(3600)).iso8601 },
    { action: "error_noData", timing: no_data.iso8601 }
  ]
  if hp
    actions << updateLEDs(today, tomorrow, timing: now.change(hour: HP_END), fx: "breathingSlow")
  end
  if tomorrow != UNKNOWN
    actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today, fx: "none")
    actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.change(hour: HP_END), fx: "breathingSlow")
  end
  { time: now.iso8601, actions: actions }.to_json.tap { puts _1 }
end