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

#   R    G    B  /  R    G   B (primary / secondary)
COLORS = [
  [  0,   0,   0],                # Black
  [ 12, 105, 255],                # Blue
  [220, 172, 120],                # White
  [255,   0,   0],                # Red
  [ 30, 200,   0],                # Green
  [220, 172, 120, 255,   0,   0], # White/Red
  [220, 172, 120,   9,  84, 204]  # White/Blue
]
COLOR_NAMES = %w(Inconnu Bleu Blanc Rouge Vert Bonus/HP Bonus/HC)
UNKNOWN, BLUE, WHITE, RED, GREEN, BONIF, BONUS = 0, 1, 2, 3, 4, 5, 6
# BONIF (Zen Flex): bonus réduction conso HP (hiver) → blanc + rouge, animation HP
# BONUS (Zen Flex): bonus sur-conso HC (surproduction) → blanc + bleu, animation HC
TEMPO_HP_START = 6
TEMPO_HP_END = 22
# 07:00 to 01:00 (D+1) in France, but using London timezone to simplify (06:00 - 24:00)
EJP_HP_START = 6  # 07:00 CET
EJP_HP_END = 24   # 01:00 D+1 CET
EJP_ANNOUNCE = 14 # 15:00 CET, time for the next day announce
ZENFLEX_HP_RANGES = [[8, 13], [18, 20]]
ZENFLEX_ANNOUNCE = 16 # 16:00 CET, official announce time for J+1
LATITUDE = BigDecimal("48.8566")  # Paris
LONGITUDE = BigDecimal("2.3522")
SYNC_INTERVAL = 1.hour # +jitter
PASSWORD = ENV['PASSWORD'] || 'test'

database = ENV["RACK_ENV"] == "test" ? ":memory:" : "data/db.sqlite3"
set :database, { adapter: "sqlite3", database: database } unless ENV["DATABASE_URL"].present?

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
    if color.size == 6
      "<span style='color: rgb(#{color[0..2].join(', ')});'>◖</span>" +
      "<span style='color: rgb(#{color[3..5].join(', ')});'>◗ #{COLOR_NAMES[index]}</span>"
    else
      "<span style='color: rgb(#{color.join(', ')});'>● #{COLOR_NAMES[index]}</span>"
    end
  end
end

get "/" do
  device_id = params[:id]
  now = Time.now.in_time_zone('Europe/Paris')
  logger.info "[#{now}] New request from #{request.ip} (device_id: #{device_id}, user-agent: #{request.user_agent}, hostname: #{request.server_name})"
  if device_id&.match?(/\A[0-9a-f]{12}\z/) and device_id&.match?(/[a-f]/)
    device_id = device_id.to_i(16)
  end
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
  @tempo_day = (@now - TEMPO_HP_START.hours).to_date
  erb :admin, layout: :layout
end

post '/devices/:id/change_mode' do
  protected!
  device = Device.find_or_create_by(id: params[:id])
  device.update(mode: params[:mode]) if %w[tempo ejp zen_flex].include?(params[:mode])
  redirect '/admin'
end
