# > bundle exec rackup

require 'sinatra'
require 'zache'
require 'http'
require 'active_support/core_ext/time'

$cache = Zache.new

# https://www.api-couleur-tempo.fr/api/docs?ui=re_doc#tag/JourTempo
# COLORS = ['inconnu', 'bleu', 'blanc', 'rouge']

get "/" do
  today = $cache.get(:today, lifetime: 600) { HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/today").parse['codeJour'] }
  tomorrow = $cache.get(:tomorrow, lifetime: 600) { HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/tomorrow").parse['codeJour'] }
  {
    today: today,
    tomorrow: tomorrow,
    time: Time.now.in_time_zone('Europe/Paris').iso8601,
    tempo_day_HP: "06:00/22:00",
    tempo_sync: "11:00"
  }.to_json
end