-- VECTRIC LUA SCRIPT
--[[
  Vektor_PDF  -  exportiert Vektoren als PDF mit einstellbarer Linienstaerke,
                 automatischer Bemassung und Beschriftung
  Fuer Aspire / VCarve (Gadget-API)

  Installation:
    Ordner "Vektor_PDF" (mit Vektor_PDF.lua und Vektor_PDF.htm) nach
    C:\Users\Public\Documents\Vectric Files\Gadgets\<Programm> V12.5\  kopieren
]]

local VERSION = "1.3.2"         -- bei jedem Release anpassen (siehe CHANGELOG.md)

local atan2 = math.atan2 or math.atan
local MM = 72 / 25.4            -- Punkte je mm (PDF-Einheit)
-- Farbauswahl im Dialog (Index 1..5) -> RGB 0..1
local COLORS = {
  { 0, 0, 0 },          -- schwarz
  { 0, 0.35, 0.8 },     -- blau
  { 0.85, 0, 0 },       -- rot
  { 0, 0.55, 0.2 },     -- gruen
  { 0.45, 0.45, 0.45 }, -- grau
}
local function ColorOps(index)                -- PDF-Operatoren fuer Strich- und Fuellfarbe
  local rgb = COLORS[index] or COLORS[1]
  local col = string.format("%.3f %.3f %.3f", rgb[1], rgb[2], rgb[3])
  return col .. " RG " .. col .. " rg"
end
local skipped = 0
local bezier_fallback = 0

-- ------------------------------------------------------------------
-- Text-Hilfen
-- ------------------------------------------------------------------
-- UTF-8 (ae, oe, ue, ss, Grad ...) -> Latin-1 fuer PDF WinAnsi
local function ToLatin1(s)
  return (s:gsub("([\194\195])([\128-\191])", function(a, b)
    return string.char((a:byte() - 192) * 64 + (b:byte() - 128))
  end))
end

local function PdfStr(s)
  return "(" .. ToLatin1(s):gsub("[()\\]", "\\%0") .. ")"
end

local function TextWidth(s, size)            -- Naeherung Helvetica
  return #ToLatin1(s) * size * 0.54
end

local function f(v) return string.format("%.3f", v) end

-- ------------------------------------------------------------------
-- Geometrie
-- ------------------------------------------------------------------
local function ArcPoints(x1, y1, x2, y2, bulge, seg_len)
  local dx, dy = x2 - x1, y2 - y1
  local c = math.sqrt(dx * dx + dy * dy)
  if c < 1e-9 or math.abs(bulge) < 1e-9 then return { { x2, y2 } } end
  local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
  local lx, ly = -dy / c, dx / c
  local off = c * (1 - bulge * bulge) / (4 * bulge)
  local cx, cy = mx + lx * off, my + ly * off
  local r = math.sqrt((x1 - cx) ^ 2 + (y1 - cy) ^ 2)
  local sweep = 4 * math.atan(bulge)
  local a1 = atan2(y1 - cy, x1 - cx)
  local n = math.max(8, math.ceil(math.abs(sweep) * r / seg_len))
  local pts = {}
  for i = 1, n do
    local a = a1 + sweep * i / n
    pts[#pts + 1] = { cx + r * math.cos(a), cy + r * math.sin(a) }
  end
  pts[#pts] = { x2, y2 }
  return pts
end

-- Kontrollpunkt i (1 oder 2) einer Bezier-Kurve lesen.
-- Die Vectric-API liefert ihn je nach Version als Eigenschaft oder Methode.
local function BezierControl(bez, i)
  local names = { "ControlPoint" .. i, "ControlPoint" .. i .. "2D", "GetControlPoint" .. i }
  for _, name in ipairs(names) do
    local ok, v = pcall(function() return bez[name] end)
    if ok and type(v) == "function" then ok, v = pcall(v, bez) end
    if ok and v ~= nil then
      local okxy, x, y = pcall(function() return v.X, v.Y end)
      if okxy and type(x) == "number" and type(y) == "number" then return { x, y } end
    end
  end
  local ok, v = pcall(function() return bez:ControlPoint(i) end)
  if ok and v ~= nil then
    local okxy, x, y = pcall(function() return v.X, v.Y end)
    if okxy and type(x) == "number" then return { x, y } end
  end
  return nil
end

-- Falls keine Kontrollpunkte lesbar sind: Kurve ueber eine
-- "Punkt bei Parameter t"-Funktion abtasten (Name je nach API-Version).
local function BezierSample(span, bez, n)
  local names = { "PointAtParameter", "GetPointAtParameter", "PointAtParam",
                  "GetPointAtParam", "PointAt", "GetPointAt", "Evaluate", "PointAtT" }
  for _, obj in ipairs({ bez, span }) do
    for _, name in ipairs(names) do
      local ok, fn = pcall(function() return obj[name] end)
      if ok and type(fn) == "function" then
        local okp, pt = pcall(fn, obj, 0.5)
        local okxy, x = pcall(function() return pt.X end)
        if okp and okxy and type(x) == "number" then
          local pts = {}
          for i = 1, n do
            local _, q = pcall(fn, obj, i / n)
            pts[#pts + 1] = { q.X, q.Y }
          end
          return pts
        end
      end
    end
  end
  return nil
end

-- Diagnose: welche Eigenschaften/Methoden bietet die Bezier-Kurve an?
local bezier_info = nil
local function BezierDiagnose(bez)
  if bezier_info then return end
  local parts = {}
  if type(class_info) == "function" then
    local ok, ci = pcall(class_info, bez)
    if ok and ci then
      parts[#parts + 1] = "Klasse: " .. tostring(ci.name)
      local m = {}
      if type(ci.methods) == "table" then for k in pairs(ci.methods) do m[#m + 1] = tostring(k) end end
      table.sort(m)
      parts[#parts + 1] = "Methoden: " .. table.concat(m, ", ")
      local a = {}
      if type(ci.attributes) == "table" then for _, v in pairs(ci.attributes) do a[#a + 1] = tostring(v) end end
      table.sort(a)
      parts[#parts + 1] = "Eigenschaften: " .. table.concat(a, ", ")
    end
  end
  if #parts == 0 then parts[1] = "Typ: " .. tostring(bez) .. " (class_info nicht verfuegbar)" end
  bezier_info = table.concat(parts, "\n")
end

-- Mittelpunkt, Radius und Punkt in der Bogenmitte (fuer die Radius-Bemassung)
local function ArcInfo(x1, y1, x2, y2, bulge)
  local dx, dy = x2 - x1, y2 - y1
  local c = math.sqrt(dx * dx + dy * dy)
  if c < 1e-9 or math.abs(bulge) < 1e-9 then return nil end
  local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
  local lx, ly = -dy / c, dx / c
  local off = c * (1 - bulge * bulge) / (4 * bulge)
  local cx, cy = mx + lx * off, my + ly * off
  local r = math.sqrt((x1 - cx) ^ 2 + (y1 - cy) ^ 2)
  local am = atan2(y1 - cy, x1 - cx) + 2 * math.atan(bulge)   -- halber Bogenwinkel
  return { cx = cx, cy = cy, r = r, px = cx + r * math.cos(am), py = cy + r * math.sin(am) }
end

-- Ecken zwischen zwei aufeinanderfolgenden Geraden -> { {vx,vy,ax,ay,bx,by,deg}, ... }
local function PathCorners(p)
  local corners, segs, n = {}, p.segs, #p.segs
  local last = p.closed and n or n - 1
  for i = 1, last do
    local s1, s2 = segs[i], segs[(i % n) + 1]
    if s1 and s2 and (i < n or p.closed) and
       math.abs(s1[3] - s2[1]) + math.abs(s1[4] - s2[2]) < 1e-6 then
      local a1 = atan2(s1[2] - s1[4], s1[1] - s1[3])     -- vom Scheitel zurueck
      local a2 = atan2(s2[4] - s2[2], s2[3] - s2[1])     -- vom Scheitel weiter
      local d = math.abs(a2 - a1)
      if d > math.pi then d = 2 * math.pi - d end
      corners[#corners + 1] = { s1[3], s1[4], s1[1], s1[2], s2[3], s2[4], d * 180 / math.pi }
    end
  end
  return corners
end

-- Kontur -> { cmds = {...}, arcs = {...}, closed, all_arcs, minx, miny, maxx, maxy }
local function ContourToPath(contour, seg_len)
  local p = { cmds = {}, arcs = {}, segs = {}, all_arcs = true, closed = contour.IsClosed,
              minx = math.huge, miny = math.huge, maxx = -math.huge, maxy = -math.huge }
  local cmds = p.cmds
  local first = true
  local pos = contour:GetHeadPosition()
  while pos ~= nil do
    local span
    span, pos = contour:GetNext(pos)
    local p1, p2 = span.StartPoint2D, span.EndPoint2D
    if first then
      cmds[#cmds + 1] = { "m", p1.X, p1.Y }
      first = false
    end
    if span.IsArcType then
      local arc = CastSpanToArcSpan(span)
      for _, q in ipairs(ArcPoints(p1.X, p1.Y, p2.X, p2.Y, arc.Bulge, seg_len)) do
        cmds[#cmds + 1] = { "l", q[1], q[2] }
      end
      local ai = ArcInfo(p1.X, p1.Y, p2.X, p2.Y, arc.Bulge)
      if ai then p.arcs[#p.arcs + 1] = ai end
      p.segs[#p.segs + 1] = false                     -- kein gerades Stueck
    elseif span.IsBezierType then
      p.all_arcs = false
      p.segs[#p.segs + 1] = false
      local bez = CastSpanToBezierSpan(span)
      local c1, c2 = BezierControl(bez, 1), BezierControl(bez, 2)
      if c1 and c2 then
        cmds[#cmds + 1] = { "c", c1[1], c1[2], c2[1], c2[2], p2.X, p2.Y }
      else
        local pts = BezierSample(span, bez, 32)
        if pts then
          for _, q in ipairs(pts) do cmds[#cmds + 1] = { "l", q[1], q[2] } end
          cmds[#cmds] = { "l", p2.X, p2.Y }
        else
          bezier_fallback = bezier_fallback + 1    -- nichts lesbar -> Gerade
          BezierDiagnose(bez)
          cmds[#cmds + 1] = { "l", p2.X, p2.Y }
        end
      end
    else
      p.all_arcs = false
      cmds[#cmds + 1] = { "l", p2.X, p2.Y }
      p.segs[#p.segs + 1] = { p1.X, p1.Y, p2.X, p2.Y }
    end
  end
  if p.closed then cmds[#cmds + 1] = { "h" } end
  local function ext(x, y)
    if x < p.minx then p.minx = x end
    if x > p.maxx then p.maxx = x end
    if y < p.miny then p.miny = y end
    if y > p.maxy then p.maxy = y end
  end
  local lx, ly = 0, 0
  for _, cmd in ipairs(cmds) do
    if cmd[1] == "c" then          -- Bezier abtasten (Kontrollpunkte liegen ausserhalb)
      for i = 1, 20 do
        local t = i / 20
        local a, b, c, e = (1 - t) ^ 3, 3 * (1 - t) ^ 2 * t, 3 * (1 - t) * t * t, t ^ 3
        ext(a * lx + b * cmd[2] + c * cmd[4] + e * cmd[6],
            a * ly + b * cmd[3] + c * cmd[5] + e * cmd[7])
      end
      lx, ly = cmd[6], cmd[7]
    elseif cmd[1] ~= "h" then
      ext(cmd[2], cmd[3])
      lx, ly = cmd[2], cmd[3]
    end
  end
  return p
end

-- ------------------------------------------------------------------
-- Vektoren einsammeln (inkl. Gruppen)
-- ------------------------------------------------------------------
-- in_group: Kontur stammt aus einer Gruppe (z. B. in Kurven umgewandelter Text)
-- Seite (Sheet) eines Objekts, falls die API sie liefert (Name je nach Version)
local sheet_probe = nil          -- welche Eigenschaft funktioniert hat (fuer die Diagnose)
local sheet_obj_info = nil       -- Klassen-Info eines Objekts, falls keine funktioniert
local known_sheets = {}          -- Seiten des Jobs { {id=..., key="...", name="..."}, ... }
local sheet_mgr = nil            -- job.SheetManager (fuer Seitennamen)

-- Beliebigen Wert (auch Vectric-Objekte wie Sheet-Ids) sicher in Text umwandeln
local function SafeStr(v)
  local t = type(v)
  if t == "string" then return v end
  if t == "number" or t == "boolean" then return tostring(v) end
  if v == nil then return nil end
  for _, k in ipairs({ "RawString", "String", "Text", "AsString" }) do
    local ok, s = pcall(function() return v[k] end)
    if ok and type(s) == "function" then ok, s = pcall(s, v) end
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  local ok, s = pcall(tostring, v)
  if ok and type(s) == "string" and not s:match("^userdata") then return s end
  return nil
end

-- Seiten-Wert -> einheitlicher Schluessel (Text); vergleicht auch mit den Ids des Jobs
local function SheetKey(v)
  if v == nil then return nil end
  local s = SafeStr(v)
  if s then return s end
  -- Vectric-Ids lassen sich nicht in Text wandeln -> ueber den Seitennamen zuordnen
  if sheet_mgr then
    local ok, name = pcall(function() return sheet_mgr:GetSheetName(v) end)
    if ok and type(name) == "string" and name ~= "" then return "n:" .. name end
  end
  for _, sh in ipairs(known_sheets) do
    local ok, eq = pcall(function() return v == sh.id end)
    if ok and eq then return sh.key end
  end
  return "?"
end

local function ObjSheet(obj)
  for _, key in ipairs({ "SheetIndex", "SheetId", "Sheet", "GetSheetIndex", "GetSheetId" }) do
    local ok, v = pcall(function() return obj[key] end)
    if ok and type(v) == "function" then ok, v = pcall(v, obj) end
    if ok and v ~= nil and type(v) ~= "function" then
      sheet_probe = key
      return SheetKey(v)
    end
  end
  if sheet_obj_info == nil and type(class_info) == "function" then
    local ok, ci = pcall(class_info, obj)
    if ok and ci then
      local m = {}
      if type(ci.methods) == "table" then for k in pairs(ci.methods) do m[#m + 1] = tostring(k) end end
      if type(ci.attributes) == "table" then for _, v in pairs(ci.attributes) do m[#m + 1] = tostring(v) end end
      table.sort(m)
      sheet_obj_info = tostring(ci.name) .. ": " .. table.concat(m, ", ")
    end
  end
  return nil
end

local function AddObject(obj, contours, in_group, sheet)
  if sheet == nil then sheet = ObjSheet(obj) end
  local ok, contour = pcall(function() return obj:GetContour() end)
  if ok and contour ~= nil then
    contours[#contours + 1] = { contour = contour, in_group = in_group or false, sheet = sheet }
    return
  end
  local gok, group = pcall(function() return CastCadObjectToCadObjectGroup(obj) end)
  if gok and group ~= nil then
    local iok = pcall(function()
      local pos = group:GetHeadPosition()
      while pos ~= nil do
        local child
        child, pos = group:GetNext(pos)
        AddObject(child, contours, true, sheet)
      end
    end)
    if iok then return end
  end
  skipped = skipped + 1
end

local function NormName(s)
  s = tostring(s or ""):lower():gsub("\195\159", "ss")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function LayerName(layer)
  -- Name je nach API-Version als Eigenschaft oder Methode
  for _, key in ipairs({ "Name", "GetName", "LayerName" }) do
    local ok, n = pcall(function() return layer[key] end)
    if ok and type(n) == "function" then ok, n = pcall(n, layer) end
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return ""
end

-- Anfangs- und Endpunkt einer Kontur (ueber die Spans, wie beim Zeichnen)
local function ContourEnds(contour)
  local ok, a, b = pcall(function()
    local pos = contour:GetHeadPosition()
    local first, last
    while pos ~= nil do
      local span
      span, pos = contour:GetNext(pos)
      if not first then first = span.StartPoint2D end
      last = span.EndPoint2D
    end
    return first, last
  end)
  if ok and a and b then return a.X, a.Y, b.X, b.Y end
  return nil
end

-- Alle Eckpunkte einer Kontur (Start + Endpunkt jedes Spans)
local function ContourPoints(contour)
  local ok, pts = pcall(function()
    local list = {}
    local pos = contour:GetHeadPosition()
    while pos ~= nil do
      local span
      span, pos = contour:GetNext(pos)
      if #list == 0 then list[1] = { span.StartPoint2D.X, span.StartPoint2D.Y } end
      list[#list + 1] = { span.EndPoint2D.X, span.EndPoint2D.Y }
    end
    return list
  end)
  if ok then return pts end
  return {}
end

-- Hilfslinien auf dem Bemassungs-Layer:
--   Linie mit 2 Punkten       -> Laengenmass  { x1,y1,x2,y2 }
--   Linie mit 3 Punkten (V)   -> Winkelmass   { ax,ay,bx,by, angle = true, vx, vy }
--                                (mittlerer Punkt = Scheitel des Winkels)
local function ContoursToDimLines(list)
  local lines = {}
  for _, c in ipairs(list) do
    if not c.contour.IsClosed then
      local pts = ContourPoints(c.contour)
      if #pts == 3 then
        lines[#lines + 1] = { pts[1][1], pts[1][2], pts[3][1], pts[3][2],
                              angle = true, vx = pts[2][1], vy = pts[2][2], sheet = c.sheet }
      elseif #pts >= 2 then
        lines[#lines + 1] = { pts[1][1], pts[1][2], pts[#pts][1], pts[#pts][2], sheet = c.sheet }
      end
    end
  end
  return lines
end

local function CollectContours(job, selected_only, dim_layer)
  local contours, dim_list = {}, {}
  local info = { names = {}, found = false, hidden = false }
  local dim_name = NormName(dim_layer)
  local lm = job.LayerManager
  local lpos = lm:GetHeadPosition()
  while lpos ~= nil do
    local layer
    layer, lpos = lm:GetNext(lpos)
    local lname = LayerName(layer)
    info.names[#info.names + 1] = (lname ~= "" and lname or "?") .. (layer.Visible and "" or " (-)")
    local is_dim = dim_name ~= "" and NormName(lname) == dim_name
    if is_dim then
      info.found = true
      if not layer.Visible then info.hidden = true end
    end
    if layer.Visible and (is_dim or not selected_only) then
      local pos = layer:GetHeadPosition()
      while pos ~= nil do
        local obj
        obj, pos = layer:GetNext(pos)
        AddObject(obj, is_dim and dim_list or contours)
      end
    end
  end
  local dim_lines = ContoursToDimLines(dim_list)
  info.objects = #dim_list
  if selected_only then
    local sel = job.Selection
    local pos = sel:GetHeadPosition()
    while pos ~= nil do
      local obj
      obj, pos = sel:GetNext(pos)
      AddObject(obj, contours)
    end
    -- mit ausgewaehlte Hilfslinien nicht als Zeichnung ausgeben
    local keep = {}
    for _, c in ipairs(contours) do
      local x1, y1, x2, y2 = ContourEnds(c.contour)
      local dup = false
      if x1 and not c.contour.IsClosed then
        for _, l in ipairs(dim_lines) do
          if math.abs(x1 - l[1]) + math.abs(y1 - l[2]) + math.abs(x2 - l[3]) + math.abs(y2 - l[4]) < 1e-6 then
            dup = true
          end
        end
      end
      if not dup then keep[#keep + 1] = c end
    end
    contours = keep
  end
  return contours, dim_lines, info
end

-- ------------------------------------------------------------------
-- Zeichen-Befehle fuer Bemassung (alles in PDF-Punkten)
-- ------------------------------------------------------------------
local Draw = {}
Draw.__index = Draw

function Draw.new(font_size, line_w)
  return setmetatable({ s = {}, fs = font_size, lw = line_w, arrow = 2.5 * MM }, Draw)
end
function Draw:add(x) self.s[#self.s + 1] = x end
function Draw:line(x1, y1, x2, y2)
  self:add(f(x1) .. " " .. f(y1) .. " m " .. f(x2) .. " " .. f(y2) .. " l S")
end
function Draw:arrowhead(x, y, dx, dy)       -- Spitze bei x,y; zeigt Richtung dx,dy
  local a, w = self.arrow, self.arrow * 0.3
  local bx, by = x - dx * a, y - dy * a
  self:add(f(x) .. " " .. f(y) .. " m " ..
           f(bx - dy * w) .. " " .. f(by + dx * w) .. " l " ..
           f(bx + dy * w) .. " " .. f(by - dx * w) .. " l f")
end
function Draw:text(x, y, str, size, rotated, align)
  size = size or self.fs
  local w = TextWidth(str, size)
  local shift = (align == "left") and 0 or (align == "right") and w or w / 2
  if rotated then
    self:add("BT /F1 " .. f(size) .. " Tf 0 1 -1 0 " .. f(x) .. " " .. f(y - shift) ..
             " Tm " .. PdfStr(str) .. " Tj ET")
  else
    self:add("BT /F1 " .. f(size) .. " Tf 1 0 0 1 " .. f(x - shift) .. " " .. f(y) ..
             " Tm " .. PdfStr(str) .. " Tj ET")
  end
end
-- waagrechtes Mass: von xa bis xb, Bezugskante yref, Masslinie bei yline (darunter)
function Draw:hdim(xa, xb, yref, yline, label)
  local gap, over = 1 * MM, 1.5 * MM
  self:line(xa, yref - gap, xa, yline - over)
  self:line(xb, yref - gap, xb, yline - over)
  self:line(xa, yline, xb, yline)
  self:arrowhead(xa, yline, -1, 0)
  self:arrowhead(xb, yline, 1, 0)
  self:text((xa + xb) / 2, yline + 1 * MM, label)
end
-- Text entlang einer Richtung (Winkel in Bogenmass), mittig bei x,y
function Draw:textAngle(x, y, str, ang)
  local size = self.fs
  local w = TextWidth(str, size)
  local c, s = math.cos(ang), math.sin(ang)
  local x0, y0 = x - c * w / 2, y - s * w / 2
  self:add("BT /F1 " .. f(size) .. " Tf " .. f(c) .. " " .. f(s) .. " " .. f(-s) .. " " .. f(c) ..
           " " .. f(x0) .. " " .. f(y0) .. " Tm " .. PdfStr(str) .. " Tj ET")
end
-- Manuelles Mass von Punkt 1 nach Punkt 2 (Masslinie liegt auf der Hilfslinie)
function Draw:alignedDim(x1, y1, x2, y2, label)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then return end
  local ux, uy = dx / len, dy / len
  local nx, ny = -uy, ux                        -- Normale (links der Linie)
  local tick = 1.5 * MM
  self:line(x1 - nx * tick, y1 - ny * tick, x1 + nx * tick, y1 + ny * tick)
  self:line(x2 - nx * tick, y2 - ny * tick, x2 + nx * tick, y2 + ny * tick)
  if len > 2.5 * self.arrow then
    self:line(x1, y1, x2, y2)
    self:arrowhead(x1, y1, -ux, -uy)
    self:arrowhead(x2, y2, ux, uy)
  else                                          -- zu kurz: Pfeile von aussen
    local e = self.arrow + 2 * MM
    self:line(x1 - ux * e, y1 - uy * e, x2 + ux * e, y2 + uy * e)
    self:arrowhead(x1, y1, ux, uy)
    self:arrowhead(x2, y2, -ux, -uy)
  end
  local ang = atan2(uy, ux)
  if ang > math.pi / 2 + 1e-6 or ang <= -math.pi / 2 + 1e-6 then   -- Text lesbar halten
    ang = ang + math.pi
  end
  local tnx, tny = -math.sin(ang), math.cos(ang)   -- "oberhalb" des Textes
  local mx, my = (x1 + x2) / 2 + tnx * 1 * MM, (y1 + y2) / 2 + tny * 1 * MM
  self:textAngle(mx, my, label, ang)
end
-- Winkelmass: Scheitel vx,vy, Schenkel Richtung a und b (alles in PDF-Punkten)
function Draw:angleDim(vx, vy, ax, ay, bx, by, label)
  local la = math.sqrt((ax - vx) ^ 2 + (ay - vy) ^ 2)
  local lb = math.sqrt((bx - vx) ^ 2 + (by - vy) ^ 2)
  if la < 1e-6 or lb < 1e-6 then return end
  local a1 = atan2(ay - vy, ax - vx)
  local sweep = atan2(by - vy, bx - vx) - a1
  while sweep > math.pi do sweep = sweep - 2 * math.pi end
  while sweep <= -math.pi do sweep = sweep + 2 * math.pi end
  if sweep < 0 then a1, sweep = a1 + sweep, -sweep end        -- immer gegen den Uhrzeigersinn
  -- Bogenradius: hoechstens 15 mm, nicht laenger als der kuerzere Schenkel (min. 6 mm)
  local r = math.max(6 * MM, math.min(15 * MM, math.min(la, lb)))
  -- Schenkel bis zum Bogen verlaengern, falls sie kuerzer sind
  local function leg(len, ang)
    if len < r then
      self:line(vx + math.cos(ang) * len, vy + math.sin(ang) * len,
                vx + math.cos(ang) * (r + 1 * MM), vy + math.sin(ang) * (r + 1 * MM))
    end
  end
  leg(la, atan2(ay - vy, ax - vx)); leg(lb, atan2(by - vy, bx - vx))
  -- Bogen als Polylinie
  local n = math.max(8, math.ceil(sweep * 24))
  local parts = { f(vx + r * math.cos(a1)) .. " " .. f(vy + r * math.sin(a1)) .. " m" }
  for i = 1, n do
    local a = a1 + sweep * i / n
    parts[#parts + 1] = f(vx + r * math.cos(a)) .. " " .. f(vy + r * math.sin(a)) .. " l"
  end
  self:add(table.concat(parts, " ") .. " S")
  -- Pfeile an beiden Bogenenden (tangential)
  local a2 = a1 + sweep
  local inside = r * sweep > 2.5 * self.arrow                   -- genug Platz fuer Pfeile innen?
  local s1 = inside and 1 or -1
  self:arrowhead(vx + r * math.cos(a1), vy + r * math.sin(a1), s1 * math.sin(a1), -s1 * math.cos(a1))
  self:arrowhead(vx + r * math.cos(a2), vy + r * math.sin(a2), -s1 * math.sin(a2), s1 * math.cos(a2))
  -- Text ausserhalb der Bogenmitte
  local am = a1 + sweep / 2
  local tr = r + 1.5 * MM + self.fs * 0.8
  self:text(vx + tr * math.cos(am), vy + tr * math.sin(am) - self.fs * 0.35, label)
end
-- Radius: Pfeil von aussen auf den Bogen (Punkt px,py), Mittelpunkt cx,cy
function Draw:radius(cx, cy, px, py, label)
  local dx, dy = px - cx, py - cy
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then return end
  dx, dy = dx / len, dy / len
  local ox, oy = px + dx * 6 * MM, py + dy * 6 * MM           -- Ende der Hinweislinie
  local side = (dx >= 0) and 1 or -1
  local sx = ox + side * 2 * MM                                -- kurzer waagrechter Absatz
  self:line(px, py, ox, oy)
  self:line(ox, oy, sx, oy)
  self:arrowhead(px, py, -dx, -dy)
  self:text(sx + side * 0.8 * MM, oy - self.fs * 0.35, label, nil, false,
            side > 0 and "left" or "right")
end
-- senkrechtes Mass: von ya bis yb, Bezugskante xref, Masslinie bei xline (links)
function Draw:vdim(ya, yb, xref, xline, label)
  local gap, over = 1 * MM, 1.5 * MM
  self:line(xref - gap, ya, xline - over, ya)
  self:line(xref - gap, yb, xline - over, yb)
  self:line(xline, ya, xline, yb)
  self:arrowhead(xline, ya, 0, -1)
  self:arrowhead(xline, yb, 0, 1)
  self:text(xline - 1 * MM, (ya + yb) / 2, label, nil, true)
end

-- ------------------------------------------------------------------
-- PDF schreiben
-- ------------------------------------------------------------------
-- ------------------------------------------------------------------
-- Seiten (Sheets) des Jobs
-- ------------------------------------------------------------------
-- Liste der Sheets { {id=..., name=...}, ... } und die aktive Sheet-Id
local function JobSheets(job)
  local list, active = {}, nil
  pcall(function()
    local sm = job.SheetManager
    sheet_mgr = sm
    active = sm.ActiveSheetId
    for id in sm:GetSheetIds() do
      local ok, name = pcall(function() return sm:GetSheetName(id) end)
      local key = SheetKey(id)
      if key == "?" then key = "#" .. (#list + 1) end
      list[#list + 1] = { id = id, key = key, name = (ok and SafeStr(name)) or key }
    end
  end)
  return list, active
end

-- Schluessel -> Eintrag in der Seiten-Liste (Name fuer die Seite)
local function SheetForKey(list, key)
  for _, sh in ipairs(list) do if sh.key == key then return sh end end
  local n = tonumber(key)                       -- Objekte zaehlen evtl. 0, 1, 2 ...
  if n and list[n + 1] then return list[n + 1] end
  return nil
end

-- Welcher Schluessel gehoert zur aktiven Seite?
local function ActiveSheetKey(list, active_key, keys)
  if active_key == nil then return nil end
  for _, k in ipairs(keys) do if k == active_key then return k end end
  for pos, sh in ipairs(list) do
    if sh.key == active_key then
      for _, k in ipairs(keys) do if k == tostring(pos - 1) then return k end end
      for _, k in ipairs(keys) do if k == tostring(pos) then return k end end
    end
  end
  return nil
end

-- pages = { { w = Breite, h = Hoehe, stream = Inhalt }, ... }
local function WritePdf(filename, pages)
  local n = #pages
  local kids = {}
  for i = 1, n do kids[#kids + 1] = (3 + 2 * i - 1) .. " 0 R" end
  local objs = {
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [" .. table.concat(kids, " ") .. "] /Count " .. n .. " >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
  }
  for i, pg in ipairs(pages) do
    local page_obj = 3 + 2 * i - 1
    objs[page_obj] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " .. f(pg.w) .. " " .. f(pg.h) ..
      "] /Contents " .. (page_obj + 1) .. " 0 R /Resources << /Font << /F1 3 0 R >> >> >>"
    objs[page_obj + 1] = "<< /Length " .. #pg.stream .. " >>\nstream\n" .. pg.stream .. "\nendstream"
  end
  local out = { "%PDF-1.4\n%\226\227\207\211\n" }
  local offset = #out[1]
  local offsets = {}
  for i, body in ipairs(objs) do
    offsets[i] = offset
    local chunk = i .. " 0 obj\n" .. body .. "\nendobj\n"
    out[#out + 1] = chunk
    offset = offset + #chunk
  end
  local xref = { "xref\n0 " .. (#objs + 1) .. "\n0000000000 65535 f \n" }
  for i = 1, #objs do xref[#xref + 1] = string.format("%010d 00000 n \n", offsets[i]) end
  out[#out + 1] = table.concat(xref)
  out[#out + 1] = "trailer\n<< /Size " .. (#objs + 1) .. " /Root 1 0 R >>\nstartxref\n" ..
                  offset .. "\n%%EOF\n"
  local fh, err = io.open(filename, "wb")
  if not fh then return false, err end
  fh:write(table.concat(out))
  fh:close()
  return true
end

-- ------------------------------------------------------------------
-- Hauptprogramm
-- ------------------------------------------------------------------
function main(script_path)
  local reg = Registry("PDF_Export")
  local lang = reg:GetInt("Lang", 1)                 -- 1 = Deutsch, 2 = English
  local function T(de, en) return (lang == 2) and en or de end

  local job = VectricJob()
  if not job.Exists then
    DisplayMessageBox(T("Kein Job geoeffnet.", "No job open."))
    return false
  end

  local dialog = HTML_Dialog(false, "file:" .. script_path .. "\\Vektor_PDF.htm", 520, 895, "Vektor_PDF " .. VERSION)
  dialog:AddRadioGroup("Lang", lang)
  dialog:AddTextField("Version", "v" .. VERSION)
  -- Zahlenfelder als Text: Komma und Punkt werden beide akzeptiert
  local function NumStr(v)                            -- Anzeige passend zur Sprache
    local str = string.format("%.3f", v)
    str = str:gsub("0+$", "")
    str = str:gsub("%.$", "")
    if lang ~= 2 then str = str:gsub("%.", ",") end
    return str
  end
  local function AddNum(id, default) dialog:AddTextField(id, NumStr(reg:GetDouble(id, default))) end
  AddNum("LineWidth", 0.5)
  AddNum("DimLineWidth", 0.25)
  AddNum("ArrowSize", 2.5)
  dialog:AddRadioGroup("VecColor", reg:GetInt("VecColor", 1))
  AddNum("Margin", 10)
  AddNum("FontSize", 3.5)
  dialog:AddRadioGroup("ScaleMode", reg:GetInt("ScaleMode", 1))
  dialog:AddRadioGroup("Orient", reg:GetInt("Orient", 1))
  dialog:AddRadioGroup("Source", job.Selection.IsEmpty and 2 or 1)
  dialog:AddRadioGroup("SheetMode", reg:GetInt("SheetMode", 1))
  dialog:AddCheckBox("DrawBorder", reg:GetBool("DrawBorder", false))
  dialog:AddCheckBox("DimOverall", reg:GetBool("DimOverall", true))
  dialog:AddCheckBox("DimEach", reg:GetBool("DimEach", false))
  AddNum("MinDim", 25)
  dialog:AddCheckBox("DimRadius", reg:GetBool("DimRadius", false))
  dialog:AddCheckBox("DimAngle", reg:GetBool("DimAngle", false))
  dialog:AddTextField("DimLayer", reg:GetString("DimLayer", "Bemassung"))
  dialog:AddCheckBox("HideDimLayer", reg:GetBool("HideDimLayer", false))
  dialog:AddRadioGroup("DimColor", reg:GetInt("DimColor", 1))
  dialog:AddCheckBox("ShowScale", reg:GetBool("ShowScale", true))
  dialog:AddTextField("Title", reg:GetString("Title", ""))
  dialog:AddTextField("Note", "")

  if not dialog:ShowDialog() then return false end

  lang = dialog:GetRadioIndex("Lang")
  reg:SetInt("Lang", lang)
  local bad = {}
  local function GetNum(id)                           -- "0,5" und "0.5" -> 0.5
    local t = (dialog:GetTextField(id) or ""):gsub("%s", "")
    t = t:gsub(",", ".")
    local v = tonumber(t)
    if v == nil then
      local names = {
        LineWidth    = T("Linienstaerke", "Line width"),
        DimLineWidth = T("Linienstaerke Bemassung", "Dimension line width"),
        ArrowSize    = T("Pfeilgroesse", "Arrow size"),
        Margin       = T("Rand", "Margin"),
        FontSize     = T("Schriftgroesse", "Font size"),
        MinDim       = T("Einzelmasse ab", "Min. size"),
      }
      bad[#bad + 1] = names[id] or id
      v = 0
    end
    return v
  end
  local line_mm     = GetNum("LineWidth")
  local dim_line_mm = GetNum("DimLineWidth")
  local arrow_mm    = GetNum("ArrowSize")
  local vec_color   = dialog:GetRadioIndex("VecColor")
  local margin_mm   = GetNum("Margin")
  local font_mm     = GetNum("FontSize")
  local scale_mode  = dialog:GetRadioIndex("ScaleMode")      -- 1 = A4, 2 = 1:1
  local orient      = dialog:GetRadioIndex("Orient")         -- 1 = automatisch, 2 = hoch, 3 = quer
  local selected_only = dialog:GetRadioIndex("Source") == 1
  local sheet_mode  = dialog:GetRadioIndex("SheetMode")     -- 1 = aktuelle Seite, 2 = alle Seiten
  local draw_border = dialog:GetCheckBox("DrawBorder")
  local dim_overall = dialog:GetCheckBox("DimOverall")
  local dim_each    = dialog:GetCheckBox("DimEach")
  local min_dim_mm  = GetNum("MinDim")
  if #bad > 0 then
    DisplayMessageBox(T("Bitte gueltige Zahlen eingeben (Komma oder Punkt): ",
                        "Please enter valid numbers (comma or point): ") .. table.concat(bad, ", "))
    return false
  end
  local dim_radius  = dialog:GetCheckBox("DimRadius")
  local dim_angle   = dialog:GetCheckBox("DimAngle")
  local dim_layer   = dialog:GetTextField("DimLayer") or ""
  local hide_dims   = dialog:GetCheckBox("HideDimLayer")
  local dim_color   = dialog:GetRadioIndex("DimColor")   -- 1 schwarz, 2 blau, 3 rot, 4 gruen, 5 grau
  local show_scale  = dialog:GetCheckBox("ShowScale")
  local title       = dialog:GetTextField("Title") or ""
  local note        = dialog:GetTextField("Note") or ""

  reg:SetDouble("LineWidth", line_mm)
  reg:SetDouble("DimLineWidth", dim_line_mm)
  reg:SetDouble("ArrowSize", arrow_mm)
  reg:SetInt("VecColor", vec_color)
  reg:SetDouble("Margin", margin_mm)
  reg:SetDouble("FontSize", font_mm)
  reg:SetInt("ScaleMode", scale_mode)
  reg:SetInt("Orient", orient)
  reg:SetInt("SheetMode", sheet_mode)
  reg:SetBool("DrawBorder", draw_border)
  reg:SetBool("DimOverall", dim_overall)
  reg:SetBool("DimEach", dim_each)
  reg:SetDouble("MinDim", min_dim_mm)
  reg:SetBool("DimRadius", dim_radius)
  reg:SetBool("DimAngle", dim_angle)
  reg:SetString("DimLayer", dim_layer)
  reg:SetBool("HideDimLayer", hide_dims)
  reg:SetInt("DimColor", dim_color)
  reg:SetBool("ShowScale", show_scale)
  reg:SetString("Title", title)

  if line_mm <= 0 or font_mm <= 0 then
    DisplayMessageBox(T("Linienstaerke und Schriftgroesse muessen groesser als 0 sein.",
                        "Line width and font size must be greater than 0."))
    return false
  end
  if selected_only and job.Selection.IsEmpty then
    DisplayMessageBox(T("Es sind keine Vektoren ausgewaehlt.", "No vectors are selected."))
    return false
  end

  local in_mm   = job.InMM
  local unit_pt = in_mm and MM or 72
  local seg_len = in_mm and 0.2 or 0.008
  local function fmt(v)
    if in_mm then
      local s = string.format("%.1f", v):gsub("%.0$", "")
      if lang == 2 then return s end                 -- English: Dezimalpunkt
      return (s:gsub("%.", ","))
    end
    return string.format('%.3f"', v)
  end
  local function fmtAng(deg)                           -- Winkel mit Gradzeichen
    local s = string.format("%.1f", deg):gsub("%.0$", "")
    if lang ~= 2 then s = s:gsub("%.", ",") end
    return s .. "\194\176"
  end

  -- Konturen
  skipped = 0
  bezier_fallback = 0
  bezier_info = nil
  local sheet_list, active_id = JobSheets(job)
  known_sheets = sheet_list
  local active_key = SheetKey(active_id)
  local contours, dim_lines, dim_info = CollectContours(job, selected_only, dim_layer)
  if hide_dims then dim_lines = {} end      -- Hilfslinien bleiben trotzdem aus der Zeichnung
  if #contours == 0 then
    DisplayMessageBox(T("Keine Vektoren gefunden.", "No vectors found."))
    return false
  end
  -- Eine PDF-Seite aus Konturen, Hilfslinien und Titel erzeugen
  local function RenderPage(contours, dim_lines, title)
    local paths = {}
    local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(contours) do
      local p = ContourToPath(c.contour, seg_len)
      p.in_group = c.in_group
      paths[#paths + 1] = p
      minx = math.min(minx, p.minx); miny = math.min(miny, p.miny)
      maxx = math.max(maxx, p.maxx); maxy = math.max(maxy, p.maxy)
    end
    local vminx, vminy, vmaxx, vmaxy = minx, miny, maxx, maxy   -- nur Vektoren
    for _, l in ipairs(dim_lines) do                              -- Platz fuer manuelle Masse
      minx = math.min(minx, l[1], l[3]); miny = math.min(miny, l[2], l[4])
      maxx = math.max(maxx, l[1], l[3]); maxy = math.max(maxy, l[2], l[4])
      if l.angle then
        minx = math.min(minx, l.vx); miny = math.min(miny, l.vy)
        maxx = math.max(maxx, l.vx); maxy = math.max(maxy, l.vy)
      end
    end

    local border = nil
    if draw_border then
      local mok, mb = pcall(MaterialBlock)
      if not mok or mb == nil then
        DisplayMessageBox(T("Materialumriss konnte nicht gelesen werden.", "Could not read the material outline."))
        return false
      end
      local box = mb.MaterialBox
      border = { box.MinX, box.MinY, box.MaxX, box.MaxY }
      minx = math.min(minx, box.MinX); miny = math.min(miny, box.MinY)
      maxx = math.max(maxx, box.MaxX); maxy = math.max(maxy, box.MaxY)
    end
    local w, h = math.max(maxx - minx, 1e-9), math.max(maxy - miny, 1e-9)

    -- Platz fuer Bemassung und Titel reservieren
    local fs     = font_mm * MM
    local margin = margin_mm * MM
    local dim_res = (dim_overall or dim_each) and (8 * MM + 2 * fs) or 0
    local lines = 0
    if title ~= "" then lines = lines + 1.4 end
    if note  ~= "" then lines = lines + 1 end
    local title_res = lines > 0 and (lines * fs * 1.5 + 3 * MM) or 0
    local foot_res  = show_scale and (fs * 1.5) or 0

    local page_w, page_h, scale
    if scale_mode == 2 then
      scale  = unit_pt
      page_w = w * scale + 2 * margin + dim_res
      page_h = h * scale + 2 * margin + dim_res + title_res + foot_res
    else
      page_w, page_h = 595.28, 841.89
      local landscape = (orient == 3) or (orient ~= 2 and w > h)
      if landscape then page_w, page_h = page_h, page_w end
      scale = math.min((page_w - 2 * margin - dim_res) / w,
                       (page_h - 2 * margin - dim_res - title_res - foot_res) / h)
    end
    local area_x = margin + dim_res
    local area_y = margin + dim_res + foot_res
    local area_w = page_w - margin - area_x
    local area_h = page_h - margin - title_res - area_y
    local offx = area_x + (area_w - w * scale) / 2
    local offy = area_y + (area_h - h * scale) / 2
    local function tx(x) return offx + (x - minx) * scale end
    local function ty(y) return offy + (y - miny) * scale end

    -- 1) Zeichnung
    local s = { f(line_mm * MM) .. " w 1 J 1 j " .. ColorOps(vec_color) }
    for _, p in ipairs(paths) do
      for _, cmd in ipairs(p.cmds) do
        local k = cmd[1]
        if k == "m" or k == "l" then
          s[#s + 1] = f(tx(cmd[2])) .. " " .. f(ty(cmd[3])) .. " " .. k
        elseif k == "c" then
          s[#s + 1] = f(tx(cmd[2])) .. " " .. f(ty(cmd[3])) .. " " ..
                      f(tx(cmd[4])) .. " " .. f(ty(cmd[5])) .. " " ..
                      f(tx(cmd[6])) .. " " .. f(ty(cmd[7])) .. " c"
        else
          s[#s + 1] = "h"
        end
      end
      s[#s + 1] = "S"
    end
    if border then
      s[#s + 1] = "q 0.3 w 0.6 G " .. f(tx(border[1])) .. " " .. f(ty(border[2])) .. " " ..
        f((border[3] - border[1]) * scale) .. " " .. f((border[4] - border[2]) * scale) .. " re S Q"
    end

    -- 2) Bemassung
    if not dim_line_mm or dim_line_mm <= 0 then dim_line_mm = 0.25 end
    local d = Draw.new(fs, dim_line_mm * MM)
    if arrow_mm and arrow_mm > 0 then d.arrow = arrow_mm * MM end
    d:add("q " .. f(dim_line_mm * MM) .. " w " .. ColorOps(dim_color))
    local near = 5 * MM          -- Abstand Einzelmasse
    local far  = near + 2 * fs + 3 * MM  -- Abstand Gesamtmasse
    if dim_overall then
      d:hdim(tx(vminx), tx(vmaxx), ty(vminy), ty(vminy) - far, fmt(vmaxx - vminx))
      d:vdim(ty(vminy), ty(vmaxy), tx(vminx), tx(vminx) - far, fmt(vmaxy - vminy))
    end
    if dim_each then
      local tol = in_mm and 0.05 or 0.002
      local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4   -- Eingabe immer in mm
      for _, p in ipairs(paths) do
        local pw, ph = p.maxx - p.minx, p.maxy - p.miny
        local is_total = math.abs(p.minx - vminx) < tol and math.abs(p.maxx - vmaxx) < tol and
                         math.abs(p.miny - vminy) < tol and math.abs(p.maxy - vmaxy) < tol
        local big_enough = math.max(pw, ph) >= min_dim
        if p.closed and not p.in_group and big_enough and pw > tol and ph > tol and
           not (is_total and dim_overall) then
          if p.all_arcs and math.abs(pw - ph) < 0.01 * pw then
            -- Kreis: Durchmesser ueber dem Kreis
            d:text(tx((p.minx + p.maxx) / 2), ty(p.maxy) + 1.5 * MM, "\195\152 " .. fmt(pw))
          else
            local same_w = dim_overall and math.abs(p.minx - vminx) < tol and math.abs(p.maxx - vmaxx) < tol
            local same_h = dim_overall and math.abs(p.miny - vminy) < tol and math.abs(p.maxy - vmaxy) < tol
            if not same_w then d:hdim(tx(p.minx), tx(p.maxx), ty(p.miny), ty(p.miny) - near, fmt(pw)) end
            if not same_h then d:vdim(ty(p.miny), ty(p.maxy), tx(p.minx), tx(p.minx) - near, fmt(ph)) end
          end
        end
      end
    end

    -- Radien an Boegen (gleiche Radien je Vektor nur einmal)
    if dim_radius then
      local tol = in_mm and 0.05 or 0.002
      local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4
      for _, p in ipairs(paths) do
        local pw, ph = p.maxx - p.minx, p.maxy - p.miny
        local is_circle = p.closed and p.all_arcs and pw > tol and math.abs(pw - ph) < 0.01 * pw
        if not p.in_group and math.max(pw, ph) >= min_dim and not (is_circle and dim_each) then
          local done = {}
          for _, a in ipairs(p.arcs) do
            local seen = false
            for _, r in ipairs(done) do if math.abs(r - a.r) < tol then seen = true end end
            if not seen and a.r > tol then
              done[#done + 1] = a.r
              d:radius(tx(a.cx), ty(a.cy), tx(a.px), ty(a.py), "R " .. fmt(a.r))
            end
          end
        end
      end
    end

    -- Winkel an Ecken zwischen zwei Geraden (90 und 180 Grad werden ausgelassen)
    if dim_angle then
      local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4
      for _, p in ipairs(paths) do
        local pw, ph = p.maxx - p.minx, p.maxy - p.miny
        if not p.in_group and math.max(pw, ph) >= min_dim then
          for _, cn in ipairs(PathCorners(p)) do
            local deg = cn[7]
            if math.abs(deg - 90) > 0.5 and deg > 0.5 and deg < 179.5 then
              d:angleDim(tx(cn[1]), ty(cn[2]), tx(cn[3]), ty(cn[4]), tx(cn[5]), ty(cn[6]), fmtAng(deg))
            end
          end
        end
      end
    end

    -- Manuelle Masse aus den Hilfslinien des Bemassungs-Layers
    for _, l in ipairs(dim_lines) do
      if l.angle then
        local a1 = atan2(l[2] - l.vy, l[1] - l.vx)
        local sw = atan2(l[4] - l.vy, l[3] - l.vx) - a1
        while sw > math.pi do sw = sw - 2 * math.pi end
        while sw <= -math.pi do sw = sw + 2 * math.pi end
        d:angleDim(tx(l.vx), ty(l.vy), tx(l[1]), ty(l[2]), tx(l[3]), ty(l[4]),
                   fmtAng(math.abs(sw) * 180 / math.pi))
      else
        local len = math.sqrt((l[3] - l[1]) ^ 2 + (l[4] - l[2]) ^ 2)
        d:alignedDim(tx(l[1]), ty(l[2]), tx(l[3]), ty(l[4]), (fmt(len)))
      end
    end

    -- 3) Titel, Notiz, Massstab (immer schwarz)
    d:add("0 G 0 g")
    local ytop = page_h - margin
    if title ~= "" then
      ytop = ytop - fs * 1.4
      d:text(margin, ytop, title, fs * 1.4, false, "left")
    end
    if note ~= "" then
      ytop = ytop - fs * 1.5
      d:text(margin, ytop, note, fs, false, "left")
    end
    if show_scale then
      local ratio = unit_pt / scale
      local r
      if math.abs(ratio - 1) < 0.005 then r = "1:1"
      elseif ratio > 1 then r = "1:" .. string.format("%.2f", ratio):gsub("%.?0+$", "")
      else r = string.format("%.2f", 1 / ratio):gsub("%.?0+$", "") .. ":1" end
      local unit = in_mm and "mm" or T("Zoll", "inch")
      local sep = "   \194\183   "
      local foot = T("Ma\195\159stab ", "Scale ") .. r .. sep ..
                   T("Ma\195\159e in ", "Dimensions in ") .. unit .. sep ..
                   os.date(T("%d.%m.%Y", "%Y-%m-%d"))
      d:text(margin, margin, foot, fs * 0.8, false, "left")
    end
    d:add("Q")

    local stream = table.concat(s, "\n") .. "\n" .. table.concat(d.s, "\n")
    return { w = page_w, h = page_h, stream = stream }, paths
  end

  -- Seiten (Sheets) aufteilen
  local keys, seen = {}, {}
  for _, c in ipairs(contours) do
    local k = c.sheet
    if k ~= nil and not seen[k] then seen[k] = true; keys[#keys + 1] = k end
  end
  local sheet_method = sheet_probe and ("Objekt." .. sheet_probe) or nil
  -- Objekte liefern keine Seite: probeweise jede Seite aktivieren und neu einlesen
  if not selected_only and #keys <= 1 and #sheet_list > 1 then
    local per, total = {}, #contours
    local differs = false
    for _, sh in ipairs(sheet_list) do
      local okset = pcall(function() job.SheetManager.ActiveSheetId = sh.id end)
      if okset then
        local c2, d2 = CollectContours(job, false, dim_layer)
        per[#per + 1] = { sh = sh, contours = c2, dims = d2 }
        if #c2 ~= total then differs = true end
      end
    end
    pcall(function() job.SheetManager.ActiveSheetId = active_id end)
    if differs then
      contours, dim_lines, keys, seen = {}, {}, {}, {}
      for _, e in ipairs(per) do
        for _, c in ipairs(e.contours) do c.sheet = e.sh.key; contours[#contours + 1] = c end
        for _, l in ipairs(e.dims) do l.sheet = e.sh.key; dim_lines[#dim_lines + 1] = l end
        if #e.contours > 0 then seen[e.sh.key] = true; keys[#keys + 1] = e.sh.key end
      end
      if hide_dims then dim_lines = {} end
      sheet_method = "ActiveSheetId"
    end
  end
  -- Diagnose, falls der Job mehrere Seiten hat, sie aber nicht getrennt werden konnten
  local sheet_diag = nil
  if not selected_only and (#sheet_list > 1 or sheet_mode == 2) and #keys <= 1 then
    local ids = {}
    for _, sh in ipairs(sheet_list) do ids[#ids + 1] = tostring(sh.key) .. "=" .. tostring(sh.name) end
    sheet_diag = T("\n\n--- Seiten-Diagnose (bitte Screenshot senden) ---\n",
                   "\n\n--- Sheet diagnostics (please send a screenshot) ---\n") ..
                 #sheet_list .. T(" Seiten: ", " sheets: ") .. table.concat(ids, ", ") ..
                 T("\naktiv: ", "\nactive: ") .. tostring(active_key) ..
                 T("\nSeite je Objekt: ", "\nsheet per object: ") .. tostring(sheet_method) ..
                 (keys[1] ~= nil and (" (" .. tostring(keys[1]) .. ")") or "") ..
                 (sheet_obj_info and ("\n" .. sheet_obj_info) or "")
  end
  table.sort(keys, function(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na < nb end
    return tostring(a) < tostring(b)
  end)
  local sheet_note = nil
  local groups = {}
  if selected_only or #keys <= 1 then
    groups[1] = { contours = contours, dims = dim_lines, title = title }
  elseif sheet_mode == 2 then
    for n, k in ipairs(keys) do
      local g = { contours = {}, dims = {} }
      for _, c in ipairs(contours) do if c.sheet == k then g.contours[#g.contours + 1] = c end end
      for _, l in ipairs(dim_lines) do if l.sheet == k then g.dims[#g.dims + 1] = l end end
      local sh = SheetForKey(sheet_list, k)
      local sname = sh and sh.name or (T("Seite ", "Sheet ") .. n)
      g.title = (title ~= "") and (title .. " - " .. sname) or sname
      groups[#groups + 1] = g
    end
  else
    local ak = ActiveSheetKey(sheet_list, active_key, keys)
    if ak == nil then
      ak = keys[1]
      sheet_note = T("aktive Seite nicht erkannt - erste Seite exportiert",
                     "active sheet not detected - first sheet exported")
    end
    local g = { contours = {}, dims = {}, title = title }
    for _, c in ipairs(contours) do if c.sheet == ak then g.contours[#g.contours + 1] = c end end
    for _, l in ipairs(dim_lines) do if l.sheet == ak then g.dims[#g.dims + 1] = l end end
    if #g.contours == 0 then
      DisplayMessageBox(T("Auf der aktiven Seite wurden keine Vektoren gefunden.",
                          "No vectors found on the active sheet."))
      return false
    end
    groups[1] = g
    local sh = SheetForKey(sheet_list, ak)
    sheet_note = sheet_note or (T("Seite: ", "Sheet: ") .. (sh and sh.name or tostring(ak)))
    dim_lines = g.dims
  end

  local pages, paths = {}, {}
  for _, g in ipairs(groups) do
    local pg, pp = RenderPage(g.contours, g.dims, g.title)
    if not pg then return false end
    pages[#pages + 1] = pg
    for _, p in ipairs(pp) do paths[#paths + 1] = p end
  end

  -- Speichern
  local fd = FileDialog()
  if not fd:FileSave("pdf", T("Zeichnung.pdf", "Drawing.pdf"), T("PDF Dateien", "PDF files") .. " (*.pdf)|*.pdf|") then
    return false
  end
  local ok, err = WritePdf(fd.PathName, pages)
  if not ok then
    DisplayMessageBox(T("PDF konnte nicht geschrieben werden:\n", "Could not write PDF:\n") .. tostring(err))
    return false
  end

  local msg = "Vektor_PDF v" .. VERSION .. "\n\n" ..
              T("PDF gespeichert:\n", "PDF saved:\n") .. fd.PathName ..
              "\n\n" .. #paths .. T(" Vektoren, Linienstaerke ", " vectors, line width ") .. NumStr(line_mm) .. " mm"
  if #pages > 1 then
    msg = msg .. "\n" .. #pages .. T(" Seiten (je VCarve-Seite eine PDF-Seite)", " pages (one PDF page per VCarve sheet)")
  elseif sheet_note then
    msg = msg .. "\n" .. sheet_note
  end
  if sheet_diag then msg = msg .. sheet_diag end
  local n_group = 0
  for _, p in ipairs(paths) do if p.in_group then n_group = n_group + 1 end end
  if #dim_lines > 0 then
    local n_ang = 0
    for _, l in ipairs(dim_lines) do if l.angle then n_ang = n_ang + 1 end end
    msg = msg .. "\n" .. (#dim_lines - n_ang) .. T(" Laengenmass(e), ", " length dimension(s), ") ..
          n_ang .. T(" Winkelmass(e) vom Layer \"", " angle dimension(s) from layer \"") .. dim_layer .. "\""
  elseif dim_layer ~= "" and not hide_dims then
    -- Hilfe, wenn keine manuellen Masse gefunden wurden
    if not dim_info.found then
      msg = msg .. T("\n\nHinweis: Mass-Layer \"", "\n\nNote: dimension layer \"") .. dim_layer ..
            T("\" nicht gefunden.\nVorhandene Layer: ", "\" not found.\nExisting layers: ") ..
            table.concat(dim_info.names, ", ")
    elseif dim_info.hidden then
      msg = msg .. T("\n\nHinweis: Mass-Layer \"", "\n\nNote: dimension layer \"") .. dim_layer ..
            T("\" ist in VCarve ausgeblendet.", "\" is hidden in VCarve.")
    else
      msg = msg .. T("\n\nHinweis: Auf dem Mass-Layer \"", "\n\nNote: dimension layer \"") .. dim_layer ..
            T("\" wurden keine offenen Linien gefunden (", "\" contains no open lines (") ..
            dim_info.objects .. T(" Objekt(e)).", " object(s)).")
    end
  end
  if dim_each then
    msg = msg .. "\n(" .. n_group .. T(" davon in Gruppen - ohne Einzelmasse)", " of them in groups - no individual dimensions)")
  end
  if skipped > 0 then
    msg = msg .. "\n\n" .. skipped .. T(" Objekt(e) ohne Vektorform (Vectric-Text/-Bemassung)" ..
          " wurden uebersprungen - Masse erzeugt das Gadget selbst.",
          " object(s) without vector shape (Vectric text/dimensions)" ..
          " were skipped - the gadget creates its own dimensions.")
  end
  if bezier_fallback > 0 then
    msg = msg .. T("\n\nHinweis: ", "\n\nNote: ") .. bezier_fallback ..
          T(" Bezier-Kurve(n) konnten nicht gelesen werden und wurden als Gerade gezeichnet." ..
            "\n\n--- Diagnose (bitte Screenshot senden) ---\n",
            " Bezier curve(s) could not be read and were drawn as straight lines." ..
            "\n\n--- Diagnostics (please send a screenshot) ---\n") ..
          tostring(bezier_info)
  end
  DisplayMessageBox(msg)
  return true
end
