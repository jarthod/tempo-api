# > bundle exec rackup
# > curl http://localhost:9292?id=7823783
# > curl "http://localhost:9292?today=3&tomorrow=0"
# > open http://localhost:9292/id (or http://config.localhost:9292)

require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/custom_logger'
require 'logger'
require 'net/http'
require 'bigdecimal'
require 'active_support/core_ext/time'
require 'active_support/core_ext/integer'
require 'sinatra/activerecord'

set :logger, Logger.new(STDOUT)
enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }

#   R    G    B  /  R    G   B (primary / secondary)
COLORS = [
  [  0,   0,   0],                # Black
  [ 12, 105, 255],                # Blue
  [220, 172, 120],                # White
  [255,   0,   0],                # Red
  [ 30, 200,   0],                # Green
  [ 30, 255, 180],                # Turquoise
  [220, 172, 120, 255,   0,   0], # White/Red
  [220, 172, 120,  24, 204, 144], # White/Turquoise
  [255,  90,   0],                # Orange
]
COLOR_NAMES = %w(Inconnu Bleu Blanc Rouge Vert Eco Bonus/HP Bonus/HC Orange)
UNKNOWN, BLUE, WHITE, RED, GREEN, ECO, BONIF, BONUS, ORANGE = 0, 1, 2, 3, 4, 5, 6, 7, 8
# ECO   (Zen Flex): "jour éco" équivalent bleu pour Tempo
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
FAST_SYNC_INTERVAL = 15.minutes # when data is not available yet
PASSWORD = ENV['PASSWORD'] || 'test'

require_relative "lib/contract"
require_relative "lib/temp_orb"
require_relative "lib/device"
also_reload './lib/*.rb', './helpers/*.rb' if development?

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

  # config.temporb.fr serves the ID form on /, /id works on any host (handy in dev)
  def config_host? = request.host.start_with?('config.')

  # Rails-like flash: kept in session until displayed on the next page (see layout)
  def flash = session['flash'] ||= {}

  # the ID form is a GET (no JS needed), redirect its ?id= to the config page URL
  def config_index
    redirect "/id/#{Rack::Utils.escape_path(params[:id].strip.downcase)}" if params[:id].present?
    erb :config_index
  end

  def find_device!
    @noindex = true
    @device_id = params[:id].to_s.strip.downcase
    @device = Device.find_by(id: Device.parse_id(@device_id))
    return if @device
    @error = "Aucun Temp'Orb trouvé avec l'identifiant « #{@device_id} ». Vérifiez l'identifiant et que votre Temp'Orb est bien branché et connecté au Wi-Fi."
    halt 404, erb(:config_index)
  end

  def h(text) = Rack::Utils.escape_html(text.to_s)

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

  # Temp'Orb drawing (see public/icon.svg) with its rings lit: top = today, bottom = tomorrow
  def orb_svg today, tomorrow
    @orb_count = (@orb_count || 0) + 1
    gradients = []
    fill = ->(index, ring) {
      color = index == UNKNOWN ? [100, 100, 100] : COLORS[index] # black would not be visible
      next "rgb(#{color.join(',')})" if color.size == 3
      id = "orb#{@orb_count}-#{ring}" # dual ring: primary fading into secondary
      gradients << "<linearGradient id='#{id}'><stop offset='30%' stop-color='rgb(#{color[0..2].join(',')})'/>" \
        "<stop offset='70%' stop-color='rgb(#{color[3..5].join(',')})'/></linearGradient>"
      "url(##{id})"
    }
    top, bottom = fill.(today, 'top'), fill.(tomorrow, 'bottom')
    <<~SVG
      <svg class='orb' viewBox='0 0 59.33 39.67' role='img' aria-label='#{COLOR_NAMES[today]} / #{COLOR_NAMES[tomorrow]}'>
        <defs>#{gradients.join}</defs>
        <g transform='translate(-64.833325,-78.495271)' fill-rule='evenodd'>
          <path fill='#111' d='M 66,106.5 C 66,100.149 78.7599,95 94.5,95 110.24,95 123,100.149 123,106.5 123,112.851 110.24,118 94.5,118 78.7599,118 66,112.851 66,106.5 Z'/>
          <path fill='#{bottom}' d='m 65,103 c 0,-6.0751 13.2076,-11 29.5,-11 16.292,0 29.5,4.9249 29.5,11 0,6.075 -13.208,11 -29.5,11 C 78.2076,114 65,109.075 65,103 Z'/>
          <path fill='#111' d='M 65,99.5 C 65,93.1487 78.2076,88 94.5,88 110.792,88 124,93.1487 124,99.5 124,105.851 110.792,111 94.5,111 78.2076,111 65,105.851 65,99.5 Z'/>
          <path fill='#{top}' d='M 65,97.5 C 65,91.1487 78.2076,86 94.5,86 110.792,86 124,91.1487 124,97.5 124,103.851 110.792,109 94.5,109 78.2076,109 65,103.851 65,97.5 Z'/>
          <path fill='#{top}' d='m 65.045563,93.25067 c 0,-6.351299 13.207601,-11.499999 29.500001,-11.499999 16.291996,0 29.499996,5.1487 29.499996,11.499999 0,6.351 -13.208,11.5 -29.499996,11.5 -16.2924,0 -29.500001,-5.149 -29.500001,-11.5 z'/>
          <path fill='#111' d='m 66,89.534145 c 0,-6.0751 12.7599,-11 28.5,-11 15.74,0 28.5,4.9249 28.5,11 0,6.0751 -12.76,11.000005 -28.5,11.000005 -15.7401,0 -28.5,-4.924905 -28.5,-11.000005 z'/>
          <path fill='none' stroke='#111' stroke-width='0.666667' d='m 68.126198,109.44659 c -1.6569,0 -3,-5.149 -3,-11.499905 0,-6.3466 1.3412,-11.4934 2.9968,-11.5'/>
          <path fill='none' stroke='#111' stroke-width='0.666667' d='m 120.96584,109.55341 c 1.65686,0 3.00001,-5.14872 3.00001,-11.499995 0,-6.3466 -1.34125,-11.4934 -2.99689,-11.5'/>
        </g>
      </svg>
    SVG
  end

  def manual_select contract, target
    time = target == 'tomorrow' ? @now.tomorrow : @now
    date = Contract.day_for(contract, time)
    val = $cache.read(Contract.cache_key(contract, date))

    options = ["<option value='0' #{'selected' if val.nil?}>Auto</option>"]
    Contract.colors_for(contract).each do |c|
      options << "<option value='#{c}' #{'selected' if val == c}>#{COLOR_NAMES[c]}</option>"
    end

    "<form action='/admin/manual_override' method='post' style='display:inline'>" +
      "<input type='hidden' name='contract' value='#{contract}'>" +
      "<input type='hidden' name='target' value='#{target}'>" +
      "<select name='color' onchange='this.form.submit()'>" +
      options.join +
      "</select>" +
      "<button type='submit' style='display:none'>Apply</button>" +
    "</form>"
  end
end

get "/" do
  return config_index if config_host?
  request.session_options[:skip] = true # no session cookie for devices

  device_id = params[:id]
  now = Time.now.in_time_zone('Europe/Paris')
  logger.info "[#{now}] New request from #{request.ip} (device_id: #{device_id}, user-agent: #{request.user_agent}, hostname: #{request.server_name})"
  device_id = Device.parse_id(device_id)
  device = Device.find_or_create_by(id: device_id) if device_id > 0
  logger.info "[#{now}] Device #{device.id} (mode: #{device.mode}, created: #{device.created_at}, last_update: #{device.updated_at})" if device
  device&.touch

  mode = params[:mode] || device&.mode || 'tempo'
  actions = TempOrb.actions_for(now, mode:, settings: device&.settings, today: params[:today], tomorrow: params[:tomorrow])

  response = { mode:, time: now.utc.iso8601, actions: actions }.to_json
  logger.info { "[#{now}] Response: #{response}" }
  content_type :json
  response
end

# Config pages: ID form on /id (and / on config.temporb.fr) → /id/:id
get('/id') { config_index }

get '/id/:id' do
  find_device!
  erb :config
end

patch '/id/:id' do
  find_device!
  @device.mode = params[:mode]
  if params[:mode] == 'hphc'
    ranges = [[params[:hc_night_start], params[:hc_night_end]]]
    ranges << [params[:hc_day_start], params[:hc_day_end]] if params[:hc_day_enabled]
    @device.hc_ranges = ranges
  end
  if @device.save
    flash['notice'] = "Paramètres enregistrés ! Votre Temp'Orb peut mettre jusqu'à 2 heures avant de se mettre à jour automatiquement. " \
      "Pour forcer la mise à jour, vous pouvez le débrancher puis le rebrancher, sans risque pour votre Temp'Orb."
    redirect "/id/#{Rack::Utils.escape_path(@device_id)}"
  else
    status 422
    erb :config
  end
end

get '/admin' do
  protected!
  @now = Time.now.in_time_zone('Europe/Paris')
  @tempo_day = Contract.day_for('tempo', @now)
  @noindex = true
  erb :admin
end

post '/admin/manual_override' do
  protected!
  contract = params[:contract]
  if Contract::MODES.include?(contract)
    now = Time.now.in_time_zone('Europe/Paris')
    target_time = params[:target] == 'tomorrow' ? now.tomorrow : now
    target_date = Contract.day_for(contract, target_time)
    Contract.set_manual_override(contract, target_date, params[:color])
  end
  redirect '/admin'
end
