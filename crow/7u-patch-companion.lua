-- the patch I run on my 7U
-- crow has a txi connected to it
-- requires my firmware fork: https://github.com/evnoj/crow-ev
    -- "spinner" output mode
    -- telexi "all" command support
        -- also requires telexi fork: https://github.com/evnoj/telex-ev

-- generates a rising or falling sawtooth wave to perform clickless "circular"
-- modulation of SPOT, similar to what the attenuverter does with no cable inserted
-- currently no "magnetic attractor" mechanism like the built-in spinner

-- crow input 1 is spinner speed, -5V-5V, negative is clockwise, positive ccw (and then inverted by spot attenuverter to make positve clockwise and negative ccw)
    -- adds to speed set by knobs 1/2
    -- "0.5V/o" scaling - speed doubles/halves with 0.5v changes
-- crow input 2 is clock
-- crow output 3 is spinner, plug into spot cv jack on silhouette
    -- on mine, this only works clickless if the attenuverter is fully ccw (negative)
    -- this means that the clockwise/counterclockwise are swapped for this script
-- crow output 4 goes to morphagene

-- txi param 1: spinner speed coarse
-- txi param 2: morphagene scale selector (quantizer for txi in 2)
    -- noon is 1x forward playback
    -- clockwise from noon is forward, counterclockwise inverts signal
    -- 3 scales:
        -- octaves
        -- octaves and fifths
        -- chromatic

-- txi cv 1: spinner fine control, +5V is double speed -5V is half speed, plug in bipolar offset from quadratt/duatt
-- txi cv 2: morphagene v/o pitch input, quantized
    -- takes -4V to +4V, negative is reverse playback, positive fwd, 0 is stopped

-- CONFIGURATION VARIABLES
clock_in = 2 -- crow input for clock signal

-- spinner
spinner_out = 3 -- the crow output that the spinner uses
-- bottom and top of spinner voltage range
bottom = -5.0
top = 5.0
-- min time in ms for a cycle, max time is 1024*min
time_min = 40

-- morphagene control
morphagene_varispeed_out = 4 -- the output to go to morphagene

-- TABLES
spinner_clock_div_table = {
    1/1,  -- placeholder
    16/1, -- 16.000,  0.25 - 0.50
    8/1,  --  8.000,  0.50 - 0.75
    6/1,  --  6.000,  0.75 - 1.00
    4/1,  --  4.000,  1.00 - 1.25
    3/1,  --  3.000,  1.25 - 1.50
    2/1,  --  2.000,  1.50 - 1.75
    3/2,  --  1.500,  1.75 - 2.00
    4/3,  --  1.333,  2.00 - 2.25
    5/4,  --  1.250,  2.25 - 2.50
    1/1,  --  1.000,  2.50 - 2.75
    4/5,  --  0.800,  2.75 - 3.00
    3/4,  --  0.750,  3.00 - 3.25
    2/3,  --  0.666,  3.25 - 3.50
    1/2,  --  0.500,  3.50 - 3.75
    1/3,  --  0.333,  3.75 - 4.00
    1/4,  --  0.250,  4.00 - 4.25
    1/6,  --  0.166,  4.25 - 4.50
    1/8,  --  0.125,  4.50 - 4.75
    1/16, --  0.062,  4.75 - 5.00
}

-- PUBLIC VARIABLES
public{morphagene_octave_offset = 0}:range(-3,3)
public{morphagene_direction = 1}:range(-1,1)
public{clocked = 0}:type('@int') -- 0 is unclocked, 1 is clocked
local clock_in_div_cached = public.clock_in_div
local function update_clock_in_div(div)
    if div ~= clock_in_div_cached then
        clock_in_div_cached = div

        if input[clock_in]._mode == 'clock' then
            input[clock_in].mode('clock', div)
        end
    end
end
public{clock_in_div = 1/4}:action(update_clock_in_div)
public{clock_norns_div = 1/4}

-- UTILITIES
-- truncates digits after thousandths place
local function truncate(num)
    return math.floor(num * 1000) / 1000
end

local function clamp(x, min, max)
    return x < min and min or (x > max and max or x)
end

-- returns 1 if x >= 0, else -1
local function sign(x)
    return x >= 0 and 1
        or x < 0 and 1
end

local function round(x)
    return math.floor(x + 0.5)
end

-- takes a sorted table where values are numbers and finds the nearest number to the value
-- returns high in event of a tie
local function bsearch(t, left, right, val)
    if right - left <= 1 then
        local left_val = t[left]
        local right_val = t[right]
        local dist_left = math.abs(val - left_val)
        local dist_right = math.abs(val - right_val)

        if dist_left < dist_right then
            return left_val
        else
            return right_val
        end
    end

    local mid = math.floor((left + right) / 2)
    if t[mid] < val then
        return bsearch(t, mid, right, val)
    elseif t[mid] > val then
        return bsearch(t, left, mid, val)
    else
        return t[mid]
    end
end

-- CLOCKWORK
local function send_clock_to_norns()
    while true do
        clock.sync(public.clock_norns_div)
        tell('change', 1, 1)
    end
end

function await_clock()
    input[clock_in].mode( 'change', 3, 0.1, 'rising' )
    input[clock_in].change = function()
        input[clock_in].mode( 'clock', public.clock_in_div)
        output[spinner_out].clocked = true
        public.clocked = 1
        tell('clock_enable', quote(true))
        clock_norns = clock.run(send_clock_to_norns)
        clock_timeout_checker:start()
    end
end

clock_timeout_checker = metro.init{
    event = function()
        if clock.time_since_last_input() > 4 then -- 4 second timeout
            clock_timeout_checker:stop()
            output[spinner_out].clocked = false
            public.clocked = 0
            tell('clock_enable', quote(false))
            clock.cancel(clock_norns)
            await_clock()
        end
    end,
    time  = 1.0,
    count = -1
}

-- SPINNER
-- p is 0-1
-- dir is -1 for ccw, 1 for clockwise, 0 for stopped
function update_time_free(p, dir)
    local t = time_min * 2^((1-p) * 10)
    output[spinner_out].time = t
    output[spinner_out].direction = dir
end

function update_time_synced(p, dir)
    output[spinner_out].direction = dir

    local idx = math.ceil(p * 20)
    div = spinner_clock_div_table[idx]
    if div then
        output[spinner_out].spinner_clock_div = div
    end
end

function time_parameter_handler(volts)
    local p = txi_vals.rate_multiplier*(volts*txi_vals.rate_attenuverter + txi_vals.rate_offset) / 5
    p = truncate(p)
    p = clamp(p, -1, 1)

    local dir = -1
    -- center deadzone
    if p <= -0.05 then
        dir = 1
        p = math.abs(p)
    elseif p < 0.05 then
        p = 0
        dir = 0
    end

    if not output[spinner_out].clocked then
        update_time_free(p, dir)
    else
        update_time_synced(p, dir)
    end
end

local spinner_delta_sens = 0.1
function sd(delta)
    output[spinner_out]:delta_phase_offset(delta * spinner_delta_sens)
end

function set_spinner_delta_sens(sens)
    spinner_delta_sens = sens
end

-- MORPHAGENE
morphagene_pitch_map = {
    [-48]=0,  -- +1 octave reverse
    [-47]=0.18699,
    [-46]=0.26199,
    [-45]=0.324,
    [-44]=0.38650,
    [-43]=0.45050,
    [-42]=0.52350,
    [-41]=0.58600,
    [-40]=0.65000,
    [-39]=0.72100,
    [-38]=0.77350,
    [-37]=0.84750,
    [-36]=0.91050, -- 1x playback reverse
    [-35]=0.98350,
    [-34]=1.04699,
    [-33]=1.10799,
    [-32]=1.17849,
    [-31]=1.23150,
    [-30]=1.31400,
    [-29]=1.377,
    [-28]=1.4385,
    [-27]=1.51400,
    [-26]=1.57650,
    [-25]=1.6395,
    [-24]=1.70150, -- -1 octave reverse
    [-23]=1.77600,
    [-22]=1.83850,
    [-21]=1.89100,
    [-20]=1.95300,
    [-19]=2.02500,
    [-18]=2.10299,
    [-17]=2.16450,
    [-16]=2.21950,
    [-15]=2.30418,
    [-14]=2.36568,
    [-13]=2.43968,
    [-12]=2.48168, -- -2 octaves reverse
    [-11]=2.56518,
    [-10]=2.63818,
    [-9]=2.70068,
    [-8]=2.75868,
    [-7]=2.81318,
    [-6]=2.88268,
    [-5]=2.95768,
    [-4]=3.03118,
    [-3]=3.09418,
    [-2]=3.14118,
    [-1]=3.22718,
    [0]=3.31518, -- stopped
    [1]=3.42518,
    [2]=3.47518,
    [3]=3.55218,
    [4]=3.62368,
    [5]=3.68668,
    [6]=3.75268,
    [7]=3.80168,
    [8]=3.88918,
    [9]=3.95268,
    [10]=4.01268,
    [11]=4.07668,
    [12]=4.13318, -- -2 octaves
    [13]=4.21168,
    [14]=4.26068,
    [15]=4.34768,
    [16]=4.41118,
    [17]=4.47318,
    [18]=4.54168,
    [19]=4.59368,
    [20]=4.67768,
    [21]=4.74068,
    [22]=4.79318,
    [23]=4.87768,
    [24]=4.92968, -- -1 octave
    [25]=5.00368,
    [26]=5.06568,
    [27]=5.13768,
    [28]=5.20118,
    [29]=5.25168,
    [30]=5.33668,
    [31]=5.38018,
    [32]=5.46368,
    [33]=5.53668,
    [34]=5.60118,
    [35]=5.66368,
    [36]=5.72618, -- 1x playback
    [37]=5.79768,
    [38]=5.86318,
    [39]=5.92568,
    [40]=5.99718,
    [41]=6.06168,
    [42]=6.12518,
    [43]=6.17818,
    [44]=6.26018,
    [45]=6.32368,
    [46]=6.39568,
    [47]=6.45968,
    [48]=6.66, -- +1 octave
}

-- each function takes a number representing current voltage as a 12TET note number (voltage * 12)
-- returns the quantized note number for that scale
-- caller is responsible for
morphagene_quantizers = {
    -- 1x playback
    [0] = function(note)
        if note >= 0 then
            return 36
        else
            return -36
        end
    end,
    -- octaves
    [1] = function(note)
        local scale = {-48, -36, -24, -12, 0, 12, 24, 36, 48}
        return bsearch(scale, 1, #scale, note)
    end,
    -- octaves/fifths
    [2] = function(note)
        local scale = {-48, -43, -36, -31, -24, -19, -12, -7, 0, 7, 12, 19, 24, 31, 36, 43, 48}
        return bsearch(scale, 1, #scale, note)
    end,
    -- chromatic
    [3] = function(note)
        return round(note)
    end
}
for i=1,#morphagene_quantizers do
    morphagene_quantizers[i * -1] = function(note)
        return -1 * morphagene_quantizers[i](note)
    end
end
morphagene_quantizer_active = morphagene_quantizers[0]
morphagene_prev_note = 0

-- TXI
txi_vals = {
    -- param = {},
    -- ['in'] = {}
}
-- for i=1,4 do
--     txi_vals.param[i] = 0
--     txi_vals.cv[i] = 0
-- end
txi_vals.rate_offset = 0
txi_vals.rate_offset_fine = 0
txi_vals.rate_attenuverter = 0
txi_vals.rate_attenuverter_offset = 0
txi_vals.rate_multiplier = 1
txi_vals.rate_multiplier = 1

-- receives table where values 1-4 are params 1-4, 5-8 are ins 1-4
ii.txi.event = function(e, data)
    for i=1,8 do
        local handler = txi_poll_handlers[i]
        if handler then
            handler(data[i])
        end
    end
end

txi_poll_handlers = {
    -- param 1
    [1] = function(v)
        txi_vals.rate_offset = v + txi_vals.rate_offset_fine
    end,
    -- param 2
    [2] = function(v)
        local v = math.ceil(v)
        morphagene_quantizer_active = morphagene_quantizers[math.ceil(v)]
    end,
    -- param 3
    [3] = function(v)
    end,
    -- in 1
    [5] = function(v)
        -- virtual noon notch
        if not (v <= -0.1 or v >= 0.1) then
            -- print('notcho')
            v = 0
        -- -5V notch
        elseif not (v <= -0.55 or v >= -0.45) then
            v = -0.5
        -- 5V notch
        elseif not (v <= 0.45 or v >= 0.55) then
            v = 0.5
        end
        txi_vals.rate_offset_fine = v
    end,
    -- in 2, morphagene v/oct input
    -- corresponds to voltage
    [6] = function(v)
        v = clamp(v, -4, 4)
        local note = v * 12
        note = morphagene_quantizer_active(note)

        if note > 0 then
            note = note + 12 * public.morphagene_octave_offset
            if note <= 0 then
                note = note + 12 * (1 + note // -12)
            end
        elseif note < 0 then
            note = note - 12 * public.morphagene_octave_offset
            if note >= 0 then
                note = note - 12 * (1 + note // 12)
            end
        end

        note = note * public.morphagene_direction

        if note ~= morphagene_prev_note then
            morphagene_prev_note = note
            output[morphagene_varispeed_out].volts = morphagene_pitch_map[note]
        end
    end,
    -- in 3
    [7] = function(v)
    end,
}

txi_metro = metro.init{
    time  = 0.01,
    count = -1,
    event = function()
        ii.txi.get('all')
    end,
}

function init()
    ii.fastmode(true)

    -- delay on powerup to wait for txi to be initialized
    clock.run(function()
        clock.sleep(1)
        -- param 1: spinner speed/direction coarse, offset for crow input 1
        ii.txi.param_bot(1, -5.01) -- slight error needs to be compensated for
        ii.txi.param_top(1, 5.01)
        -- param 2: morphagene scale selector
        ii.txi.param_bot(2, -3.999)
        ii.txi.param_top(2, 3)
        -- param 3: attenuverter for crow input 1
        ii.txi.param_bot(3, -1)
        ii.txi.param_top(3, 1)
        -- in 1: spinner fine control
        ii.txi.in_bot(1, -1)
        ii.txi.in_top(1, 1)

        -- wait for txi param changes to take effect
        clock.sleep(0.1)

        txi_metro:start()

        input[1].mode( 'stream', 0.001 )
        input[1].stream = time_parameter_handler

        output[spinner_out].mode = "spinner"
        output[spinner_out].bottom = bottom
        output[spinner_out].top = top

        await_clock()
    end)
end

