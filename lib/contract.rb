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

  def self.manual_color_for(mode, date)
    ManualOverride.find_by(contract: mode.to_s, date: date)&.color
  end

  def self.set_manual_override(mode, date, color)
    color_int = color.to_i
    if color_int <= UNKNOWN
      ManualOverride.where(contract: mode.to_s, date: date).destroy_all
    else
      override = ManualOverride.find_or_initialize_by(contract: mode.to_s, date: date)
      override.update!(color: color_int)
    end
    # Purge cache for this day
    $cache.delete("#{mode}_color/#{date}")
  end

  def self.color_for(mode, time)
    date = day_for(mode, time)
    if (manual = manual_color_for(mode, date))
      return manual
    end
    fetcher = CONFIG.dig(mode.to_s, :fetcher)
    fetcher ? fetcher.call(time) : UNKNOWN
  end
end
