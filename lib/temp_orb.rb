require_relative "edf"
require_relative "contract"
require "solareventcalculator"

module TempOrb
  def self.actions_for now, mode:, settings: nil, today: nil, tomorrow: nil
    # reduced sync interval to get the color if announced earlier
    sync_at = now + SYNC_INTERVAL + rand(SYNC_INTERVAL/2)
    fast_sync_at = now + FAST_SYNC_INTERVAL + rand(FAST_SYNC_INTERVAL/2)
    case mode
    when 'ejp'
      # Timezone 1h en avance sur la France, pour simplifier la gestion de la fin à 1h (ca passe a minuit)
      now = now.in_time_zone('Europe/London')
      today = today&.to_i || Contract.color_for('ejp', now)
      tomorrow = tomorrow&.to_i || Contract.color_for('ejp', now.tomorrow)
      hp = now.hour.between?(EJP_HP_START, EJP_HP_END-1)
      end_of_today = now.change(hour: EJP_HP_END)
      end_of_tomorrow = end_of_today + 1.day
      logger.info "[#{now}] EJP HP: #{hp}, Today: #{COLOR_NAMES[today]} (→ #{end_of_today}), Tomorrow: #{COLOR_NAMES[tomorrow]} (→ #{end_of_tomorrow})"
      actions = [
        updateLEDs(today, tomorrow, fx: (hp && today == 3 ? "breathingRingHalf" : "none"), brightness: (hp ? 1 : 0.5)),
      ]
      if !hp
        actions << updateLEDs(today, tomorrow, timing: now.change(hour: EJP_HP_START), fx: (today == 3 ? "breathingRingHalf" : "none"))
      end
      if tomorrow != UNKNOWN
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today, brightness: 0.5)
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.change(hour: EJP_HP_START), fx: (tomorrow == 3 ? "breathingRingHalf" : "none"))
        actions << syncAPI(sync_at)
        actions << error_noData(end_of_tomorrow)
      else
        # or 15h max when the color is announced
        announce_at = now.change(hour: EJP_ANNOUNCE) + rand(1.minute) if now.hour < EJP_ANNOUNCE
        actions << syncAPI([fast_sync_at, announce_at].compact.min)
        actions << error_noData(end_of_today)
      end
    when 'tempo'
      now = now.in_time_zone('Europe/Paris')
      today = today&.to_i || Contract.color_for('tempo', now)
      tomorrow = tomorrow&.to_i || Contract.color_for('tempo', now.tomorrow)
      hp = now.hour.between?(TEMPO_HP_START, TEMPO_HP_END-1)
      end_of_today = (now.hour < TEMPO_HP_START ? now.change(hour: TEMPO_HP_START) : now.tomorrow.change(hour: TEMPO_HP_START))
      end_of_tomorrow = end_of_today + 1.day
      logger.info "[#{now}] Tempo HP: #{hp}, Today: #{COLOR_NAMES[today]} (→ #{end_of_today}), Tomorrow: #{COLOR_NAMES[tomorrow]} (→ #{end_of_tomorrow})"
      actions = [
        updateLEDs(today, tomorrow, fx: (hp && today == 3 ? "breathingRingHalf" : "none"), brightness: (hp ? 1 : 0.5)),
      ]
      if hp
        actions << updateLEDs(today, tomorrow, timing: now.change(hour: TEMPO_HP_END), brightness: 0.5)
      end
      if tomorrow != UNKNOWN
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today, fx: (tomorrow == 3 ? "breathingRingHalf" : "none"))
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.change(hour: TEMPO_HP_END), brightness: 0.5)
        actions << error_noData(end_of_tomorrow)
        actions << syncAPI(sync_at)
      else
        actions << error_noData(end_of_today)
        actions << syncAPI(fast_sync_at)
      end
    when 'zen_flex'
      now = now.in_time_zone('Europe/Paris')
      today = today&.to_i || Contract.color_for('zen_flex', now)
      tomorrow = tomorrow&.to_i || Contract.color_for('zen_flex', now.tomorrow)
      hp = ZENFLEX_HP_RANGES.any? { |s, e| now.hour.between?(s, e-1) }
      end_of_today = now.end_of_day + 1.second # midnight = start of next day
      end_of_tomorrow = end_of_today + 1.day

      # BONIF: bonus réduction conso HP → or + rouge, animation HP
      # BONUS: bonus sur-conso HC → or + bleu, animation HC
      fx_hc = today == BONUS ? "breathingRingHalf" : "none"
      fx_hp = (today == RED || today == BONIF) ? "breathingRingHalf" : "none"

      logger.info "[#{now}] Zen Flex HP: #{hp}, Today: #{COLOR_NAMES[today]} (→ #{end_of_today}), Tomorrow: #{COLOR_NAMES[tomorrow]} (→ #{end_of_tomorrow})"

      # Color/FX actions only (no brightness concern)
      actions = [
        updateLEDs(today, tomorrow, fx: (hp ? fx_hp : fx_hc)),
      ]
      ZENFLEX_HP_RANGES.each do |hp_start, hp_end|
        start_time = now.change(hour: hp_start)
        end_time = now.change(hour: hp_end)
        actions << updateLEDs(today, tomorrow, timing: start_time, fx: fx_hp) if start_time > now
        actions << updateLEDs(today, tomorrow, timing: end_time, fx: fx_hc) if end_time > now
      end

      if tomorrow != UNKNOWN
        fx_hc_tmr = tomorrow == BONUS ? "breathingRingHalf" : "none"
        fx_hp_tmr = (tomorrow == RED || tomorrow == BONIF) ? "breathingRingHalf" : "none"
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today, fx: fx_hc_tmr)
        ZENFLEX_HP_RANGES.each do |hp_start, hp_end|
          start_time = end_of_today.change(hour: hp_start)
          end_time = end_of_today.change(hour: hp_end)
          actions << updateLEDs(tomorrow, UNKNOWN, timing: start_time, fx: fx_hp_tmr)
          actions << updateLEDs(tomorrow, UNKNOWN, timing: end_time, fx: fx_hc_tmr)
        end
        actions << syncAPI(sync_at)
        actions << error_noData(end_of_tomorrow)
      else
        announce_at = now.change(hour: ZENFLEX_ANNOUNCE) + rand(1.minute) if now.hour < ZENFLEX_ANNOUNCE
        actions << syncAPI([fast_sync_at, announce_at].compact.min)
        actions << error_noData(end_of_today)
      end

      # Post-process: apply night dimming based on sunset/sunrise
      actions = apply_dimming(actions, now)
    when 'hphc'
      # No notion of day: top = current hour, bottom = next hour (HC turquoise, HP orange)
      now = now.in_time_zone('Europe/Paris')
      hc_periods = hc_periods_for(now, settings&.dig('hc_ranges') || [])
      if hc_periods.empty?
        logger.info "[#{now}] HP/HC not configured"
        return [updateLEDs(UNKNOWN, UNKNOWN), syncAPI(sync_at), error_noData(now)]
      end
      end_of_data = now + 2.days # schedule is static, no need to go further
      color_at = ->(time) { hc_periods.any? { _1.cover?(time) } ? ECO : ORANGE }
      changes = hc_periods.flat_map { [_1.begin, _1.end] }.uniq
        .select { color_at.(_1) != color_at.(_1 - 1.second) }
      # bottom ring changes 1h before the top one
      updates = changes.flat_map { [_1, _1 - 1.hour] }.uniq.sort.select { _1 > now && _1 < end_of_data }
      logger.info "[#{now}] HP/HC: #{COLOR_NAMES[color_at.(now)]}, next changes: #{changes.sort.select { _1 > now }.first(4).join(', ')}"

      actions = [now, *updates].map do |time|
        updateLEDs(color_at.(time), color_at.(time + 1.hour), timing: (time unless time == now))
      end
      actions << syncAPI(sync_at)
      actions << error_noData(end_of_data)
      actions = apply_dimming(actions, now)
    else
      raise ArgumentError.new("Invalid mode: #{mode}")
    end
    actions
  end

  private

  # Off-peak periods around now as time ranges, from [["22:00", "06:00"], ...] settings
  def self.hc_periods_for now, ranges
    (-1..2).flat_map do |offset|
      day = now.beginning_of_day + offset.days
      ranges.map do |range|
        start_time, end_time = range.map { |hm| h, m = hm.split(':').map(&:to_i); day.change(hour: h, min: m) }
        end_time += 1.day if end_time <= start_time # crosses midnight
        start_time...end_time
      end
    end
  end

  def self.updateLEDs today, tomorrow, timing: nil, fx: "none", brightness: 1
    top = {**color_codes(today, brightness:), FX: fx}
    bottom = {**color_codes(tomorrow, brightness:), FX: "none"}
    { action: "updateLEDs", timing: timing&.utc&.iso8601 || "initial", topLEDs: top, bottomLEDs: bottom}
  end

  def self.color_codes code, brightness: 1
    ajusted = COLORS[code].map { (_1 * brightness).to_i }
    out = {RGB: ajusted[0..2]}
    out[:secondaryRGB] = ajusted[3..5] if ajusted.size == 6
    out
  end

  def self.syncAPI time
    { action: "syncAPI", timing: time.utc.iso8601 }
  end

  def self.error_noData time
    { action: "error_noData", timing: time.utc.iso8601 }
  end

  def self.apply_dimming(actions, now)
    now = now.in_time_zone('Europe/Paris')
    sunrise, sunset = sun_times(now.to_date)

    time_of = ->(action) {
      action[:timing] == "initial" ? now : Time.parse(action[:timing])
    }

    led_actions, other_actions = actions.partition { _1[:action] == "updateLEDs" }

    # Sunset/sunrise transition markers (today + tomorrow)
    sun_markers = [
      now.change(hour: sunrise.hour, min: sunrise.min),
      now.change(hour: sunset.hour, min: sunset.min),
      (now + 1.day).change(hour: sunrise.hour, min: sunrise.min),
      (now + 1.day).change(hour: sunset.hour, min: sunset.min),
    ].select { _1 > now }

    events = led_actions.map { |a| [time_of.(a), :led, a] }
    sun_markers.each { |t| events << [t, :sun, nil] }
    events.sort_by!(&:first)

    result = []
    current_leds = nil

    events.each do |time, type, action|
      tod = time.in_time_zone('Europe/Paris').seconds_since_midnight
      during_night = (tod >= sunset.seconds_since_midnight || tod < sunrise.seconds_since_midnight)
      if type == :led
        current_leds = action.slice(:topLEDs, :bottomLEDs, :FX).deep_dup
        result << (during_night ? dim_action(action) : action)
      elsif type == :sun && current_leds
        transition = { action: "updateLEDs", timing: time.utc.iso8601, **current_leds.deep_dup }
        result << (during_night ? dim_action(transition) : transition)
      end
    end

    # remove duplication (sunrise/sunset aligned with existing changes)
    (result + other_actions).uniq
  end

  def self.dim_action(action)
    { **action, topLEDs: dim_leds(action[:topLEDs]), bottomLEDs: dim_leds(action[:bottomLEDs]) }
  end

  def self.dim_leds(leds)
    result = { RGB: leds[:RGB].map { _1 / 2 }, FX: leds[:FX] }
    result[:secondaryRGB] = leds[:secondaryRGB].map { _1 / 2 } if leds[:secondaryRGB]
    result
  end

  def self.sun_times(date, min: 20, max: 8)
    calc = SolarEventCalculator.new(date, LATITUDE, LONGITUDE)
    sunrise = calc.compute_official_sunrise('Europe/Paris').to_time.in_time_zone('Europe/Paris')
    sunset = calc.compute_official_sunset('Europe/Paris').to_time.in_time_zone('Europe/Paris')
    # Clamp: sunset no earlier than min (last HP end), sunrise no later than max (first HP start)
    sunset = [sunset, sunset.change(hour: min, min: 0)].max
    sunrise = [sunrise, sunrise.change(hour: max, min: 0)].min
    [sunrise, sunset]
  end

  def self.logger = Sinatra::Application.logger
end
