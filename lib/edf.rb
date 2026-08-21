$cache = ENV['RACK_ENV'] == 'test' ? ActiveSupport::Cache::MemoryStore.new : ActiveSupport::Cache::FileStore.new("tmp/cache")

module EDF
  RTE_COLORS = {"BLUE" => 1, "WHITE" => 2, "RED" => 3}
  ZENFLEX_COLORS = {"RAS" => 5, "ZENF_PM" => 3, "ZENF_BONIF" => 6, "ZENF_BONUS" => 7}
  TEMPO_APIS = ['api-couleur-tempo.fr', 'services-rte.com']
  EJP_OFF_MONTH = 4..10 # Avril - Octobre

  def self.tempo_color_for tempo_day, api:
    case api
    when 'services-rte.com'
      values = get_json("https://www.services-rte.com/cms/open_data/v1/tempoLight")['values']
      if values&.dig("#{tempo_day}-fallback") == 'false'
        RTE_COLORS[values[tempo_day.to_s]]
      elsif values&.dig("#{tempo_day}-fallback") == 'true'
        UNKNOWN
      else
        UNKNOWN # other type of errors
      end
    when 'api-couleur-tempo.fr'
      get_json("https://www.api-couleur-tempo.fr/api/jourTempo/#{tempo_day}").fetch('codeJour', UNKNOWN)
    end
  end

  def self.ejp_color_for time
    time = time.in_time_zone('Europe/London')
    ejp_day = time.to_date
    response = get_json("https://api-commerce.edf.fr/commerce/activet/v1/calendrier-jours-effacement",
      headers: {"Accept": "application/json", "application-origine-controlee" => "site_RC", "situation-usage" => "Jours Effacement"},
      params: {
        dateApplicationBorneInf: ejp_day.strftime("%Y-%-m-%-d"),
        dateApplicationBorneSup: ejp_day.strftime("%Y-%-m-%-d"),
        option: 'EJP', identifiantConsommateur: "src"
      })
    statut = response.dig('content', 'options', 0, 'calendrier', 0, 'statut')
    case statut
    when "EJP"
      code = 3 # rouge
    when "NON_EJP"
      code = 4 # vert
      code = UNKNOWN if ejp_day > Date.today && time.hour < EJP_ANNOUNCE # tomorrow not "announced" yet
    else
      code = UNKNOWN
    end
    logger.debug "> #{statut} → #{code}"
    code
  end

  def self.zen_flex_color_for date
    # API returns both J and J+1 for a given date; we query with the target date as J
    # and also try as J-1's J+1 to maximize cache hits from get_json
    response = get_json("https://particulier.edf.fr/services/rest/opm/getOPMStatut",
      params: { dateRelevant: date.strftime("%Y-%m-%d") })
    statut = response['couleurJourJ']
    ZENFLEX_COLORS.fetch(statut, UNKNOWN)
  end

  def self.get_json url, params: nil, headers: {}
    url = URI(url)
    url.query = URI.encode_www_form(params) if params

    $cache.fetch("get_json/#{url}", expires_in: 10.minutes) do
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(url)
      request["Accept"] = "application/json"
      headers.each { request[_1] = _2 }

      logger.info "> Query #{url}"

      begin
        response = http.request(request)
        if Net::HTTPSuccess === response && response['Content-Type']&.include?('application/json')
          logger.info "> Response #{response.code} #{response.body}"
          JSON.parse(response.body)
        else
          logger.warn "> Error #{response.code} #{response.body}"
          { error: "#{response.code} #{response.body}" }
        end
      rescue StandardError => error
        logger.warn "> #{error.class}: #{error.message}"
        { error: "#{error.class} #{error.message}" }
      end
    end
  end

  def self.logger = Sinatra::Application.logger
end