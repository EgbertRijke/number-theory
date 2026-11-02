local M = {}
local pi, sin, cos, ceil, sqrt, max = math.pi, math.sin, math.cos,
                                      math.ceil, math.sqrt, math.max
local pt_to_mm = 25.4 / 72.27 -- TeX pt, not PostScript bp
local shapes_cache = {}

local function shapes_for(f)
  local filename = assert(f.filename, "ClockWarp: font has no filename")
  local shapes = shapes_cache[filename]
  if not shapes then
    local reader = assert(fonts.handlers.otf.readers.loadshapes,
                          "ClockWarp requires luaotfload's shape reader")
    shapes = reader(filename)
    assert(shapes and shapes.units and shapes.units > 0,
           "ClockWarp: could not load font outlines: " .. filename)
    shapes_cache[filename] = shapes
  end
  return shapes
end

local function quadratic(p0, p1, p2, t)
  local s = 1-t
  return s*s*p0[1]+2*s*t*p1[1]+t*t*p2[1],
         s*s*p0[2]+2*s*t*p1[2]+t*t*p2[2]
end
local function cubic(p0, p1, p2, p3, t)
  local s = 1-t
  return s*s*s*p0[1]+3*s*s*t*p1[1]+3*s*t*t*p2[1]+t*t*t*p3[1],
         s*s*s*p0[2]+3*s*s*t*p1[2]+3*s*t*t*p2[2]+t*t*t*p3[2]
end
local function distance(p,q)
  local dx,dy = p[1]-q[1],p[2]-q[2]
  return sqrt(dx*dx+dy*dy)
end

function M.draw(text, angle, radius, stretch, font_id)
  local f = assert(font.getfont(font_id), "ClockWarp: invalid font id")
  local shapes = shapes_for(f)
  local mm_per_unit = (f.size / 65536) * pt_to_mm / shapes.units
  local glyphs, advance = {}, 0
  for _, code in utf8.codes(text) do
    local ch = assert(f.characters[code], "ClockWarp: missing character " .. code)
    local outline = assert(shapes.glyphs[ch.index],
      "ClockWarp: missing outline for glyph index " .. tostring(ch.index))
    glyphs[#glyphs+1] = {outline=outline, origin=advance}
    advance = advance + ch.width/65536 * pt_to_mm
  end
  local halfwidth = advance / 2
  local theta = tonumber(angle)*pi/180
  radius, stretch = tonumber(radius), tonumber(stretch)
  assert(radius and radius > 0 and stretch, "ClockWarp: invalid radius/stretch")

  local function map(x, y, origin)
    local u = origin + x*mm_per_unit - halfwidth
    local v = y*mm_per_unit
    local phi = theta - u/radius
    local rr = radius + stretch*v
    return rr*cos(phi), rr*sin(phi)
  end
  local result = {"\\path[fill=clockink,draw=none,even odd rule] "}
  local function point(x,y,origin,command)
    local xx, yy = map(x,y,origin)
    result[#result+1] = string.format("%s (%.6f,%.6f) ", command,xx,yy)
  end
  for _, item in ipairs(glyphs) do
    local segments = assert(item.outline.segments,
      "ClockWarp: font outline has no segments")
    local origin = item.origin
    local current, beginpoint = nil, nil
    for _,seg in ipairs(segments) do
      local kind = seg[#seg]
      if kind == "m" then
        if current then result[#result+1] = "-- cycle " end
        current = {seg[1],seg[2]}
        beginpoint = current
        point(seg[1],seg[2],origin,"")
      else
        if not current then
          error("ClockWarp: shape contour starts without moveto")
        end
        local endpoint, length, eval
        if kind == "l" then
          endpoint = {seg[1],seg[2]}
          length = distance(current,endpoint)
          eval = function(t)
            return current[1]+t*(endpoint[1]-current[1]),
                   current[2]+t*(endpoint[2]-current[2])
          end
        elseif kind == "q" then
          local a = {seg[1],seg[2]}
          endpoint = {seg[3],seg[4]}
          length = distance(current,a)+distance(a,endpoint)
          eval = function(t) return quadratic(current,a,endpoint,t) end
        elseif kind == "c" then
          local a, b = {seg[1],seg[2]}, {seg[3],seg[4]}
          endpoint = {seg[5],seg[6]}
          length = distance(current,a)+distance(a,b)+distance(b,endpoint)
          eval = function(t) return cubic(current,a,b,endpoint,t) end
        else
          error("ClockWarp: unknown segment type " .. tostring(kind))
        end

        local steps = max(1,ceil(length*mm_per_unit / 0.20))
        for k=1,steps do
          local x,y=eval(k/steps)
          point(x,y,origin,"--")
        end
        current = endpoint
      end
    end
    if current then result[#result+1] = "-- cycle " end
  end
  result[#result+1] = ";"
  tex.sprint(table.concat(result))
end
return M
