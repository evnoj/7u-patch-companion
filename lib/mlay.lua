-- draw elements on top of a script's UI

local Mlay = {}

-- UTILITIES
local function noop() end

-- MLAY
function Mlay:new(args)
  local self = setmetatable({},{__index=Mlay})
  local args = args==nil and {} or args

  self.elements = {}
  self.draw = args.draw or false
  self.fps = args.fps or 60
  self.depth = 0 -- protects against nested drawing calls

  return self
end

function Mlay:capture_redraw()
  local saved_update = screen.update
  self.script_canvas = screen.create_image(128, 64)

  -- set the created canvas defaults same as norns does
  screen.draw_to(self.script_canvas, function()
    screen.aa(0)
    screen.line_width(1)
    screen.font_face(1)
    screen.font_size(8)
  end)

  local script_redraw = norns.script.redraw
  self.script_redraw = function(...)
    local args = table.pack(...)
    screen.update = noop
    self.depth = self.depth + 1
    screen.draw_to(self.script_canvas, function() script_redraw(table.unpack(args, 1, args.n)) end)
    self.depth = self.depth - 1
    screen.update = saved_update
  end

  local script_refresh = norns.script.refresh
  self.script_refresh = function(...)
    local args = table.pack(...)
    screen.update = noop
    self.depth = self.depth + 1
    screen.draw_to(self.script_canvas, function() script_refresh(table.unpack(args, 1, args.n)) end)
    self.depth = self.depth - 1
    screen.update = saved_update
  end

  norns.script.redraw = function(...)
    self.script_redraw(...)
  end
  redraw = norns.script.redraw

  norns.script.refresh = function(...)
    self.script_refresh(...)

    -- depth tracks "nested" drawing calls
    -- this surfaced with eterna, which calls refresh from redraw
    -- since the mlay refresh runs `screen.clear`, this was getting called in eterna's canvas
    -- this ensures that our custom redrawing doesn't run in the script's canvas
    if self.depth == 0 then
      self:redraw()
    end
  end
  refresh = norns.script.refresh
end

function Mlay:redraw()
  screen.clear()
  screen.display_image(self.script_canvas, 0, 0)

  if self.draw then
    for _,e in pairs(self.elements) do
      if e.show then
        e.elem:redraw()
        screen.blend_mode(e.blend_mode)
        screen.display_image(e.elem.image, e.x, e.y)
      elseif e.fade_counter then
        e.fade_counter = e.fade_counter - 1
        if e.fade_counter <= 0 then
          e.fade_counter = nil
        else
          e.elem:redraw()
          screen.blend_mode(e.blend_mode)
          screen.display_image(e.elem.image, e.x, e.y)
        end
      end
    end
  end

  screen.update()
  screen.blend_mode('OVER') -- restore default blend mode
end

function Mlay:show_element(id)
  local e = self.elements[id]

  e.show = true
end

function Mlay:show_element_and_fade(id)
  local e = self.elements[id]

  e.fade_counter = e.fade_time * self.fps
end

function Mlay:hide_element(id)
  local e = self.elements[id]

  e.show = false
  e.fade_counter = nil
end

function Mlay:add_element(id, elem, x, y, show_on_update, fade_time, blend_mode)
  self.elements[id] = {
    elem = elem,
    x = x,
    y = y,
    show_on_update = show_on_update,
    fade_time = fade_time or 1,
    -- useful blend modes:
    -- SOURCE: completely replaces where it's drawn to, no transparency
    -- DIFFERENCE: XORs brightness, dark on bright content and bright on dark content
    -- LIGHTEN: shows only where it's brighter than the background
    -- ADD: accumulates brightness toward white
    -- DARKEN: mark darkens the background
    -- the default OVER will leave undrawn areas showing the underlying canvas
    blend_mode = blend_mode or 'OVER'
  }
end

function Mlay:update_element(id, args)
  local e = self.elements[id]
  if not e then return end

  for k,v in pairs(args) do
    e.elem[k] = v
  end
  e.elem.dirty = true

  if e.show_on_update then
    e.fade_counter = e.fade_time * self.fps
  end
end

return Mlay
