require_relative "edf"

module TempOrb
  def self.actions_for now, mode:, today: nil, tomorrow: nil
    case mode
    when 'ejp'
      # Timezone 1h en avance sur la France, pour simplifier la gestion de la fin à 1h (ca passe a minuit)
      now = now.in_time_zone('Europe/London')
      today = today&.to_i || EDF.cached_ejp_color_for(now)
      tomorrow = tomorrow&.to_i || EDF.cached_ejp_color_for(now.tomorrow)
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
        actions << syncAPI(now + SYNC_INTERVAL + rand(SYNC_INTERVAL))
        actions << error_noData(end_of_tomorrow)
      else
        # reduced sync interval to get the RED if announced earlier
        fast_sync_at = now + SYNC_INTERVAL/2 + rand(SYNC_INTERVAL/2)
        # or 15h max when the color is announced
        announce_at = now.change(hour: EJP_ANNOUNCE) + rand(1.minute) if now.hour < EJP_ANNOUNCE
        actions << syncAPI([fast_sync_at, announce_at].compact.min)
        actions << error_noData(end_of_today)
      end
    when 'tempo'
      now = now.in_time_zone('Europe/Paris')
      today = today&.to_i || EDF.cached_tempo_color_for(now)
      tomorrow = tomorrow&.to_i || EDF.cached_tempo_color_for(now.tomorrow)
      hp = now.hour.between?(TEMPO_HP_START, TEMPO_HP_END-1)
      end_of_today = (now.hour < TEMPO_HP_START ? now.change(hour: TEMPO_HP_START) : now.tomorrow.change(hour: TEMPO_HP_START))
      end_of_tomorrow = end_of_today + 1.day
      logger.info "[#{now}] Tempo HP: #{hp}, Today: #{COLOR_NAMES[today]} (→ #{end_of_today}), Tomorrow: #{COLOR_NAMES[tomorrow]} (→ #{end_of_tomorrow})"
      actions = [
        updateLEDs(today, tomorrow, fx: (hp && today == 3 ? "breathingRingHalf" : "none"), brightness: (hp ? 1 : 0.5)),
        syncAPI(now + SYNC_INTERVAL + rand(SYNC_INTERVAL)),
      ]
      if hp
        actions << updateLEDs(today, tomorrow, timing: now.change(hour: TEMPO_HP_END), brightness: 0.5)
      end
      if tomorrow != UNKNOWN
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today, fx: (tomorrow == 3 ? "breathingRingHalf" : "none"))
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today.change(hour: TEMPO_HP_END), brightness: 0.5)
        actions << error_noData(end_of_tomorrow)
      else
        actions << error_noData(end_of_today)
      end
    when 'zen_flex'
      now = now.in_time_zone('Europe/Paris')
      today = today&.to_i || EDF.cached_zen_flex_color_for(now)
      tomorrow = tomorrow&.to_i || EDF.cached_zen_flex_color_for(now.tomorrow)
      hp = ZENFLEX_HP_RANGES.any? { |s, e| now.hour.between?(s, e-1) }
      # Next HP/HC transition
      next_transition = ZENFLEX_HP_RANGES.map { |s, e| [now.change(hour: s), now.change(hour: e)] }.flatten
        .sort.find { _1 > now }
      end_of_today = now.end_of_day + 1.second # midnight = start of next day
      end_of_tomorrow = end_of_today + 1.day

      # GOLD_HP: bonus réduction conso HP → or + rouge, animation HP
      # GOLD_HC: bonus sur-conso HC → or + bleu, animation HC
      secondary_today = case today; when GOLD_HP then RED; when GOLD_HC then BLUE; end
      secondary_tomorrow = case tomorrow; when GOLD_HP then RED; when GOLD_HC then BLUE; end
      animate_today = today == RED || today == GOLD_HP ? hp : (today == GOLD_HC ? !hp : false)
      fx_today = animate_today ? "breathingRingHalf" : "none"

      logger.info "[#{now}] Zen Flex HP: #{hp}, Today: #{COLOR_NAMES[today]} (→ #{end_of_today}), Tomorrow: #{COLOR_NAMES[tomorrow]} (→ #{end_of_tomorrow})"

      actions = [
        updateLEDs(today, tomorrow, fx: fx_today, brightness: (hp ? 1 : 0.5), secondary: secondary_today),
      ]

      # Schedule all remaining HP/HC transitions for today
      ZENFLEX_HP_RANGES.each do |hp_start, hp_end|
        start_time = now.change(hour: hp_start)
        end_time = now.change(hour: hp_end)
        if start_time > now # upcoming HP start
          fx_hp = (today == RED || today == GOLD_HP) ? "breathingRingHalf" : "none"
          actions << updateLEDs(today, tomorrow, timing: start_time, fx: fx_hp, secondary: secondary_today)
        end
        if end_time > now # upcoming HC start
          fx_hc = today == GOLD_HC ? "breathingRingHalf" : "none"
          actions << updateLEDs(today, tomorrow, timing: end_time, brightness: 0.5, fx: fx_hc, secondary: secondary_today)
        end
      end

      if tomorrow != UNKNOWN
        secondary_tmr = case tomorrow; when GOLD_HP then RED; when GOLD_HC then BLUE; end
        # Midnight: switch to tomorrow's color (HC)
        fx_midnight = tomorrow == GOLD_HC ? "breathingRingHalf" : "none"
        actions << updateLEDs(tomorrow, UNKNOWN, timing: end_of_today, brightness: 0.5, fx: fx_midnight, secondary: secondary_tmr)
        # Tomorrow's HP/HC transitions
        ZENFLEX_HP_RANGES.each do |hp_start, hp_end|
          start_time = end_of_today.change(hour: hp_start)
          end_time = end_of_today.change(hour: hp_end)
          fx_hp = (tomorrow == RED || tomorrow == GOLD_HP) ? "breathingRingHalf" : "none"
          fx_hc = tomorrow == GOLD_HC ? "breathingRingHalf" : "none"
          actions << updateLEDs(tomorrow, UNKNOWN, timing: start_time, fx: fx_hp, secondary: secondary_tmr)
          actions << updateLEDs(tomorrow, UNKNOWN, timing: end_time, brightness: 0.5, fx: fx_hc, secondary: secondary_tmr)
        end
        actions << syncAPI(now + SYNC_INTERVAL + rand(SYNC_INTERVAL))
        actions << error_noData(end_of_tomorrow)
      else
        # Faster sync to get tomorrow's color, or wait for announce time
        fast_sync_at = now + SYNC_INTERVAL/2 + rand(SYNC_INTERVAL/2)
        announce_at = now.change(hour: ZENFLEX_ANNOUNCE) + rand(1.minute) if now.hour < ZENFLEX_ANNOUNCE
        actions << syncAPI([fast_sync_at, announce_at].compact.min)
        actions << error_noData(end_of_today)
      end
    else
      raise ArgumentError.new("Invalid mode: #{mode}")
    end
    actions
  end

  private

  def self.updateLEDs today, tomorrow, timing: nil, fx: "none", brightness: 1, secondary: nil
    top = {RGB: COLORS[today].map { (_1 * brightness).to_i }, FX: fx}
    top[:secondaryRGB] = COLORS[secondary].map { (_1 * brightness).to_i } if secondary
    { action: "updateLEDs", timing: timing&.utc&.iso8601 || "initial", topLEDs: top, bottomLEDs: {RGB: COLORS[tomorrow].map { (_1 * brightness).to_i }, FX: "none"}}
  end

  def self.syncAPI time
    { action: "syncAPI", timing: time.utc.iso8601 }
  end

  def self.error_noData time
    { action: "error_noData", timing: time.utc.iso8601 }
  end

  def self.logger = Sinatra::Application.logger
end