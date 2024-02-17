require 'sinatra'
require 'zache'
require 'http'

$cache = Zache.new

# https://www.api-couleur-tempo.fr/api/docs?ui=re_doc#tag/JourTempo
# COLORS = ['inconnu', 'bleu', 'blanc', 'rouge']

get "/" do
  today = $cache.get(:today, lifetime: 600) { HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/today").parse['codeJour'] }
  tomorrow = $cache.get(:tomorrow, lifetime: 600) { HTTP.get("https://www.api-couleur-tempo.fr/api/jourTempo/tomorrow").parse['codeJour'] }
  {today: today, tomorrow: tomorrow}.to_json
end