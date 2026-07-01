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

  return self
end

function Mlay:capture_redraw()
  local saved_update = screen.update
  self.script_canvas = screen.create_image(128, 64)
  local script_redraw = norns.script.redraw
  self.script_redraw = function()
    screen.update = noop
    screen.draw_to(self.script_canvas, script_redraw)
    screen.update = saved_update
  end

  norns.script.redraw = function(from_mod)
    if not from_mod then
      self.script_redraw()
    end
    self:redraw()
  end
  redraw = norns.script.redraw

  if self.draw_metro then
    metro.free(self.draw_metro.id)
  end

  self.draw_metro = metro.init(function()
    redraw(true)
  end, 1/60)
  self.draw_metro:start()
end

function Mlay:redraw()
  screen.clear()
  screen.display_image(self.script_canvas, 0, 0)

  for _,e in pairs(self.elements) do
    if e.show then
      e.elem:redraw()
      screen.display_image(e.elem.image, e.x, e.y)
    end
  end

  screen.update()
end

function Mlay:show_element(id)
  local e = self.elements[id]

  e.show = true

  if e.fade_metro then
    metro.free(e.fade_metro.id)
    e.fade_metro = nil
  end

  if e.fade_time then
    -- e.fade_metro = metro.init(function()
    --   e.show = false
    --   metro.free(e.fade_metro.id)
    --   e.fade_metro = nil
    -- end, e.fade_time, 1)
  end
end

function Mlay:hide_element(id)
  local e = self.elements[id]

  e.show = false
  if e.fade_metro then
    metro.free(e.fade_metro.id)
    e.fade_metro = nil
  end
end

function Mlay:add_element(id, elem, x, y, show_on_update, fade_time)
  self.elements[id] = {
    elem = elem,
    x = x,
    y = y,
    show_on_update = show_on_update,
    fade_time = fade_time
  }
end

function Mlay:update_element(id, args)
  local e = self.elements[id]
  for k,v in pairs(args) do
    e.elem[k] = v
  end
  e.elem.dirty = true

  if e.show_on_update then
    self:show_element(id)
  end
end

return Mlay
