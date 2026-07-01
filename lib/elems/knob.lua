local Knob = {}

function Knob:new(args)
  local self = setmetatable({},{__index=Knob})
  local args = args==nil and {} or args

  self.name = "knob"
  self.size = args.size or 20
  self.size_half = self.size / 2
  self.angle = 0 -- radians
  self.dirty = true

  self.image = screen.create_image(self.size, self.size)

  self:draw_init()

  return self
end

function Knob:draw_init()
  screen.draw_to(self.image, function()
    screen.clear()
    screen.level(15)
    screen.line_width(1)
  end)
end

function Knob:redraw()
  if self.dirty then
    screen.draw_to(self.image, function()
      screen.clear()
      screen.aa(1)
      local x_center = self.size_half
      local y_center = self.size_half
      screen.circle(x_center, y_center, self.size_half - 1); screen.stroke()
      local x_2 = x_center + math.cos(self.angle) * self.size_half
      local y_2 = y_center + math.sin(self.angle) * self.size_half

      screen.move(x_center, y_center)
      screen.line(x_2, y_2)
      screen.stroke()
    end)
    self.dirty = false
  end
end

function Knob:set_x(x)
  if x ~= self.x then
    if x > 1 or x < -1 then
      error("x must be between -1 and 1")
      return
    end

    self.x = x
    self.dirty = true
  end
end

function Knob:set_y(y)
  if y ~= self.y then
    if y > 1 or y < -1 then
      error("y must be between -1 and 1")
      return
    end

    self.y = y
    self.dirty = true
  end
end

return Knob

