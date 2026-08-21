require_relative "edf"

module Contract
  MODES = %w(tempo ejp zen_flex).freeze

  CONFIG = {
    'tempo' => {
      name: 'Tempo',
      colors: [BLUE, WHITE, RED],
      day_for: ->(time) { (time.in_time_zone('Europe/Paris') - TEMPO_HP_START.hours).to_date },
      fetcher: ->(time) { EDF.cached_tempo_color_for(time) }
    },
    'ejp' => {
      name: 'EJP',
      colors: [GREEN, RED],
      day_for: ->(time) { time.in_time_zone('Europe/London').to_date },
      fetcher: ->(time) { EDF.cached_ejp_color_for(time) }
    },
    'zen_flex' => {
      name: 'Zen Flex',
      colors: [ECO, RED, BONIF, BONUS],
      day_for: ->(time) { time.in_time_zone('Europe/Paris').to_date },
      fetcher: ->(time) { EDF.cached_zen_flex_color_for(time) }
    }
  }.freeze

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
    key = "#{mode}_color/#{date}"
    color_int = color.to_i
    if color_int <= UNKNOWN
      $cache.delete(key)
    else
      $cache.write(key, color_int, expires_in: 48.hours)
    end
  end

  def self.color_for(mode, time_or_date)
    date = time_or_date.is_a?(Date) ? time_or_date : day_for(mode, time_or_date)
    fetcher = CONFIG.dig(mode.to_s, :fetcher)
    fetcher ? fetcher.call(date) : UNKNOWN
  end
end
