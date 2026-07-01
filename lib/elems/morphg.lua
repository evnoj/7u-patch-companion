-- shows octave offset and direction, intended for showing state of morphagene control
local Morphg = {}

-- CONFIG VARIABLES
-- choose a monospace bmp font
-- vars should be set to match the chosen font by referring to the font file
-- see resources/bmp/
local font_face = 25 -- tom-thumb
local font_height = 6 -- PIXEL_SIZE
local font_ascent = 5 -- FONT_ASCENT
local font_descent = 1 -- FONT_DESCENT
local font_width = 4 -- DWIDTH

function Morphg:new(args)
  local self = setmetatable({},{__index=Morphg})
  local args = args==nil and {} or args

  -- self.size = args.size or 20
  self.octave = args.octave or 0
  self.direction = args.direction or 1 -- 1 is fwd, -1 is bkwd, 0 is stopped
  self.dirty = true
  self.width = font_width * 6
  self.height = font_height

  -- self.image = screen.create_image(self.size, self.size)
  self.image = screen.create_image(self.width, self.height)
  self:draw_init()

  return self
end

function Morphg:draw_init()
  screen.draw_to(self.image, function()
    screen.clear()
    screen.level(15)
    screen.aa(0)
    screen.font_face(font_face)
    screen.font_size(font_height)
  end)
end

function Morphg:redraw()
  if self.dirty then
    screen.draw_to(self.image, function()
      screen.clear()
      screen.move(0, font_ascent)

      local sign = '+'
      if self.octave < 0 then
        sign = ''
      end
      local oct = sign..self.octave
      if self.direction == 1 then
        screen.text('  '..oct..'>>')
      elseif self.direction == -1 then
        screen.text('<<'..oct..'  ')
      else
        screen.text('~~'..oct..'~~')
      end
    end)
    self.dirty = false
  end
end

return Morphg

