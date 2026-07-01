local Coord = {}

function Coord:new(args)
  local self = setmetatable({},{__index=Coord})
  local args = args==nil and {} or args

  self.name = "coord"
  self.size = args.size or 20
  self.coord_space = self.size - 2
  self.size_half = self.size / 2
  -- distance from origin to edge of drawn space
  self.range = args.range or 1
  self.scale = (self.coord_space / 2) / self.range
  -- x coord of drawn point, -1 to 1
  self.x = 0
  -- y coord of drawn point, -1 to 1
  self.y = 0
  self.dirty = true

  self.image = screen.create_image(self.size, self.size)

  self:draw_init()

  return self
end

function Coord:draw_init()
  screen.draw_to(self.image, function()
    screen.clear()
    screen.level(15)
    screen.aa(1)
    screen.line_width(1)
  end)
end

function Coord:redraw()
  if self.dirty then
    screen.draw_to(self.image, function()
      screen.clear()
      screen.rect(0, 0, self.size, self.size); screen.stroke()
      local x = self.size_half + self.x * self.scale
      local y = self.size_half + self.y * self.scale * -1
      screen.circle(x, y, 1); screen.fill()
    end)
    self.dirty = false
  end
end

return Coord
