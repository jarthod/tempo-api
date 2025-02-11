# > bundle exec rackup
# > curl http://localhost:9292?id=7823783
# > curl "http://localhost:9292?today=3&tomorrow=0"

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/custom_logger'
require 'logger'
require 'net/http'
require 'active_support/core_ext/time'
require 'active_support/core_ext/integer'
require 'sinatra/activerecord'
require_relative "lib/temp_orb"
require_relative "lib/device"
also_reload './lib/*.rb', './helpers/*.rb' if development?

set :logger, Logger.new(STDOUT)

# https://www.api-couleur-tempo.fr/api/docs?ui=re_doc#tag/JourTempo [inconnu, bleu, blanc, rouge] (+vert pour EJP)
COLORS = [[0, 0, 0], [12, 105, 255], [220, 190, 160], [255, 0, 0], [30, 200, 0]]
COLOR_NAMES = %w(Inconnu Bleu Blanc Rouge Vert)
UNKNOWN, BLUE, WHITE, RED, GREEN = 0, 1, 2, 3, 4
TEMPO_HP_START = 6
TEMPO_HP_END = 22
# 07:00 to 01:00 (D+1) in France, but using London timezone to simplify (06:00 - 24:00)
EJP_HP_START = 6  # 07:00 CET
EJP_HP_END = 24   # 01:00 D+1 CET
EJP_ANNOUNCE = 14 # 15:00 CET, time for the next day announce
SYNC_INTERVAL = 1.hour # +jitter
PASSWORD = ENV['PASSWORD'] || 'test'

database = ENV["RACK_ENV"] == "test" ? ":memory:" : "data/db.sqlite3"
set :database, { adapter: "sqlite3", database: database }

helpers do
  def protected!
    auth = Rack::Auth::Basic::Request.new(request.env)
    unless auth.provided? && auth.basic? && auth.credentials == ['admin', PASSWORD]
      headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
      halt 401, 'Not authorized'
    end
  end

  def color_display index
    color = COLORS[index]
    color = [100, 100, 100] if index == 0 # black would not be readable on the admin background
    "<span style='color: rgb(#{color.join(', ')});'>● #{COLOR_NAMES[index]}</span>"
  end
end

get "/" do
  device_id = params[:id]
  now = Time.now.in_time_zone('Europe/Paris')
  logger.info "[#{now}] New request from #{request.ip} (device_id: #{device_id}, user-agent: #{request.user_agent})"
  device = Device.find_or_create_by(id: device_id.to_i) if device_id.to_i > 0
  logger.info "[#{now}] Device #{device.id} (mode: #{device.mode}, created: #{device.created_at}, last_update: #{device.updated_at})" if device
  device&.touch

  mode = params[:mode] || device&.mode || 'tempo'
  actions = TempOrb.actions_for(now, mode:, today: params[:today], tomorrow: params[:tomorrow])

  response = { mode:, time: now.utc.iso8601, actions: actions }.to_json
  logger.info { "[#{now}] Response: #{response}" }
  content_type :json
  response
end

get '/admin' do
  protected!
  @now = Time.now.in_time_zone('Europe/Paris')
  erb :admin, layout: :layout
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