require_relative "edf"

module Contract
  MODES = %w(tempo ejp zen_flex).freeze

  # Each day_for forces its own timezone rather than trusting the caller to have
  # already converted, so it gives the right answer no matter what zone `time` is in.
  #
  # fetch receives (time, date): tempo/zen_flex only need the date, EJP also needs the
  # full time for its announce-time check.
  CONFIG = {
    'tempo' => {
      name: 'Tempo',
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
      colors: [GREEN, RED],
      day_for: ->(time) { time.in_time_zone('Europe/London').to_date },
      fetch: ->(time, date) { EDF::EJP_OFF_MONTH === date.month ? GREEN : EDF.ejp_color_for(time) }
    },
    'zen_flex' => {
      name: 'Zen Flex',
      colors: [ECO, RED, BONIF, BONUS],
      day_for: ->(time) { time.in_time_zone('Europe/Paris').to_date },
      fetch: ->(time, date) { EDF.zen_flex_color_for(date) }
    }
  }.freeze

  def self.cache_key(mode, date) = "#{mode}_color/#{date}"

  def self.name_for(mode)
    CONFIG.dig(mode.to_s, :name) || mode.to_s.upcase
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
    return UNKNOWN unless config

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
