-- furiko
-- 4-track pendulum sequencer with awake logic & reverse fx
-- supports LIVEN Ambient Ø, Standard MIDI (GM), and Custom mapping
--
-- The screen is divided into 4 quadrants, assigning an independent pendulum to Ch1-Ch4.
-- Minimal, physics-focused visual interface.
-- Pendulums swing at asynchronous default speed ratios.
-- Ch1 & Ch4 trigger root/degree/octave tones to prevent harmonic clutter.
-- Chords dynamically adapt between major and minor scales to maintain clean harmony.
-- K1+K3 toggles Ch3 into Awake melody mode, displaying a dual-step sequencer.
-- K2 steps active pendulum count back and forth: 0 -> 1 -> 2 -> 3 -> 4 -> 3 -> 2 -> 1 -> 0.
-- Softcut half-speed reverse tape FX triggers probabilistically during melody mode.
--
-- K1 (hold) + K2: toggle SYNC mode (aligns to Ch2 speed/phase)
-- K1 (hold) + K3: toggle Ch3 AWAKE melody mode
-- K2: cycle active pendulum count (0 <-> 4)
-- K3: play / pause
-- E1: chord progression (transpose) / [AWAKE] mode select (STEP/LOOP/SOUND/OPTION)
-- E2: base speed / [AWAKE] parameter edit 1
-- E3: harmonic interval / [AWAKE] parameter edit 2

local SCALE_INTERVALS = {0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24}

-- Separate major and minor intervals for dynamic scale adaptation
local MAJOR_INTERVALS = {0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24}
local MINOR_INTERVALS = {0, 3, 5, 7, 10, 12, 15, 17, 19, 22, 24}

local MAJOR_SEMITONES = {0, 2, 4, 5, 7, 9, 11, 12}
local MINOR_SEMITONES = {0, 2, 3, 5, 7, 8, 10, 12}

-- Curated root notes based on C pentatonic for clean resonance
local ALLOWED_ROOTS = {36, 40, 43, 45, 48, 52, 55, 57, 60, 64, 67, 69, 72}
local root_names = {"C2", "E2", "G2", "A2", "C3", "E3", "G3", "A3", "C4", "E4", "G4", "A4", "C5"}

local is_playing = true
local shift_active = false 
local sync_active = false  
local ch3_melody_mode = false
local display_timer = 0    

-- --- [FX State Variables] ---
local fx_active = false
local fx_name = ""

-- --- [AWAKE Sequencer Variables] ---
local awake_mode = 1 -- 1: STEP, 2: LOOP, 3: SOUND, 4: OPTION
local awake_mode_names = {"STEP", "LOOP", "SOUND", "OPTION"}
local awake_one = {
  pos = 0,
  length = 8,
  data = {1, 0, 3, 5, 6, 7, 8, 7, 0, 0, 0, 0, 0, 0, 0, 0}
}
local awake_two = {
  pos = 0,
  length = 7,
  data = {5, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
}
local awake_edit_ch = 1 
local awake_edit_pos = 1
local awake_notes = {}
local awake_active_note = nil
local awake_clock = nil
local awake_step_count = 0 

-- --- [SOUND Mode / Softcut Delay Variables] ---
local awake_snd_sel = 1
local awake_snd_names = {"delay", "rate", "feedback", "pan"}
local awake_snd_params = {"delay", "delay_rate", "delay_feedback", "delay_pan"}
local NUM_AWAKE_SND_PARAMS = #awake_snd_params

local transpose_offsets = {0, 5, 9, 7}
local current_transpose_idx = 1
local chord_names = {"I (+0)", "IV (+5)", "VIm (+9)", "V (+7)"}

local degree_short_names = {"1st (+0)", "2nd (+2)", "3rd (+4)", "4th (+5)", "5th (+7)", "6th (+9)", "7th (+11)", "8th (+12)"}

-- Tracks pendulum count cycling direction (1: increasing, -1: decreasing)
local pends_direction = 1 

local p = {}
local DEFAULT_RATIOS = {1.0, 0.78, 0.59, 0.37}

for i = 1, 4 do
  local offset = (3 - i) * 12
  if i == 1 then offset = 12 end

  p[i] = {
    phase = 1.5 * math.pi,   
    speed_ratio = DEFAULT_RATIOS[i],
    bx = 0, by = 0,
    active_note = nil,
    last_pan = -1,
    last_level = -1,
    last_harmonic = -1, 
    last_cutoff = 64,   
    last_reso = 64,     
    trigger_flash = 0,
    trigger_level_boost = 0.0,
    last_triggered_note = nil,
    octave_offset = offset,
    arp_targets = {nil, nil, nil},
    arp_active_notes = {nil, nil, nil},
    arp_state = {false, false, false},
    last_arp_pattern = -1,
    melody_counter = 0,
    fx_counter = 0
  }
end

local midi_out_device = nil
local updating_profile = false

local function trigger_display()
  display_timer = 30
end

local function get_layer_ch(layer_idx)
  return params:get("layer_" .. layer_idx .. "_ch")
end

local function send_cc(param_name, val, layer_idx)
  if not midi_out_device then return end
  local cc_num = params:get(param_name)
  if cc_num and cc_num >= 0 then
    local ch = get_layer_ch(layer_idx)
    midi_out_device:cc(cc_num, val, ch)
  end
end

local function reset_all_midi()
  if not midi_out_device then return end
  local cc_pitch = params:get("cc_pitch")
  local cc_attack = params:get("cc_attack")
  for i = 1, 4 do
    local ch = get_layer_ch(i)
    if cc_pitch and cc_pitch >= 0 then
      midi_out_device:cc(cc_pitch, 64, ch)
    else
      midi_out_device:pitchbend(8192, ch)
    end
    if cc_attack and cc_attack >= 0 then
      midi_out_device:cc(cc_attack, 0, ch)
    end
  end
end

local function get_base_root()
  local idx = params:get("root_note_index")
  return ALLOWED_ROOTS[idx] or 48
end

local function get_transposed_root()
  local base_root = get_base_root()
  local offset = transpose_offsets[current_transpose_idx]
  return base_root + offset
end

local function get_current_intervals()
  if current_transpose_idx == 3 then return MINOR_INTERVALS else return MAJOR_INTERVALS end
end

local function get_current_semitones()
  if current_transpose_idx == 3 then return MINOR_SEMITONES else return MAJOR_SEMITONES end
end

local function build_awake_scale()
  local root = get_transposed_root() + p[3].octave_offset 
  local intervals = get_current_intervals()
  awake_notes = {}
  for octave = 0, 2 do
    for k = 1, #intervals do
      table.insert(awake_notes, root + intervals[k] + (octave * 12))
    end
  end
end

-- Initialize Softcut delay and dedicated reverse buffer
local function init_halfsecond()
  audio.level_cut(1.0)
  audio.level_adc_cut(1)
  audio.level_eng_cut(1)
  
  -- Voice 1: Standard halfsecond delay
  softcut.level(1, 1.0)
  softcut.level_slew_time(1, 0.25)
  softcut.level_input_cut(1, 1, 1.0)
  softcut.level_input_cut(2, 1, 1.0)
  softcut.pan(1, 0.0)

  softcut.play(1, 1)
  softcut.rate(1, 1)
  softcut.rate_slew_time(1, 0.25)
  softcut.loop_start(1, 1)
  softcut.loop_end(1, 1.5)
  softcut.loop(1, 1)
  softcut.fade_time(1, 0.1)
  softcut.rec(1, 1)
  softcut.rec_level(1, 1)
  softcut.pre_level(1, 0.75)
  softcut.position(1, 1)
  softcut.enable(1, 1)

  softcut.filter_dry(1, 0.125)
  softcut.filter_fc(1, 1200)
  softcut.filter_lp(1, 0)
  softcut.filter_bp(1, 1.0)
  softcut.filter_rq(1, 2.0)

  -- Voice 2: Dedicated half-speed reverse buffer
  softcut.enable(2, 1)
  softcut.buffer(2, 2)
  softcut.level(2, 0.0) 
  softcut.loop(2, 1)
  softcut.loop_start(2, 1)
  softcut.loop_end(2, 7)
  softcut.rec(2, 1)
  softcut.rec_level(2, 1.0)
  softcut.pre_level(2, 0.0)
  softcut.position(2, 1)
  softcut.rate(2, 1.0)
  softcut.level_input_cut(1, 2, 1.0)
  softcut.level_input_cut(2, 2, 1.0)
  softcut.pan(2, 0.0)

  params:add_separator("Tape Delay (halfsecond)")
  params:add_control("delay", "Delay Level", controlspec.new(0, 1, 'lin', 0, 0.5, ""))
  params:set_action("delay", function(x) softcut.level(1, x) end)

  params:add_control("delay_rate", "Delay Rate", controlspec.new(0.5, 2.0, 'lin', 0, 1, ""))
  params:set_action("delay_rate", function(x) softcut.rate(1, x) end)

  params:add_control("delay_feedback", "Delay Feedback", controlspec.new(0, 1.0, 'lin', 0, 0.75, ""))
  params:set_action("delay_feedback", function(x) softcut.pre_level(1, x) end)

  params:add_control("delay_pan", "Delay Pan", controlspec.new(-1, 1.0, 'lin', 0, 0, ""))
  params:set_action("delay_pan", function(x) softcut.pan(1, x) end)
end

-- Coroutine for triggering half-speed reverse FX
local function fx_reverse_routine()
  if fx_active then return end
  fx_active = true
  fx_name = "REVERSE"
  trigger_display()
  
  softcut.rec(2, 0)
  softcut.loop_start(2, 1)
  softcut.loop_end(2, 7)
  softcut.rate_slew_time(2, 0.1)
  softcut.rate(2, -0.5) 
  softcut.level(2, 1.2) 
  softcut.pan(2, 0.0)
  
  clock.sleep(6) 
  
  softcut.level(2, 0.0)
  softcut.rate(2, 1.0)
  softcut.rec(2, 1) 
  
  fx_active = false
  fx_name = ""
end

local function crossed_threshold(old, new, threshold)
  if old < new then
    return (old < threshold and new >= threshold)
  else 
    return (old < threshold or new >= threshold)
  end
end

function awake_clock_loop()
  while true do
    local base_speed = params:get("speed")
    local current_speed = base_speed * p[2].speed_ratio 
    
    if current_speed < 0.01 then current_speed = 0.01 end
    local step_duration = (1 / current_speed) / 16
    
    clock.sleep(step_duration)
    
    if is_playing and ch3_melody_mode and (params:get("active_pendulums") >= 3) then
      advance_awake_step()
    end
  end
end

function advance_awake_step()
  if not midi_out_device then return end

  build_awake_scale()

  awake_one.pos = awake_one.pos + 1
  if awake_one.pos > awake_one.length then awake_one.pos = 1 end
  awake_two.pos = awake_two.pos + 1
  if awake_two.pos > awake_two.length then awake_two.pos = 1 end

  if params:get("auto_chord_progression") == 2 then
    awake_step_count = awake_step_count + 1
    if awake_step_count % 32 == 0 then
      current_transpose_idx = (current_transpose_idx % #transpose_offsets) + 1
      trigger_display()
    end
  end

  local ch3 = get_layer_ch(3)

  if awake_active_note then
    midi_out_device:note_off(awake_active_note, 0, ch3)
    awake_active_note = nil
  end

  if awake_one.data[awake_one.pos] > 0 then
    local note_idx = awake_one.data[awake_one.pos] + awake_two.data[awake_two.pos]
    local note_num = awake_notes[util.clamp(note_idx, 1, #awake_notes)]

    if note_num then
      local swing_width = params:get("orbit_width")
      local velocity = math.floor(util.linlin(0.0, 1.0, 55, 95, swing_width))
      
      p[3].trigger_level_boost = 1.0 
      midi_out_device:note_on(note_num, velocity, ch3)
      awake_active_note = note_num
      p[3].trigger_flash = 3 
    end
  end
  redraw()
end

function init()
  params:add_separator("MIDI Device")
  local midi_device_names = {}
  for i = 1, #midi.vports do
    local name = midi.vports[i] and midi.vports[i].name or "none"
    table.insert(midi_device_names, string.format("%d: %s", i, name))
  end
  
  if #midi_device_names == 0 then
    table.insert(midi_device_names, "none")
  end
  
  local default_device = 1

  params:add_option("midi_out_device", "MIDI Out Device", midi_device_names, default_device)
  params:set_action("midi_out_device", function(idx)
    midi_out_device = midi.connect(idx)
    reset_all_midi() 
  end)

  params:add_separator("MIDI Profile & Mapping")
  params:add_option("midi_profile", "MIDI Profile", {"Ambient Ø", "Standard (GM)", "Custom"}, 1)

  local function cc_formatter(param)
    local v = param:get()
    return v == -1 and "Off" or string.format("CC %d", v)
  end

  local function on_custom_changed()
    if not updating_profile then
      params:set("midi_profile", 3)
    end
  end

  params:add_separator("Channel & CC Assignment")
  for i = 1, 4 do
    params:add_number("layer_" .. i .. "_ch", "Layer " .. i .. " Channel", 1, 16, i)
    params:set_action("layer_" .. i .. "_ch", on_custom_changed)
  end

  params:add_number("cc_pan", "Pan CC", -1, 127, 53, cc_formatter)
  params:set_action("cc_pan", on_custom_changed)

  params:add_number("cc_level", "Level/Volume CC", -1, 127, 52, cc_formatter)
  params:set_action("cc_level", on_custom_changed)

  params:add_number("cc_mod", "Modulation CC (Ch2)", -1, 127, 30, cc_formatter)
  params:set_action("cc_mod", on_custom_changed)

  params:add_number("cc_attack", "Attack CC", -1, 127, 40, cc_formatter)
  params:set_action("cc_attack", on_custom_changed)

  params:add_number("cc_pitch", "Pitch Reset CC", -1, 127, 32, cc_formatter)
  params:set_action("cc_pitch", on_custom_changed)

  params:set_action("midi_profile", function(profile)
    if profile == 3 then return end
    updating_profile = true
    if profile == 1 then
      -- Ambient Ø mapping
      for i = 1, 4 do params:set("layer_" .. i .. "_ch", i) end
      params:set("cc_pan", 53)
      params:set("cc_level", 52)
      params:set("cc_mod", 30)
      params:set("cc_attack", 40)
      params:set("cc_pitch", 32)
    elseif profile == 2 then
      -- Standard MIDI mapping
      for i = 1, 4 do params:set("layer_" .. i .. "_ch", i) end
      params:set("cc_pan", 10)       -- Standard Pan
      params:set("cc_level", 7)      -- Standard Main Volume
      params:set("cc_mod", 74)       -- Brightness / Filter Cutoff
      params:set("cc_attack", 73)    -- Attack Time
      params:set("cc_pitch", -1)     -- Uses standard pitchbend reset
    end
    updating_profile = false
    reset_all_midi()
  end)

  params:add_separator("Organism Settings")
  
  params:add_control("speed", "Base Speed (Hz)", controlspec.new(0.05, 4.0, "linear", 0.01, 0.13))
  params:set_action("speed", function(val)
    trigger_display()
    redraw()
  end)

  params:add_control("orbit_width", "Swing Width", controlspec.new(0.0, 1.0, "linear", 0.01, 1.0))
  params:set_action("orbit_width", function(val)
    trigger_display()
    redraw()
  end)

  params:add_option("root_note_index", "Root Key (Scale)", root_names, 5)
  params:set_action("root_note_index", function(idx)
    kill_all_notes() 
    trigger_display()
    redraw()
  end)
  
  params:add_option("harmonic_degree", "Harmonic Interval", 
    {"1st (Unison)", "2nd (+2st)", "3rd (+4st)", "4th (+5st)", "5th (+7st)", "6th (+9st)", "7th (+11st)", "8th (+12st)"}, 5)
  params:set_action("harmonic_degree", function(val)
    trigger_display()
    redraw()
  end)
  
  params:add_control("depth_intensity", "Depth Intensity", controlspec.new(0.0, 1.0, "linear", 0.05, 0.9))
  params:set_action("depth_intensity", function(val)
    trigger_display()
    redraw()
  end)

  params:add_separator("Song Progression")
  params:add_number("active_pendulums", "Active Pendulums", 0, 4, 0)
  params:set_action("active_pendulums", function(val)
    redraw()
  end)

  params:add_option("auto_chord_progression", "Auto Chord Progression", {"Off", "On"}, 2)

  params:add_separator("Auto Effects")
  params:add_control("fx_probability", "Reverse FX Probability (%)", controlspec.new(0, 100, 'lin', 1, 10, "%"))

  params:add_separator("Sync Settings")
  params:add_option("sync_to_ch2", "Sync to Ch2 Speed", {"Off", "On"}, 1)
  params:set_action("sync_to_ch2", function(val)
    sync_active = (val == 2)
    trigger_display()
    redraw()
  end)

  init_halfsecond()

  local fps = 20
  local dt = 1 / fps
  local timer = metro.init(function() update(dt) redraw() end, dt)
  timer:start()

  awake_clock = clock.run(awake_clock_loop)

  params:default()
end

function update(dt)
  if is_playing then
    local base_speed = params:get("speed")
    local orbit_width = params:get("orbit_width")
    local intensity = params:get("depth_intensity")
    local active_limit = params:get("active_pendulums") 

    for i = 1, 4 do
      if i <= active_limit then
        local target_ratio = DEFAULT_RATIOS[i]
        if sync_active then
          target_ratio = DEFAULT_RATIOS[2] 
        end

        local max_change = dt * 0.05
        if p[i].speed_ratio < target_ratio then
          p[i].speed_ratio = math.min(target_ratio, p[i].speed_ratio + max_change)
        elseif p[i].speed_ratio > target_ratio then
          p[i].speed_ratio = math.max(target_ratio, p[i].speed_ratio - max_change)
        end

        local current_speed = base_speed * p[i].speed_ratio
        local old_phase = p[i].phase

        if sync_active and i ~= 2 then
          local diff = p[2].phase - p[i].phase
          diff = (diff + math.pi) % (2 * math.pi) - math.pi
          old_phase = (old_phase + diff * 0.012) % (2 * math.pi)
        end

        p[i].phase = (old_phase + (current_speed * 2 * math.pi) * dt) % (2 * math.pi)

        local crossed_right = crossed_threshold(old_phase, p[i].phase, 0.5 * math.pi)
        local crossed_left = crossed_threshold(old_phase, p[i].phase, 1.5 * math.pi)

        if crossed_left or crossed_right then
          -- Check reverse FX probability every 5 round trips (10 boundary crossings) on Ch3
          if i == 3 and ch3_melody_mode then
            p[i].fx_counter = p[i].fx_counter + 1
            if p[i].fx_counter >= 10 then
              p[i].fx_counter = 0
              if not fx_active then
                local prob = params:get("fx_probability")
                if math.random(100) <= prob then
                  clock.run(fx_reverse_routine)
                end
              end
            end
          end

          if not (i == 3 and ch3_melody_mode) then
            trigger_note(i)
          else
            p[i].trigger_flash = 5 
          end
        end
      else
        p[i].phase = 1.5 * math.pi
        if p[i].active_note then release_note(i) end
        if i == 3 and awake_active_note then
          local ch3 = get_layer_ch(3)
          if midi_out_device then midi_out_device:note_off(awake_active_note, 0, ch3) end
          awake_active_note = nil
        end
      end

      if p[i].trigger_flash > 0 then p[i].trigger_flash = p[i].trigger_flash - 1 end

      local cx = (i % 2 == 1) and 32 or 96
      local cy = (i <= 2) and 2 or 34
      local arm_len = 22
      local max_angle = (math.pi / 3) * orbit_width
      local theta = max_angle * math.sin(p[i].phase)

      p[i].bx = cx + arm_len * math.sin(theta)
      p[i].by = cy + arm_len * math.cos(theta)

      if midi_out_device then
        local spatial_pan = 0
        local distance = 0
        if orbit_width > 0 then
          local max_val = arm_len * math.sin(max_angle)
          spatial_pan = util.clamp((p[i].bx - cx) / max_val, -1.0, 1.0)
          distance = util.clamp(math.abs(p[i].bx - cx) / max_val, 0.0, 1.0)
        end

        local pan_val = math.floor(util.clamp(64 + spatial_pan * 63, 0, 127))
        if p[i].last_pan == -1 or math.abs(pan_val - p[i].last_pan) >= 2 then
          send_cc("cc_pan", pan_val, i)
          p[i].last_pan = pan_val
        end

        local mod_factor = 1.0 - distance

        if i == 2 then
          local min_harmonic = math.floor(127 - (107 * intensity)) 
          local harmonic_val = math.floor(util.linlin(0.0, 1.0, min_harmonic, 127, mod_factor))
          if p[i].last_harmonic == -1 or math.abs(harmonic_val - p[i].last_harmonic) >= 2 then
            send_cc("cc_mod", harmonic_val, i)
            p[i].last_harmonic = harmonic_val
          end
        end

        if i == 1 or i == 2 then
          local arp_thresholds = {0.3, 0.6, 0.9} 
          local ch_i = get_layer_ch(i)
          for j = 1, 3 do
            if mod_factor > arp_thresholds[j] and not p[i].arp_state[j] then
               if p[i].arp_targets[j] then
                 local arp_vel = math.floor(util.linlin(0.0, 1.0, 40, 80, orbit_width))
                 send_cc("cc_attack", 95, i)
                 midi_out_device:note_on(p[i].arp_targets[j], arp_vel, ch_i)
                 p[i].arp_active_notes[j] = p[i].arp_targets[j]
               end
               p[i].arp_state[j] = true
            elseif mod_factor <= arp_thresholds[j] and p[i].arp_state[j] then
               if p[i].arp_active_notes[j] then
                 midi_out_device:note_off(p[i].arp_active_notes[j], 0, ch_i)
                 p[i].arp_active_notes[j] = nil
               end
               p[i].arp_state[j] = false
            end
          end
        end

        p[i].trigger_level_boost = math.max(0.0, p[i].trigger_level_boost - dt * 2.0)
        local level_factor = math.max(mod_factor, p[i].trigger_level_boost)

        local min_level = math.floor(127 - (87 * intensity))
        local level_val = math.floor(util.linexp(0.0, 1.0, min_level, 127, level_factor))
        level_val = math.floor(level_val * 0.7) 
        
        if p[i].last_level == -1 or math.abs(level_val - p[i].last_level) >= 2 then
          send_cc("cc_level", level_val, i)
          p[i].last_level = level_val
        end
      end
    end
  end

  if display_timer > 0 then display_timer = display_timer - 1 end
end

function trigger_note(i)
  if not midi_out_device then return end
  
  local root = get_transposed_root() 
  local octave_base = root + p[i].octave_offset
  local intervals = get_current_intervals()
  local ch = get_layer_ch(i)

  if i == 1 or i == 2 then
    local start_idx = math.random(1, 6)
    local notes = {
      intervals[start_idx],
      intervals[start_idx + 1],
      intervals[start_idx + 2],
      intervals[start_idx + 3]
    }
    
    local pattern_type
    repeat
      pattern_type = math.random(3)
    until pattern_type ~= p[i].last_arp_pattern
    p[i].last_arp_pattern = pattern_type
    
    if pattern_type == 2 then
      notes = { notes[4], notes[3], notes[2], notes[1] }
    elseif pattern_type == 3 then
      for idx = 4, 2, -1 do
        local r = math.random(idx)
        notes[idx], notes[r] = notes[r], notes[idx]
      end
    end
    
    local target_note = util.clamp(octave_base + notes[1], 0, 127)
    p[i].arp_targets[1] = util.clamp(octave_base + notes[2], 0, 127)
    p[i].arp_targets[2] = util.clamp(octave_base + notes[3], 0, 127)
    p[i].arp_targets[3] = util.clamp(octave_base + notes[4], 0, 127)
    
    for j = 1, 3 do
      if p[i].arp_active_notes[j] then
        midi_out_device:note_off(p[i].arp_active_notes[j], 0, ch)
        p[i].arp_active_notes[j] = nil
      end
      p[i].arp_state[j] = false
    end

    if p[i].active_note then midi_out_device:note_off(p[i].active_note, 0, ch) end

    local swing_width = params:get("orbit_width")
    local velocity = math.floor(util.linlin(0.0, 1.0, 50, 100, swing_width))
    p[i].trigger_level_boost = 1.0
    send_cc("cc_attack", 0, i)
    midi_out_device:note_on(target_note, velocity, ch)
    p[i].active_note = target_note
    p[i].last_triggered_note = target_note
    p[i].trigger_flash = 5

  else
    local degree_semitones = get_current_semitones()
    local degree_opt = params:get("harmonic_degree")
    local semitones = degree_semitones[degree_opt] or 0
    
    local target_semitones = 0
    local rand_val = math.random(4)
    if rand_val == 1 then target_semitones = 0
    elseif rand_val == 2 then target_semitones = semitones
    elseif rand_val == 3 then target_semitones = 12
    else target_semitones = semitones + 12 end
    local target_note = octave_base + target_semitones

    if i == 4 then
      while target_note < 31 do target_note = target_note + 12 end
      while target_note > 55 do target_note = target_note - 12 end
    end

    target_note = util.clamp(target_note, 0, 127)

    if p[i].active_note then midi_out_device:note_off(p[i].active_note, 0, ch) end

    local swing_width = params:get("orbit_width")
    local velocity = math.floor(util.linlin(0.0, 1.0, 50, 100, swing_width))
    p[i].trigger_level_boost = 1.0
    midi_out_device:note_on(target_note, velocity, ch)
    p[i].active_note = target_note
    p[i].last_triggered_note = target_note
    p[i].trigger_flash = 5
  end
end

function release_note(i)
  if midi_out_device then
    local ch = get_layer_ch(i)
    if p[i].active_note then
      midi_out_device:note_off(p[i].active_note, 0, ch)
      p[i].active_note = nil
    end
    for j = 1, 3 do
      if p[i].arp_active_notes[j] then
        midi_out_device:note_off(p[i].arp_active_notes[j], 0, ch)
        p[i].arp_active_notes[j] = nil
      end
      p[i].arp_state[j] = false
    end
  end
end

function kill_all_notes()
  if midi_out_device then
    for i = 1, 4 do release_note(i) end
    if awake_active_note then
      local ch3 = get_layer_ch(3)
      midi_out_device:note_off(awake_active_note, 0, ch3)
      awake_active_note = nil
    end
  end
end

function enc(n, d)
  if ch3_melody_mode then
    if n == 1 then
      awake_mode = util.clamp(awake_mode + d, 1, 4)
    elseif awake_mode == 1 then 
      if n == 2 then
        local max_len = (awake_edit_ch == 1) and awake_one.length or awake_two.length
        awake_edit_pos = util.clamp(awake_edit_pos + d, 1, max_len)
      elseif n == 3 then
        if awake_edit_ch == 1 then
          awake_one.data[awake_edit_pos] = util.clamp(awake_one.data[awake_edit_pos] + d, 0, 8)
        else
          awake_two.data[awake_edit_pos] = util.clamp(awake_two.data[awake_edit_pos] + d, 0, 8)
        end
      end
    elseif awake_mode == 2 then 
      if n == 2 then
        awake_one.length = util.clamp(awake_one.length + d, 1, 16)
      elseif n == 3 then
        awake_two.length = util.clamp(awake_two.length + d, 1, 16)
      end
    elseif awake_mode == 3 then 
      if n == 2 then params:delta(awake_snd_params[awake_snd_sel], d)
      elseif n == 3 then params:delta(awake_snd_params[awake_snd_sel+1], d) end
    elseif awake_mode == 4 then 
      if n == 2 then params:delta("speed", d) 
      elseif n == 3 then params:delta("root_note_index", d) end
    end
  else
    if n == 1 then
      current_transpose_idx = util.clamp(current_transpose_idx + d, 1, 4)
      trigger_display()
    elseif n == 2 then params:delta("speed", d)
    elseif n == 3 then params:delta("harmonic_degree", d) end
  end
  redraw()
end

function key(n, z)
  if n == 1 then shift_active = (z == 1) end

  if z == 1 then
    if ch3_melody_mode and not shift_active then
      if awake_mode == 1 then
        if n == 2 then
          awake_edit_ch = (awake_edit_ch == 1) and 2 or 1
          local max_len = (awake_edit_ch == 1) and awake_one.length or awake_two.length
          if awake_edit_pos > max_len then awake_edit_pos = max_len end
        elseif n == 3 then
          if awake_edit_ch == 1 then
            for j = 1, awake_one.length do awake_one.data[j] = math.random(0, 8) end
          else
            for j = 1, awake_two.length do awake_two.data[j] = math.random(0, 8) end
          end
        end
      elseif awake_mode == 2 then
        if n == 2 then
          awake_one.pos = 0; awake_two.pos = 0
        elseif n == 3 then
          awake_one.pos = math.floor(math.random() * awake_one.length)
          awake_two.pos = math.floor(math.random() * awake_two.length)
        end
      elseif awake_mode == 3 then
        if n == 2 then awake_snd_sel = util.clamp(awake_snd_sel - 2, 1, NUM_AWAKE_SND_PARAMS - 1)
        elseif n == 3 then awake_snd_sel = util.clamp(awake_snd_sel + 2, 1, NUM_AWAKE_SND_PARAMS - 1) end
      elseif awake_mode == 4 then
        if n == 2 then params:set("speed", 0.13) 
        elseif n == 3 then current_transpose_idx = (current_transpose_idx % #transpose_offsets) + 1 end
      end
      redraw()
      return
    end

    if n == 2 then
      if shift_active then
        local current_val = params:get("sync_to_ch2")
        params:set("sync_to_ch2", current_val == 1 and 2 or 1)
      else
        local cur_pends = params:get("active_pendulums")
        if pends_direction == 1 then
          if cur_pends < 4 then params:set("active_pendulums", cur_pends + 1)
          else pends_direction = -1; params:set("active_pendulums", cur_pends - 1) end
        else 
          if cur_pends > 0 then params:set("active_pendulums", cur_pends - 1)
          else pends_direction = 1; params:set("active_pendulums", cur_pends + 1) end
        end
      end
      redraw()
    elseif n == 3 then
      if shift_active then
        ch3_melody_mode = not ch3_melody_mode
        if awake_active_note then
          local ch3 = get_layer_ch(3)
          midi_out_device:note_off(awake_active_note, 0, ch3)
          awake_active_note = nil
        end
        release_note(3) 
        p[3].melody_counter = 0
        trigger_display()
      else
        is_playing = not is_playing
        trigger_display() 
        if is_playing then
          local active_limit = params:get("active_pendulums")
          for i = 1, 4 do
            p[i].phase = 1.5 * math.pi
            if i <= active_limit then trigger_note(i) end
          end
        else
          kill_all_notes()
        end
      end
      redraw()
    end
  end
end

function redraw()
  screen.clear()

  screen.level(3)
  screen.move(64, 0)
  screen.line(64, 64)
  screen.stroke()
  screen.move(0, 32)
  screen.line(128, 32)
  screen.stroke()

  local active_limit = params:get("active_pendulums")

  for i = 1, 4 do
    if i == 3 and ch3_melody_mode and active_limit >= 3 then
      local x_start = 6
      local step_w = 3.2

      if awake_mode == 3 then
        screen.level(5)
        screen.move(4, 40)
        screen.text(awake_snd_names[awake_snd_sel] .. ":")
        screen.level(15)
        screen.move(34, 40)
        screen.text(params:string(awake_snd_params[awake_snd_sel]))

        screen.level(5)
        screen.move(4, 52)
        screen.text(awake_snd_names[awake_snd_sel+1] .. ":")
        screen.level(15)
        screen.move(34, 52)
        screen.text(params:string(awake_snd_params[awake_snd_sel+1]))
        
        screen.level(5)
        screen.move(4, 62)
        screen.text("SND")
      elseif awake_mode == 4 then
        screen.level(5)
        screen.move(4, 40)
        screen.text("speed:")
        screen.level(15)
        screen.move(34, 40)
        screen.text(params:string("speed"))

        screen.level(5)
        screen.move(4, 52)
        screen.text("root:")
        screen.level(15)
        screen.move(34, 52)
        screen.text(params:string("root_note_index"))

        screen.level(5)
        screen.move(4, 62)
        screen.text("OPT")
      else
        screen.level(awake_mode == 2 and 8 or 3)
        screen.move(x_start + step_w, 46)
        screen.line(x_start + awake_one.length * step_w, 46)
        screen.stroke()

        screen.move(x_start + step_w, 62)
        screen.line(x_start + awake_two.length * step_w, 62)
        screen.stroke()

        if awake_mode == 1 then
          screen.level(15)
          local cur_y = (awake_edit_ch == 1) and 48 or 64
          screen.move(x_start + awake_edit_pos * step_w - 1, cur_y)
          screen.line_rel(2, 0)
          screen.stroke()
        end

        for s = 1, awake_one.length do
          local sx = x_start + s * step_w
          local sy = 46 - awake_one.data[s] * 1.5
          screen.move(sx, sy)
          screen.line_rel(2, 0)
          local is_active = (s == awake_one.pos)
          local has_data = (awake_one.data[s] > 0)
          local is_editing = (awake_mode == 1 and awake_edit_ch == 1 and s == awake_edit_pos)
          
          if is_active then screen.level(15)
          elseif is_editing then screen.level(11) 
          elseif has_data then screen.level(7)  
          else screen.level(2) end
          screen.stroke()
        end

        for s = 1, awake_two.length do
          local sx = x_start + s * step_w
          local sy = 62 - awake_two.data[s] * 1.5
          screen.move(sx, sy)
          screen.line_rel(2, 0)
          local is_active = (s == awake_two.pos)
          local has_data = (awake_two.data[s] > 0)
          local is_editing = (awake_mode == 1 and awake_edit_ch == 2 and s == awake_edit_pos)
          
          if is_active then screen.level(15)
          elseif is_editing then screen.level(11) 
          elseif has_data then screen.level(7)  
          else screen.level(2) end
          screen.stroke()
        end

        screen.level(5) 
        screen.move(4, 40)
        screen.text(awake_mode_names[awake_mode])
      end

    else
      local cx = (i % 2 == 1) and 32 or 96
      local cy = (i <= 2) and 2 or 34

      screen.level(6)
      screen.move(cx, cy)
      screen.line(p[i].bx, p[i].by)
      screen.stroke()

      if p[i].trigger_flash > 0 then
        screen.level(15)
        screen.circle(p[i].bx, p[i].by, 4)
        screen.fill()
      else
        screen.level(i <= active_limit and 12 or 4)
        screen.circle(p[i].bx, p[i].by, 2)
        screen.fill()
      end

      screen.level(8)
      screen.rect(cx - 1, cy - 1, 3, 3)
      screen.fill()
    end
  end

  if display_timer > 0 or fx_active then
    screen.level(15)
    screen.rect(34, 10, 60, 44) 
    screen.fill()
    screen.level(0)
    
    screen.move(64, 18)
    if not is_playing then screen.text_center("PAUSED")
    else screen.text_center(chord_names[current_transpose_idx]) end
    
    screen.move(64, 26)
    screen.text_center(degree_short_names[params:get("harmonic_degree")])
    
    screen.move(64, 34)
    if ch3_melody_mode then screen.text_center("Ch3: MELODY")
    else screen.text_center("Ch3: BACKING") end

    screen.move(64, 42)
    local dots = ""
    for d_idx = 1, 4 do
      if d_idx <= active_limit then dots = dots .. "•" else dots = dots .. "◦" end
      if d_idx < 4 then dots = dots .. " " end
    end
    screen.text_center("Pends: " .. dots)
    
    screen.move(64, 50)
    if fx_active then
      screen.text_center(fx_name)
    elseif sync_active then
      screen.text_center("• SYNC •")
    else
      screen.text_center("FREE")
    end
  end

  screen.update()
end

function cleanup()
  kill_all_notes()
  reset_all_midi()
end