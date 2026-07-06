local util = require 'util'
local mod = require 'core/mods'
local modmenu = require '7u-patch-companion/lib/modmenu'
mlay=include("7u-patch-companion/lib/mlay"):new()
local coord=include("7u-patch-companion/lib/elems/coord")
local morphg=include("7u-patch-companion/lib/elems/morphg")
local knob=include("7u-patch-companion/lib/elems/knob")

-- BEGIN CONFIG VARIABLES
local debug_7u = false
local crow_script = "7u-patch-companion/crow/7u-patch-companion.lua"
-- local pubvar_save_location = "/home/we/dust/data/7u-patch-companion/saved.tbl"
local pset_restore_location = "/home/we/dust/data/7u-patch-companion/restore.pset"
local trackball_pointer_sensitivity = 0.005
-- END CONFIG VARIABLES

-- UTILITIES
local function debug_msg(s)
  if debug_7u then
    print("7u debug: "..s)
  end
end

function tup()
  require 'tools/tools'
end

-- UI ELEMENTS
local mg_info = morphg:new()
mlay:add_element(
  'mg_info',
  mg_info,
  128-mg_info.width,
  0,
  true,
  1,
  'SOURCE'
)

mlay:add_element(
  'trackball_coord',
  coord:new({
    size = 20,
    range = 5
  }),
  128-20,
  6,
  true,
  1,
  'SOURCE'
)

local knob_elem = knob:new({
  size = 20,
})
mlay:add_element(
  'knob',
  knob_elem,
  128-20,
  30,
  true,
  1,
  'SOURCE'
)

-- MOD MENU AND PARAMS
local menu = modmenu.new("my_mod_menu_id", mod.this_name)
local mod_params = menu.params

mod_params:add{
  id="draw_changes",
  name="draw changes",
  type="binary",
  behavior="toggle",
  default=1,
  action=function(v)
    if v == 0 then
      mlay.draw = false
    else
      mlay.draw = true
    end
  end
}

mod_params:add{
  id="morphagene_octave_offset",
  name="morphagene octave offset",
  type="number",
  min=-3,
  max=3,
  default=0,
  action=function(v)
    crow.public.morphagene_octave_offset = v
    mlay:update_element('mg_info', {octave=v})
  end
}

mod_params:add{
  id="morphagene_direction",
  name="morphagene direction",
  type="number",
  min=-1,
  max=1,
  default=1,
  action=function(v)
    crow.public.morphagene_direction = v
    mlay:update_element('mg_info', {direction=v})
  end
}

mod_params:add{
  id="crow_load_7u_script",
  name="load 7u companion to crow",
  type="binary",
  behavior="trigger",
  action=function()
    crow.clear()
    norns.crow.loadscript(crow_script, true)
    crow.public.discover()
  end,
}

mod_params:add{
  id="bang_params",
  name="bang mod params",
  type="binary",
  behavior="trigger",
  action=function() mod_params:bang() end
}

mod_params:add{
  id="trackball_x",
  name="trackball x",
  type="number",
  min=-5,
  max=5,
  default=0,
  action=function(v)
    crow.output[1].volts = v
    mlay:update_element('trackball_coord', {x=v})
  end
}
mod_params:hide("trackball_x")

mod_params:add{
  id="trackball_y",
  name="trackball y",
  type="number",
  min=-5,
  max=5,
  default=0,
  action=function(v)
    crow.output[2].volts = v
    mlay:update_element('trackball_coord', {y=v})
  end
}
mod_params:hide("trackball_y")

local function params_save()
  mod_params:write(pset_restore_location, "last")
end

local function params_restore()
  if not util.file_exists(pset_restore_location) then
    debug_msg("attempted to load "..pset_restore_location.." but file didn't exist")
    return
  end
  mod_params:read(pset_restore_location)
end

params_restore()
mod.menu.register(mod.this_name, menu)

-- CROW HOOKS
-- noop clock_enable, the crow script handles sending the clock sync events
norns.crow.clock_enable = function()
  -- original
  -- directly set the change event on crow so it conforms to old-style event names
  -- norns.crow.send[[
  --   input[1].change = function()
  --     tell('change',1,1)
  --   end
  --   input[1].mode('change',2,0.1,'rising')
  -- ]]
end

-- allow setting clock source to crow from from
norns.crow.events.clock_enable = function(enable)
  if enable then
    params:set("clock_source", 4) -- crow
  elseif params:get("clock_source") == 4 then
    params:set("clock_source", 1) -- internal
  end
end

-- prevent crow from being reset when loading a script or hotplugging
-- original at lua/core/crow.lua
norns.crow.init = function()
 norns.crow.reset_events()

  print("CROW INIT")
  norns.crow.public.discovered = function()
    if crow.public.clocked then
      params:set("clock_source", 4)
    end

    mod_params:bang()
  end
  norns.crow.add = function(id, name, dev)
    print(">>>>>> norns.crow.add / " .. id .. " / " .. name)
    crow.public.discover()
  end
  norns.crow.remove = function(id)
    params_save()

    if params:get("clock_source") == 4 then
      params:set("clock_source", 1)
    end
  end
  norns.crow.receive = function(...) print("crow:", ...) end

  norns.crow.public.reset()       -- clears only norns' LOCAL mirror + callbacks
  crow.public.discover()
end
norns.crow.init()

-- ENDGAME TRACKBALL
local endgame_handlers = {
  -- see lua/core/hid_events.lua for codes
  [0] = function(v) -- hid_events.codes.REL_X = 0x00
    mod_params:delta("trackball_x", trackball_pointer_sensitivity * v)
  end,
  [1] = function(v) -- hid_events.codes.REL_Y = 0x01
    -- y relative follows graphics convention of up = y decreases, we reverse this
    mod_params:delta("trackball_y", trackball_pointer_sensitivity * v * -1)
  end,
  [11] = function(v) -- also could check type == 2 (EV_REL), scroll
    mlay:update_element('knob', {angle = knob_elem.angle + v * -0.001})
    -- function `sd` must be implemented on crow side
    v = v * 0.001
    crow(string.format("sd(%.4g)", v))
  end,
  [59] = function(v) -- F1, mouse button top left
    if v == 1 then
      mod_params:delta("draw_changes", 1)
    end
  end,
  [60] = function(v) -- F2, mouse button top right
  end,
  [0x112] = function(v) -- middle mouse button, mouse button left upper
  end,
  [61] = function(v) -- F3, mouse button right upper
  end,
  [0x110] = function(v) -- left mouse button, mouse button left lower
  end,
  [0x111] = function(v) -- right mouse button, mouse button right lower
    -- crow.public.morphagene_direction = crow.public.morphagene_direction * -1
    if v == 1 then
      mod_params:set("morphagene_direction", mod_params:get("morphagene_direction") * -1)
    end
  end,
  [0x113] = function(v) -- BTN_SIDE, mouse button bottom left
  end,
  [0x114] = function(v) -- BTN_EXTRA, mouse button bottom right
    if v == 1 then
      mod_params:set("morphagene_octave_offset", 0)
    end
  end,
  [63] = function(v) -- F5, encoder 1 down
  end,
  [64] = function(v) -- F6, encoder 1 up
  end,
  [65] = function(v) -- F7, encoder 2 down
    -- crow.public.morphagene_octave_offset = crow.public.morphagene_octave_offset - 1
    if v == 1 then
      mod_params:delta("morphagene_octave_offset", -1)
    end
  end,
  [66] = function(v) -- F8, encoder 2 up
    -- crow.public.morphagene_octave_offset = crow.public.morphagene_octave_offset + 1
    if v == 1 then
      mod_params:delta("morphagene_octave_offset", 1)
    end
  end,
}

local function endgame_input(type, code, val)
  local func = endgame_handlers[code]
  if func then func(val) end
end

function set_endgame_event_handler()
  for _,device in pairs(hid.devices) do
    if (device.name == "endgame trackball") then
      device.event = endgame_input
    end
  end
end

-- hid.cleanup() nils every device/vport event handler
-- runs from from norns.script.clear() during script load and at boot
local orig_hid_cleanup = hid.cleanup
hid.cleanup = function()
  orig_hid_cleanup()
  set_endgame_event_handler()
end

-- MOD HOOKS
mod.hook.register("system_post_startup", "7u patch companion post startup", function()
  crow.public.discover()
  set_endgame_event_handler()
end)

mod.hook.register("script_post_init", "7u patch companion post init", function()
  mlay:capture_redraw()
  set_endgame_event_handler()
  crow.public.discover()
end)

mod.hook.register("system_pre_shutdown", "7u patch companion pre shutdown", function()
  params_save()
end)

