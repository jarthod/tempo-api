require_relative "edf"

module Contract
  MODES = %w(tempo ejp zen_flex hphc).freeze

  # Each day_for forces its own timezone rather than trusting the caller to have
  # already converted, so it gives the right answer no matter what zone `time` is in.
  #
  # fetch receives (time, date): tempo/zen_flex only need the date, EJP also needs the
  # full time for its announce-time check.
  CONFIG = {
    'tempo' => {
      name: 'Tempo',
      description: 'Tarif modulé selon la couleur du jour (Bleu, Blanc, Rouge) et les heures pleines ou creuses.',
      colors: [BLUE, WHITE, RED],
      day_for: ->(time) { (time.in_time_zone('Europe/Paris') - TEMPO_HP_START.hours).to_date },
      fetch: ->(time, date) {
        color = EDF.tempo_color_for(date, api: EDF::TEMPO_APIS[0])
        color = EDF.tempo_color_for(date, api: EDF::TEMPO_APIS[1]) if color <= UNKNOWN
        color
      }
    },
    'ejp' => {
      name: 'EJP',
      description: 'Tarif réduit la plupart des jours, plus élevé pendant les jours EJP (Effacement Jour Pointe).',
      colors: [GREEN, RED],
      day_for: ->(time) { time.in_time_zone('Europe/London').to_date },
      fetch: ->(time, date) { EDF::EJP_OFF_MONTH === date.month ? GREEN : EDF.ejp_color_for(time) }
    },
    'zen_flex' => {
      name: 'Zen Flex',
      description: 'Contrat privé EDF dont le nom complet est Zen Week-End - Option Flex. Tarif réduit la plupart des jours, plus élevé pendant les jours sobriété. Heures creuses durant 17h.',
      colors: [ECO, RED, BONIF, BONUS],
      day_for: ->(time) { time.in_time_zone('Europe/Paris').to_date },
      fetch: ->(time, date) { EDF.zen_flex_color_for(date) }
    },
    # No API: off-peak hours are specific to each customer, configured in device settings
    'hphc' => {
      name: 'HP / HC',
      description: "Deux tarifs selon l'horaire ; les heures creuses sont moins chères.",
      colors: [ECO, ORANGE]
    }
  }.freeze

  def self.cache_key(mode, date) = "#{mode}_color/#{date}"

  def self.name_for(mode)
    CONFIG.dig(mode.to_s, :name) || mode.to_s.upcase
  end

  def self.description_for(mode)
    CONFIG.dig(mode.to_s, :description)
  end

  def self.colors_for(mode)
    CONFIG.dig(mode.to_s, :colors) || []
  end

  def self.day_for(mode, time)
    calculator = CONFIG.dig(mode.to_s, :day_for)
    calculator ? calculator.call(time) : time.to_date
  end

  def self.set_manual_override(mode, date, color)
    key = cache_key(mode, date)
    color_int = color.to_i
    if color_int <= UNKNOWN || !colors_for(mode).include?(color_int)
      $cache.delete(key)
    else
      $cache.write(key, color_int, expires_in: 48.hours)
    end
  end

  # Single caching layer for all contracts: read the per-day cache (which manual
  # overrides also write into), else fetch fresh and cache it (unless UNKNOWN).
  def self.color_for(mode, time)
    config = CONFIG[mode.to_s]
    return UNKNOWN unless config&.dig(:fetch)

    date = config[:day_for].call(time)
    key = cache_key(mode, date)
    if color = $cache.read(key)
      return color
    end

    color = config[:fetch].call(time, date) || UNKNOWN
    $cache.write(key, color, expires_in: 3.hours) if color > UNKNOWN
    color
  end
end
