-- VECTRIC LUA SCRIPT
--[[
  Vektor_PDF  -  exportiert Vektoren als PDF mit einstellbarer Linienstaerke,
                 automatischer Bemassung und Beschriftung
  Fuer Aspire / VCarve (Gadget-API)

  Installation:
    Ordner "Vektor_PDF" (mit Vektor_PDF.lua und Vektor_PDF.htm) nach
    C:\Users\Public\Documents\Vectric Files\Gadgets\<Programm> V12.5\  kopieren
]]

local G_version = "dev"         -- wird von MakeRelease.ps1 beim Release ersetzt (nicht von Hand aendern)
local G_subVersion = "development"
local G_title = "Vektor_PDF"
-- Anzeige z. B. "1.4.0 beta.1" bzw. "dev development"
local function VersionText()
  if G_subVersion ~= nil and G_subVersion ~= "" then return G_version .. " " .. G_subVersion end
  return G_version
end

local atan2 = math.atan2 or math.atan
local MM = 72 / 25.4            -- Punkte je mm (PDF-Einheit)
local EXT_GAP = 2 * MM          -- Abstand der Masshilfslinien zum Bauteil
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
local vdims = {}                    -- gesammelte Vectric-Bemassungen { obj, sheet }
local vdim_ok, vdim_unsure = 0, 0
local use_vdims = false             -- Vectric-Masse nur aus eingeschalteten Layern (wie in VCarve angezeigt)
local layer_colors = {}                          -- Layer-Id -> Farbe (fuer "Nur ausgewaehlte")
local layer_color_ok, layer_color_fail = 0, 0   -- Layerfarben gelesen / nicht lesbar
local layer_color_diag = nil

-- Farbe eines Layers als { r, g, b } (0..1) lesen; je nach API-Version unterschiedlich
local function ToRGB(a, b, c)
  if type(a) == "number" and type(b) == "number" and type(c) == "number" then
    if a > 1 or b > 1 or c > 1 then return { a / 255, b / 255, c / 255 } end
    return { a, b, c }
  end
  if type(a) == "number" then                      -- Windows-COLORREF 0x00BBGGRR
    local v = math.floor(a)
    return { (v % 256) / 255, (math.floor(v / 256) % 256) / 255, (math.floor(v / 65536) % 256) / 255 }
  end
  if a ~= nil and type(a) ~= "string" and type(a) ~= "boolean" then   -- Objekt mit Farbanteilen
    for _, k in ipairs({ { "Red", "Green", "Blue" }, { "R", "G", "B" }, { "r", "g", "b" } }) do
      local ok, r, g, bl = pcall(function() return a[k[1]], a[k[2]], a[k[3]] end)
      if ok and type(r) == "number" and type(g) == "number" and type(bl) == "number" then
        return ToRGB(r, g, bl)
      end
    end
  end
  return nil
end
local function LayerColour(layer)
  for _, key in ipairs({ "Colour", "Color", "GetColour", "GetColor", "ColourRGB", "LayerColour" }) do
    local ok, v = pcall(function() return layer[key] end)
    if ok and v ~= nil then
      local rgb
      if type(v) == "function" then
        local ok2, a, b, c = pcall(v, layer)
        if ok2 then rgb = ToRGB(a, b, c) end
      else
        rgb = ToRGB(v)
      end
      if rgb then return rgb end
    end
  end
  -- Diagnose fuer die Abschlussmeldung, falls nichts lesbar war
  if layer_color_diag == nil then
    local found = {}
    for _, key in ipairs({ "Colour", "Color", "GetColour", "GetColor", "ColourRGB", "LayerColour" }) do
      local ok, v = pcall(function() return layer[key] end)
      if ok and v ~= nil then found[#found + 1] = key .. "=" .. type(v) end
    end
    layer_color_diag = (#found > 0) and table.concat(found, ", ") or "keine Farb-Eigenschaft gefunden"
  end
  return nil
end
local straight_bez = 0   -- gerade Bezier-Kurven, die als Linie behandelt werden
local skipped_dims = 0   -- davon Vectric-Bemassungen (CadLinearDimensioningObject usw.)
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
  local sa = atan2(y1 - cy, x1 - cx)
  local am = sa + 2 * math.atan(bulge)                         -- halber Bogenwinkel
  return { cx = cx, cy = cy, r = r, px = cx + r * math.cos(am), py = cy + r * math.sin(am),
           sa = sa, sw = 4 * math.atan(bulge) }                -- Startwinkel, Bogenwinkel
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

-- Bezier-Kurve, die ein Kreisbogen ist (z. B. Verrundung)? -> wie ArcInfo, sonst nil
-- at(t) liefert den Kurvenpunkt bei t (0..1)
local function BezierArcInfo(x0, y0, x3, y3, at)
  local mx, my = at(0.5)
  if not mx then return nil end
  -- Kreis durch Anfang, Mitte, Ende
  local ax, ay, bx, by = mx - x0, my - y0, x3 - x0, y3 - y0
  local d = 2 * (ax * by - ay * bx)
  if math.abs(d) < 1e-12 then return nil end
  local a2, b2 = ax * ax + ay * ay, bx * bx + by * by
  local ux, uy = (by * a2 - ay * b2) / d, (ax * b2 - bx * a2) / d
  local cx, cy = x0 + ux, y0 + uy
  local r = math.sqrt(ux * ux + uy * uy)
  local chord = math.sqrt(bx * bx + by * by)
  local sag = math.abs(ax * by - ay * bx) / chord                -- Pfeilhoehe des Bogens
  local tol = math.min(0.01 * r, 0.005 * chord, 0.05 * sag)        -- erlaubte Abweichung
  for _, t in ipairs({ 0.125, 0.25, 0.375, 0.625, 0.75, 0.875 }) do
    local qx, qy = at(t)
    if not qx or math.abs(math.sqrt((qx - cx) ^ 2 + (qy - cy) ^ 2) - r) > tol then return nil end
  end
  local sa = atan2(y0 - cy, x0 - cx)
  local ea = atan2(y3 - cy, x3 - cx)
  local am = atan2(my - cy, mx - cx)
  local tp = 2 * math.pi
  local ccw = (ea - sa) % tp
  local sw = (((am - sa) % tp) < ccw) and ccw or (ccw - tp)
  if math.abs(sw) > math.pi * 1.01 then return nil end      -- mehr als Halbkreis: lieber nicht
  return { cx = cx, cy = cy, r = r, px = mx, py = my, sa = sa, sw = sw, bez = true }
end

-- Kreis? Aus Boegen oder aus Bezier-Kurven (z. B. importierte Kreise): alle Punkte
-- gleich weit vom Mittelpunkt, Rahmen quadratisch, keine geraden Stuecke
local function IsCircle(p, tol)
  local pw, ph = p.maxx - p.minx, p.maxy - p.miny
  if not p.closed or pw <= tol or math.abs(pw - ph) >= 0.01 * pw then return false end
  if p.all_arcs then return true end
  for _, sg in ipairs(p.segs) do if sg then return false end end
  local cx, cy, r = (p.minx + p.maxx) / 2, (p.miny + p.maxy) / 2, pw / 2
  local n = 0
  for _, c in ipairs(p.cmds) do
    local x, y
    if c[1] == "m" or c[1] == "l" then x, y = c[2], c[3] elseif c[1] == "c" then x, y = c[6], c[7] end
    if x then
      n = n + 1
      if math.abs(math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) - r) > 0.015 * r then return false end
    end
  end
  return n >= 4
end

-- Kontur -> { cmds = {...}, arcs = {...}, closed, all_arcs, minx, miny, maxx, maxy }
local function ContourToPath(contour, seg_len)
  local p = { cmds = {}, arcs = {}, segs = {}, knots = {}, all_arcs = true, closed = contour.IsClosed,
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
      p.knots[#p.knots + 1] = { p1.X, p1.Y }
      first = false
    end
    p.knots[#p.knots + 1] = { p2.X, p2.Y }          -- Knoten (Anfang/Ende jedes Stuecks)
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
      local bez = CastSpanToBezierSpan(span)
      local c1, c2 = BezierControl(bez, 1), BezierControl(bez, 2)
      local pts = nil
      if not (c1 and c2) then pts = BezierSample(span, bez, 32) end
      -- Kurve, die in Wahrheit gerade ist (Kontrollpunkte auf der Verbindungslinie)?
      -- Dann wie eine Linie behandeln, damit sie bemasst wird und Ecken-Winkel bekommt.
      local function Straight()
        local dx, dy = p2.X - p1.X, p2.Y - p1.Y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1e-9 then return false end
        local tol = seg_len * 0.05
        local function off(q) return math.abs((q[1] - p1.X) * dy - (q[2] - p1.Y) * dx) / len end
        if c1 and c2 then return off(c1) <= tol and off(c2) <= tol end
        if pts then
          for _, q in ipairs(pts) do if off(q) > tol then return false end end
          return true
        end
        return false
      end
      -- Kreisbogen aus Bezier (fuer Radius-Masse)
      local at = nil
      if c1 and c2 then
        at = function(t)
          local u = 1 - t
          local a, b, c, e = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
          return a * p1.X + b * c1[1] + c * c2[1] + e * p2.X, a * p1.Y + b * c1[2] + c * c2[2] + e * p2.Y
        end
      elseif pts and #pts >= 8 then
        at = function(t)
          local i = math.floor(t * #pts + 0.5)
          if i < 1 then return p1.X, p1.Y end
          return pts[i][1], pts[i][2]
        end
      end
      if Straight() then
        straight_bez = straight_bez + 1
        cmds[#cmds + 1] = { "l", p2.X, p2.Y }
        p.segs[#p.segs + 1] = { p1.X, p1.Y, p2.X, p2.Y }
      elseif c1 and c2 then
        p.segs[#p.segs + 1] = false
        cmds[#cmds + 1] = { "c", c1[1], c1[2], c2[1], c2[2], p2.X, p2.Y }
        local ai = BezierArcInfo(p1.X, p1.Y, p2.X, p2.Y, at)
        if ai then p.arcs[#p.arcs + 1] = ai end
      else
        p.segs[#p.segs + 1] = false
        if pts then
          for _, q in ipairs(pts) do cmds[#cmds + 1] = { "l", q[1], q[2] } end
          cmds[#cmds] = { "l", p2.X, p2.Y }
          local ai = at and BezierArcInfo(p1.X, p1.Y, p2.X, p2.Y, at)
          if ai then p.arcs[#p.arcs + 1] = ai end
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

-- Layerfarbe setzen (nur beim Neuanlegen; danach in VCarve frei aenderbar).
-- Je nach API-Version 0..1 oder 0..255 -> pruefen, ob die Farbe angekommen ist.
local function SetLayerColour(layer, r, g, b)
  local function close()
    local c = LayerColour(layer)
    return c and math.abs(c[1] - r) < 0.05 and math.abs(c[2] - g) < 0.05 and math.abs(c[3] - b) < 0.05
  end
  for _, m in ipairs({ "SetColor", "SetColour" }) do
    if pcall(function() layer[m](layer, r, g, b) end) and close() then return true end
    if pcall(function() layer[m](layer, r * 255, g * 255, b * 255) end) and close() then return true end
  end
  return false
end
local CUSTOM_LAYER_RGB = { 0.45, 0.85, 0.35 }   -- hellgruen

local function AddObject(obj, contours, in_group, sheet, color)
  if sheet == nil then sheet = ObjSheet(obj) end
  local ok, contour = pcall(function() return obj:GetContour() end)
  if ok and contour ~= nil then
    contours[#contours + 1] = { contour = contour, in_group = in_group or false, sheet = sheet, color = color }
    return
  end
  local gok, group = pcall(function() return CastCadObjectToCadObjectGroup(obj) end)
  if gok and group ~= nil then
    local iok = pcall(function()
      local pos = group:GetHeadPosition()
      while pos ~= nil do
        local child
        child, pos = group:GetNext(pos)
        AddObject(child, contours, true, sheet, color)
      end
    end)
    if iok then return end
  end
  skipped = skipped + 1
  -- Vectric-Bemassungen erkennen: sie geben ueber die Gadget-Schnittstelle nur ihren
  -- Umriss heraus, keine Punkte und keinen Masstext
  local cok, cname = pcall(function() return obj.ClassName end)
  if cok and type(cname) == "string" and cname:find("Dimension") then
    skipped = skipped - 1                          -- wird als Mass uebernommen
    vdims[#vdims + 1] = { obj = obj, sheet = sheet }
  end
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


-- ------------------------------------------------------------------
-- Vectric-Bemassungen fuer das PDF in Masslinien umrechnen (nur im Speicher,
-- an der Zeichnung in VCarve wird nichts geaendert).
-- VCarve gibt von einer Bemassung nur den Umriss-Rahmen heraus. Daraus wird eine
-- waagrechte bzw. senkrechte Masslinie abgeleitet, deren Enden auf das Bauteil fangen.
-- Schraege oder unsichere Bemassungen werden ausgelassen.
-- ------------------------------------------------------------------
local PDF_DIM_LAYER = "pdf_dim"     -- Layer fuer selbst gezeichnete Masslinien (im Dialog einstellbar)
local custom_dims = true            -- Schalter "Individuelle Bemassung"
local snap_verts = nil              -- Fangpunkte aller Vektoren (einmal je Lauf)
local snap_segs = nil               -- gerade Stuecke aller Vektoren (fuer schmale Masse)
local snap_arcs = nil               -- Kreisboegen aller Vektoren (fuer Radius-Masse)
local snap_knots = nil              -- Knoten aller Vektoren (Ecken, Bogen-Enden) fuer schraege Masse

local function SnapVerts(job, in_mm)
  if snap_verts then return snap_verts end
  snap_verts, snap_segs, snap_arcs, snap_knots = {}, {}, {}, {}
  pcall(function()
    local lm = job.LayerManager
    local lpos = lm:GetHeadPosition()
    while lpos ~= nil do
      local layer
      layer, lpos = lm:GetNext(lpos)
      if NormName(LayerName(layer)) ~= NormName(PDF_DIM_LAYER) then
        local stack = {}
        local pos = layer:GetHeadPosition()
        while pos ~= nil do
          local obj
          obj, pos = layer:GetNext(pos)
          stack[#stack + 1] = obj
        end
        while #stack > 0 do
          local obj = table.remove(stack)
          local ok, c = pcall(function() return obj:GetContour() end)
          if ok and c ~= nil then
            pcall(function()
              -- Punkte entlang des Vektors (auch auf Boegen, z. B. Kreis-Tangentenpunkte)
              local p = ContourToPath(c, in_mm and 1.0 or 0.04)
              local sx, sy, lx, ly
              for _, cmd in ipairs(p.cmds) do
                if cmd[1] == "m" or cmd[1] == "l" then snap_verts[#snap_verts + 1] = { cmd[2], cmd[3] }
                elseif cmd[1] == "c" then snap_verts[#snap_verts + 1] = { cmd[6], cmd[7] } end
                if cmd[1] == "m" then sx, sy, lx, ly = cmd[2], cmd[3], cmd[2], cmd[3]
                elseif cmd[1] == "l" then snap_segs[#snap_segs + 1] = { lx, ly, cmd[2], cmd[3] }; lx, ly = cmd[2], cmd[3]
                elseif cmd[1] == "c" then snap_segs[#snap_segs + 1] = { lx, ly, cmd[6], cmd[7] }; lx, ly = cmd[6], cmd[7]
                elseif cmd[1] == "h" and sx then snap_segs[#snap_segs + 1] = { lx, ly, sx, sy } end
              end
              for _, k in ipairs(p.knots) do snap_knots[#snap_knots + 1] = k end
              -- Kreisboegen: genaue Extrempunkte (0/90/180/270 Grad) als Fangpunkte
              for _, a in ipairs(p.arcs) do
                snap_arcs[#snap_arcs + 1] = a
                -- nur bei echten Boegen: Bezier-Kreise haben ihre Scheitel schon als Knoten,
                -- der angenaeherte Mittelpunkt waere minimal ungenau (z. B. 11.999 statt 12.000)
                for k = 0, (a.bez and -1 or 3) do
                  local ang = k * math.pi / 2
                  local t = (a.sw >= 0) and ((ang - a.sa) % (2 * math.pi)) or ((a.sa - ang) % (2 * math.pi))
                  if t <= math.abs(a.sw) + 1e-9 then
                    snap_verts[#snap_verts + 1] = { a.cx + a.r * math.cos(ang), a.cy + a.r * math.sin(ang) }
                  end
                end
              end
            end)
          else
            pcall(function()
              local g = CastCadObjectToCadObjectGroup(obj)
              if g then
                local gp = g:GetHeadPosition()
                while gp ~= nil do
                  local ch
                  ch, gp = g:GetNext(gp)
                  stack[#stack + 1] = ch
                end
              end
            end)
          end
        end
      end
    end
  end)
  return snap_verts
end

local function VectricDimLine(job, obj, in_mm, known_k)
  local verts = SnapVerts(job, in_mm)
  local tol = in_mm and 1.0 or 0.04                -- Fangbereich
  local okb, box = pcall(function() return obj:GetBoundingBox() end)
  if not okb or box == nil then return nil end
  local x0, y0, x1, y1 = box.MinX, box.MinY, box.MaxX, box.MaxY
  local w, h = x1 - x0, y1 - y0
  -- Radius-Mass (kein lineares Mass): eine Rahmenecke = Pfeilspitze auf einem Kreisbogen
  local okc, cname = pcall(function() return obj.ClassName end)
  cname = (okc and type(cname) == "string") and cname or ""
  if cname ~= "" and not cname:find("Linear") then
    local tb = math.max(2 * tol, 0.04 * math.max(w, h))
    local best, bd = nil, tb
    for _, a in ipairs(snap_arcs or {}) do
      for _, c in ipairs({ { x0, y0 }, { x1, y0 }, { x0, y1 }, { x1, y1 } }) do
        local dd = math.abs(math.sqrt((c[1] - a.cx) ^ 2 + (c[2] - a.cy) ^ 2) - a.r)
        if dd < bd then best, bd = { a = a, x = c[1], y = c[2] }, dd end
      end
    end
    if best then
      local a = best.a
      local ang = atan2(best.y - a.cy, best.x - a.cx)
      local px, py = a.cx + a.r * math.cos(ang), a.cy + a.r * math.sin(ang)
      -- innenliegend (Linie vom Mittelpunkt): Rahmen umfasst den Mittelpunkt
      local inside = a.cx > x0 - tb and a.cx < x1 + tb and a.cy > y0 - tb and a.cy < y1 + tb
      -- Radius und Durchmesser sind in VCarve dieselbe Klasse (vcCadArcDimensioningObject) und
      -- geben keine Eigenschaften heraus -> immer als Radius ("R ...") ausgeben
      local diam = false
      return { a.cx, a.cy, px, py, radius = true, inside = inside, diam = diam,
               cx = a.cx, cy = a.cy, r = a.r, px = px, py = py }
    end
    return nil
  end
  local function Snap(v, ax, lo, hi)
    -- Punkt auf Hoehe v; bei mehreren den naechsten am Rahmen (Hilfslinie fuehrt dorthin),
    -- nicht einen gleich hohen Punkt an einem anderen Teil
    local clo, chi = (ax == 1) and y0 or x0, (ax == 1) and y1 or x1
    local best, bs, other = v, math.huge, nil
    for _, q in ipairs(verts) do
      local o = q[3 - ax]
      local dd = math.abs(q[ax] - v)
      if o >= lo and o <= hi and dd < tol then
        local cd = (o < clo and clo - o) or (o > chi and o - chi) or 0
        local sc = dd + 0.001 * cd        -- genauester Treffer (z. B. Kreis-Scheitel), bei Gleichstand der naechste
        -- Hilfslinie reicht bis knapp an den Messpunkt; weit entfernte Punkte -> Rueckfall 3)
        if cd <= math.max(3 * tol, 0.15 * (chi - clo)) and sc < bs then best, bs, other = q[ax], sc, o end
      end
    end
    return best, other
  end
  -- Gerade quer durch den Rahmen: wo schneidet sie Kanten (nur Kanten quer zur Messrichtung)
  local function CutsAt(hz, c, lo, hi)
    local cuts = {}
    for _, sg in ipairs(snap_segs or {}) do
      local a1, b1, a2, b2
      if hz then a1, b1, a2, b2 = sg[1], sg[2], sg[3], sg[4] else a1, b1, a2, b2 = sg[2], sg[1], sg[4], sg[3] end
      if (b1 - c) * (b2 - c) <= 0 and math.abs(b2 - b1) > 1e-9 and math.abs(a2 - a1) <= 0.2 * math.abs(b2 - b1) then
        local a = a1 + (a2 - a1) * (c - b1) / (b2 - b1)
        if a >= lo and a <= hi then cuts[#cuts + 1] = a end
      end
    end
    return cuts
  end
  -- 0) Mass innerhalb des Bauteils (ohne Hilfslinien): Pfeilspitzen sitzen genau auf zwei Kanten,
  --    die Zahl steht mittig auf der Masslinie -> Linie durch die Rahmenmitte
  for _, hz in ipairs({ w >= h, w < h }) do
    local lo, hi = hz and x0 or y0, hz and x1 or y1
    local c = hz and (y0 + y1) / 2 or (x0 + x1) / 2
    if hi - lo > 2 * tol then
      local at_lo, at_hi = false, false
      for _, a in ipairs(CutsAt(hz, c, lo - tol, hi + tol)) do
        if math.abs(a - lo) < tol then at_lo = true end
        if math.abs(a - hi) < tol then at_hi = true end
      end
      if at_lo and at_hi then
        if hz then return { x0, c, x1, c } else return { c, y0, c, y1 } end
      end
    end
  end
  local hx0, ho0 = Snap(x0, 1, y0 - 2 * h, y1 + 2 * h)
  local hx1, ho1 = Snap(x1, 1, y0 - 2 * h, y1 + 2 * h)
  local vy0, vo0 = Snap(y0, 2, x0 - 2 * w, x1 + 2 * w)
  local vy1, vo1 = Snap(y1, 2, x0 - 2 * w, x1 + 2 * w)
  local hs = (ho0 and 1 or 0) + (ho1 and 1 or 0)
  local vs = (vo0 and 1 or 0) + (vo1 and 1 or 0)
  local horiz
  if hs ~= vs then horiz = hs > vs else horiz = w >= h end
  if (horiz and hs < 2) or (not horiz and vs < 2) then
    -- Schmales Mass (Pfeile aussen, Zahl daneben), z. B. Nutbreite: Die Masslinie liegt quer
    -- zwischen zwei Kanten. Eine Linie quer durch den Rahmen schneidet die Kanten ("cuts").
    -- Die Pfeile ragen auf beiden Seiten gleich weit (k) ueber die Kanten hinaus; steht die
    -- Zahl in Messrichtung daneben, ist nur eine Seite um k ueberstehend (k aus anderen Massen).
    local function Cuts(hz, c, lo, hi)
      local cuts = {}
      for _, sg in ipairs(snap_segs or {}) do
        local a1, b1, a2, b2                        -- a = Messrichtung, b = quer
        if hz then a1, b1, a2, b2 = sg[1], sg[2], sg[3], sg[4] else a1, b1, a2, b2 = sg[2], sg[1], sg[4], sg[3] end
        -- nur Kanten quer zur Messrichtung (fast senkrecht dazu), keine schraegen
        if (b1 - c) * (b2 - c) <= 0 and math.abs(b2 - b1) > 1e-9 and math.abs(a2 - a1) <= 0.2 * math.abs(b2 - b1) then
          local a = a1 + (a2 - a1) * (c - b1) / (b2 - b1)
          if a > lo and a < hi then
            local dup = false
            for _, q in ipairs(cuts) do if math.abs(q - a) < tol * 0.1 then dup = true end end
            if not dup then cuts[#cuts + 1] = a end
          end
        end
      end
      table.sort(cuts)
      return cuts
    end
    local eps = tol * 0.3
    local function Make(hz, ca, cb, c, lo2, hi2, side)
      -- Lage quer: bei Zahl seitlich die Rahmenkante, an der beide Kanten wirklich vorhanden sind
      if side then
        local function has(cc)
          local n = 0
          for _, q in ipairs(Cuts(hz, cc, (hz and x0 or y0), (hz and x1 or y1))) do
            if math.abs(q - ca) < eps or math.abs(q - cb) < eps then n = n + 1 end
          end
          return n >= 2
        end
        local m = 0.03 * (hi2 - lo2)
        if has(hi2 - m) and not has(lo2 + m) then c = hi2 - m
        elseif has(lo2 + m) and not has(hi2 - m) then c = lo2 + m end
      end
      if hz then return { ca, c, cb, c } else return { c, ca, c, cb } end
    end
    -- 1) Zahl seitlich: Ueberstand auf beiden Seiten gleich
    for _, hz in ipairs({ true, false }) do
      local lo, hi = hz and x0 or y0, hz and x1 or y1
      local qlo, qhi = hz and y0 or x0, hz and y1 or x1
      local cuts = Cuts(hz, (qlo + qhi) / 2, lo, hi)
      for i = 1, #cuts - 1 do
        local d1, d2 = cuts[i] - lo, hi - cuts[i + 1]
        if d1 > eps and math.abs(d1 - d2) < eps then
          return Make(hz, cuts[i], cuts[i + 1], (qlo + qhi) / 2, qlo, qhi, true), d1
        end
      end
    end
    -- 2) Zahl in Messrichtung daneben: eine Seite steht um k ueber (k aus anderen Massen)
    if known_k then
      for _, hz in ipairs({ true, false }) do
        local lo, hi = hz and x0 or y0, hz and x1 or y1
        local qlo, qhi = hz and y0 or x0, hz and y1 or x1
        local c = (qlo + qhi) / 2
        local cuts = Cuts(hz, c, lo, hi)
        for i = 1, #cuts do
          if i < #cuts and math.abs(cuts[i] - lo - known_k) < eps then
            return Make(hz, cuts[i], cuts[i + 1], c), nil
          end
          if i > 1 and math.abs(hi - cuts[i] - known_k) < eps then
            return Make(hz, cuts[i - 1], cuts[i], c), nil
          end
        end
      end
    end
    -- 3a) schraeges (paralleles) Mass: Messpunkte P1, P2 am Bauteil; die Hilfslinien laufen senkrecht
    --     zu P1-P2 von Abstand g (Luecke zum Bauteil) bis D (knapp ueber der Masslinie). Der Rahmen
    --     ist der Umriss dieser beiden Hilfslinien -> g und D aus x und y getrennt berechnen, muessen passen.
    do
      local tb = math.max(2 * tol, 0.03 * math.max(w, h))
      local ex = 0.3 * math.max(w, h)
      local function Fit(pts)
      local cand = {}
      for _, q in ipairs(pts) do
        if q[1] > x0 - ex and q[1] < x1 + ex and q[2] > y0 - ex and q[2] < y1 + ex and #cand < 150 then
          cand[#cand + 1] = q
        end
      end
      local best, berr = nil, 2 * tb
      for i = 1, #cand do
        for j = i + 1, #cand do
          local P1, P2 = cand[i], cand[j]
          local ux, uy = P2[1] - P1[1], P2[2] - P1[2]
          local L = math.sqrt(ux * ux + uy * uy)
          if L > 3 * tb and math.abs(ux) > 0.05 * L and math.abs(uy) > 0.05 * L then
            for _, sg in ipairs({ 1, -1 }) do
              local nx, ny = -uy / L * sg, ux / L * sg
              local function GD(p1, p2, n, lo, hi)
                if n > 0 then return (lo - math.min(p1, p2)) / n, (hi - math.max(p1, p2)) / n end
                return (hi - math.max(p1, p2)) / n, (lo - math.min(p1, p2)) / n
              end
              local gx, dx = GD(P1[1], P2[1], nx, x0, x1)
              local gy, dy = GD(P1[2], P2[2], ny, y0, y1)
              local g, D = (gx + gy) / 2, (dx + dy) / 2
              local err = math.abs(gx - gy) + math.abs(dx - dy)
              if err < berr and g > -tb and D > g + 2 * tb and g < 0.6 * D then
                local k = D - 0.08 * (D - g)            -- Masslinie knapp innerhalb der Hilfslinien-Enden
                best = { P1[1] + nx * k, P1[2] + ny * k, P2[1] + nx * k, P2[2] + ny * k,
                         p1 = { P1[1], P1[2] }, p2 = { P2[1], P2[2] } }
                berr = err
              end
            end
          end
        end
      end
      return best
      end
      -- zuerst nur Knoten (Ecken, Bogen-Enden): Vectric misst meist dazwischen;
      -- sonst wuerde ein Punkt mitten auf einem Bogen faelschlich passen
      local best = Fit(snap_knots or {}) or Fit(verts)
      if best then return best end
    end
    -- 3) kurze Hilfslinien (Fangpunkt weit weg vom Rahmen): naechsten Punkt genau auf der
    --    Hoehe der Rahmenenden suchen, beide Punkte muessen auf derselben Seite liegen
    local hz = w >= h
    local len, cross = hz and w or h, hz and h or w
    if len > 2 * cross then
      local ax = hz and 1 or 2
      local clo, chi = hz and y0 or x0, hz and y1 or x1
      local function Far(v)
        local best, bd = nil, math.huge
        for _, q in ipairs(verts) do
          if math.abs(q[ax] - v) < tol then
            local o = q[3 - ax]
            local d = (o < clo and clo - o) or (o > chi and o - chi) or 0
            if d < bd then best, bd = o, d end
          end
        end
        return best
      end
      local o0, o1 = Far(hz and x0 or y0), Far(hz and x1 or y1)
      if o0 and o1 and not ((o0 < clo and o1 > chi) or (o0 > chi and o1 < clo)) then
        local om = (o0 + o1) / 2
        local c = (math.abs(chi - om) > math.abs(clo - om)) and (chi - 0.08 * cross) or (clo + 0.08 * cross)
        if hz then return { x0, c, x1, c, p1 = { x0, o0 }, p2 = { x1, o1 } } end
        return { c, y0, c, y1, p1 = { o0, y0 }, p2 = { o1, y1 } }
      end
    end
    return nil
  end
  -- Masslinie fast am aeusseren Rand des Rahmens (weiter weg vom Bauteil)
  if horiz then
    local oy = (ho0 + ho1) / 2
    local y = (math.abs(y1 - oy) > math.abs(y0 - oy)) and (y1 - 0.08 * h) or (y0 + 0.08 * h)
    -- Masszahl aus den Hilfslinien selbst (Rahmenkanten = exakte Messpunkte von Vectric),
    -- der Fangpunkt bestimmt nur, wohin die Hilfslinie fuehrt
    return { x0, y, x1, y, p1 = { x0, ho0 }, p2 = { x1, ho1 } }
  else
    local ox = (vo0 + vo1) / 2
    local x = (math.abs(x1 - ox) > math.abs(x0 - ox)) and (x1 - 0.08 * w) or (x0 + 0.08 * w)
    return { x, y0, x, y1, p1 = { vo0, y0 }, p2 = { vo1, y1 } }
  end
end

-- layer_filter: nil = alle sichtbaren Layer, sonst Tabelle { [NormName] = true } der gewaehlten Layer
local function CollectContours(job, selected_only, dim_layer, layer_filter)
  layer_colors = {}
  vdims = {}
  vdim_ok, vdim_unsure = 0, 0
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
    local use
    if is_dim then use = custom_dims and layer.Visible   -- Individuelle Bemassung: Layer wie in VCarve angezeigt
    elseif selected_only then use = false
    elseif layer_filter then use = layer_filter[NormName(lname)] == true   -- auch ausgeblendete
    else use = layer.Visible end
    local lcol = (not is_dim) and LayerColour(layer) or nil
    if not is_dim then
      if lcol then layer_color_ok = layer_color_ok + 1 else layer_color_fail = layer_color_fail + 1 end
      local iok, lid = pcall(function() return tostring(layer.Id) end)
      if iok and lid ~= nil and lcol then layer_colors[lid] = lcol end
    end
    if use then
      local pos = layer:GetHeadPosition()
      while pos ~= nil do
        local obj
        obj, pos = layer:GetNext(pos)
        AddObject(obj, is_dim and dim_list or contours, nil, nil, lcol)
      end
    elseif use_vdims and not selected_only then
      -- Layer wird nicht gedruckt (ausgeblendet / nicht gewaehlt): nur seine Vectric-Bemassungen
      local pos = layer:GetHeadPosition()
      while pos ~= nil do
        local obj
        obj, pos = layer:GetNext(pos)
        local okc, cn = pcall(function() return obj.ClassName end)
        if okc and type(cn) == "string" and cn:find("Dimension") then
          vdims[#vdims + 1] = { obj = obj, sheet = ObjSheet(obj) }
        end
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
      local lok, lid = pcall(function() return tostring(obj.LayerId) end)
      AddObject(obj, contours, nil, nil, lok and layer_colors[lid] or nil)
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
  -- Vectric-Bemassungen der gedruckten Layer bzw. der Auswahl als Masslinien
  -- 1. Durchgang: eindeutige Masse; dabei den Pfeil-Ueberstand k schmaler Masse lernen
  local open, known_k = {}, nil
  for _, vd in ipairs(vdims) do
    local l, k = VectricDimLine(job, vd.obj, job.InMM, nil)
    if k and not known_k then known_k = k end
    if l then
      l.sheet = vd.sheet
      dim_lines[#dim_lines + 1] = l
      vdim_ok = vdim_ok + 1
    else
      open[#open + 1] = vd
    end
  end
  -- 2. Durchgang: schmale Masse mit der Zahl in Messrichtung (brauchen k)
  for _, vd in ipairs(open) do
    local l = known_k and VectricDimLine(job, vd.obj, job.InMM, known_k) or nil
    if l then
      l.sheet = vd.sheet
      dim_lines[#dim_lines + 1] = l
      vdim_ok = vdim_ok + 1
    else
      vdim_unsure = vdim_unsure + 1
    end
  end
  return contours, dim_lines, info
end

-- ------------------------------------------------------------------
-- Zeichen-Befehle fuer Bemassung (alles in PDF-Punkten)
-- ------------------------------------------------------------------
local Draw = {}
Draw.__index = Draw

function Draw.new(font_size, line_w)
  return setmetatable({ s = {}, fs = font_size, lw = line_w, arrow = 2.5 * MM, boxes = {} }, Draw)
end
-- Flaeche einer Beschriftung (x0, y0, x1, y1), damit sich Zahlen nicht ueberdecken
local function TextBox(x, y, str, size, rotated, align)
  local w = TextWidth(str, size)
  local shift = (align == "left") and 0 or (align == "right") and w or w / 2
  if rotated then return { x - 0.8 * size, y - shift, x + 0.2 * size, y - shift + w } end
  return { x - shift, y - 0.25 * size, x - shift + w, y + 0.8 * size }
end
function Draw:boxFree(b)
  local pad = 0.5 * MM
  for _, o in ipairs(self.boxes) do
    if b[1] < o[3] + pad and b[3] > o[1] - pad and b[2] < o[4] + pad and b[4] > o[2] - pad then
      return false
    end
  end
  return true
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
  self.boxes[#self.boxes + 1] = TextBox(x, y, str, size, rotated, align)
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
-- Mass zu kurz fuer Pfeile und Zahl innen? (dann wie bei Vectric: Pfeile von aussen,
-- Zahl daneben mit verlaengerter Masslinie)
function Draw:narrow(len, label)
  return len < 2 * self.arrow + TextWidth(label, self.fs) + 2 * MM
end
function Draw:hdim(xa, xb, yref, yline, label)
  local gap, over = EXT_GAP, 1.5 * MM
  self:line(xa, yref - gap, xa, yline - over)
  self:line(xb, yref - gap, xb, yline - over)
  if self:narrow(xb - xa, label) then
    local e = self.arrow + 2 * MM
    local tx = xa - e - 1 * MM                       -- Zahl links daneben
    self:line(tx, yline, xb + e, yline)
    self:arrowhead(xa, yline, 1, 0)
    self:arrowhead(xb, yline, -1, 0)
    self:text(tx - 0.5 * MM, yline - self.fs * 0.35, label, nil, false, "right")
    return
  end
  self:line(xa, yline, xb, yline)
  self:arrowhead(xa, yline, -1, 0)
  self:arrowhead(xb, yline, 1, 0)
  self:text((xa + xb) / 2, yline + 1 * MM, label)
end
-- Text entlang einer Richtung (Winkel in Bogenmass), mittig bei x,y
-- Flaeche eines gedrehten Textes (achsparalleler Rahmen um die gedrehte Schrift)
function Draw:angleBox(x, y, str, ang)
  local size = self.fs
  local w = TextWidth(str, size)
  local c, s = math.cos(ang), math.sin(ang)
  local x0, y0 = x - c * w / 2, y - s * w / 2
  local xs, ys = {}, {}
  for _, p in ipairs({ { 0, -0.25 * size }, { w, -0.25 * size }, { 0, 0.8 * size }, { w, 0.8 * size } }) do
    xs[#xs + 1] = x0 + c * p[1] - s * p[2]
    ys[#ys + 1] = y0 + s * p[1] + c * p[2]
  end
  local b = { xs[1], ys[1], xs[1], ys[1] }
  for i = 2, 4 do
    b[1] = math.min(b[1], xs[i]); b[2] = math.min(b[2], ys[i])
    b[3] = math.max(b[3], xs[i]); b[4] = math.max(b[4], ys[i])
  end
  return b
end
function Draw:textAngle(x, y, str, ang)
  local size = self.fs
  local w = TextWidth(str, size)
  local c, s = math.cos(ang), math.sin(ang)
  local x0, y0 = x - c * w / 2, y - s * w / 2
  self.boxes[#self.boxes + 1] = self:angleBox(x, y, str, ang)
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
  if not self:narrow(len, label) then
    self:line(x1, y1, x2, y2)
    self:arrowhead(x1, y1, -ux, -uy)
    self:arrowhead(x2, y2, ux, uy)
  else                                          -- zu kurz: Pfeile von aussen
    local e = self.arrow + 2 * MM
    self:line(x1 - ux * e, y1 - uy * e, x2 + ux * e, y2 + uy * e)
    self:arrowhead(x1, y1, ux, uy)
    self:arrowhead(x2, y2, -ux, -uy)
  end
  if self:narrow(len, label) then              -- Zahl passt nicht dazwischen: daneben (wie Vectric)
    local tw = TextWidth(label, self.fs)
    local e = self.arrow + 2 * MM
    -- auf der Seite, die beim Lesen links bzw. unten liegt
    local sx, sy, sgn = x1, y1, -1
    if ux < -1e-6 or (math.abs(ux) <= 1e-6 and uy < 0) then sx, sy, sgn = x2, y2, 1 end
    local ex, ey = sx + sgn * ux * (e + 1 * MM), sy + sgn * uy * (e + 1 * MM)
    self:line(sx + sgn * ux * e, sy + sgn * uy * e, ex, ey)
    local ang = atan2(uy, ux)
    if ang > math.pi / 2 + 1e-6 or ang <= -math.pi / 2 + 1e-6 then ang = ang + math.pi end
    local cx, cy = ex + sgn * ux * (tw / 2 + 0.5 * MM), ey + sgn * uy * (tw / 2 + 0.5 * MM)
    local tnx, tny = -math.sin(ang), math.cos(ang)
    self:textAngle(cx - tnx * self.fs * 0.35, cy - tny * self.fs * 0.35, label, ang)
    return
  end
  local ang = atan2(uy, ux)
  if ang > math.pi / 2 + 1e-6 or ang <= -math.pi / 2 + 1e-6 then   -- Text lesbar halten
    ang = ang + math.pi
  end
  local tnx, tny = -math.sin(ang), math.cos(ang)   -- "oberhalb" des Textes
  -- Zahl moeglichst mittig; liegt dort schon eine andere Zahl, entlang der Linie ausweichen
  local mx, my
  for _, t in ipairs({ 0.5, 0.35, 0.65, 0.25, 0.75, 0.15, 0.85 }) do
    local cx, cy = x1 + dx * t + tnx * 1 * MM, y1 + dy * t + tny * 1 * MM
    if mx == nil then mx, my = cx, cy end
    if self:boxFree(self:angleBox(cx, cy, label, ang)) then mx, my = cx, cy; break end
  end
  self:textAngle(mx, my, label, ang)
end
-- Mass parallel zu einer schraegen Linie, um 'off' nach unten/links versetzt, mit Hilfslinien
function Draw:offsetDim(x1, y1, x2, y2, label, off)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then return end
  local nx, ny = -dy / len, dx / len
  if ny > 1e-9 or (math.abs(ny) <= 1e-9 and nx > 0) then nx, ny = -nx, -ny end   -- nach unten/links
  local gap, over = EXT_GAP, 1.5 * MM
  self:line(x1 + nx * gap, y1 + ny * gap, x1 + nx * (off + over), y1 + ny * (off + over))
  self:line(x2 + nx * gap, y2 + ny * gap, x2 + nx * (off + over), y2 + ny * (off + over))
  self:alignedDim(x1 + nx * off, y1 + ny * off, x2 + nx * off, y2 + ny * off, label)
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
  -- Bogenradius: knapp die Haelfte des kuerzeren Schenkels, 4 bis 10 mm
  -- (grosse Boegen ueberdecken sich bei kleinen Teilen sonst gegenseitig)
  local r = math.max(4 * MM, math.min(10 * MM, 0.45 * math.min(la, lb)))
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
  local px, py = vx + tr * math.cos(am), vy + tr * math.sin(am) - self.fs * 0.35
  -- liegt dort schon eine andere Zahl, weiter nach aussen bzw. leicht seitlich ausweichen
  if not self:boxFree(TextBox(px, py, label, self.fs)) then
    local found = false
    for step = 1, 4 do
      for _, da in ipairs({ 0, 0.25, -0.25 }) do
        local a = am + da * sweep
        local t = tr + step * self.fs * 1.1
        local qx, qy = vx + t * math.cos(a), vy + t * math.sin(a) - self.fs * 0.35
        if self:boxFree(TextBox(qx, qy, label, self.fs)) then
          px, py, found = qx, qy, true
          break
        end
      end
      if found then break end
    end
  end
  self:text(px, py, label)
end
-- Radius: Pfeil von aussen auf den Bogen (Punkt px,py), Mittelpunkt cx,cy
-- Kreisdurchmesser: Masslinie innen durch den Mittelpunkt, Pfeile an den Kreis, Zahl darueber.
-- Ist der Kreis dafuer zu klein: Pfeile von aussen, Zahl rechts daneben (wie bei Vectric).
function Draw:diameter(cx, cy, r, label)
  local x1, x2 = cx - r, cx + r
  if not self:narrow(2 * r, label) then
    self:line(x1, cy, x2, cy)
    self:arrowhead(x1, cy, -1, 0)
    self:arrowhead(x2, cy, 1, 0)
    -- Zahl ueber der Linie; ist dort belegt, darunter
    local ty = cy + 1 * MM
    if not self:boxFree(TextBox(cx, ty, label, self.fs)) then ty = cy - 1 * MM - self.fs * 0.8 end
    self:text(cx, ty, label)
  else
    local e = self.arrow + 2 * MM
    self:line(x1 - e, cy, x2 + e + 1 * MM, cy)
    self:arrowhead(x1, cy, 1, 0)
    self:arrowhead(x2, cy, -1, 0)
    self:text(x2 + e + 1.5 * MM, cy - self.fs * 0.35, label, nil, false, "left")
  end
end
-- Radius von innen (wie Vectric): Linie vom Mittelpunkt zum Bogen, Pfeil am Bogen,
-- Zahl entlang der Linie
function Draw:radiusInside(cx, cy, px, py, label)
  local dx, dy = px - cx, py - cy
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1e-6 then return end
  local ux, uy = dx / len, dy / len
  self:line(cx, cy, px, py)
  self:arrowhead(px, py, ux, uy)
  local ang = atan2(uy, ux)
  if ang > math.pi / 2 + 1e-6 or ang <= -math.pi / 2 + 1e-6 then ang = ang + math.pi end
  local tnx, tny = -math.sin(ang), math.cos(ang)
  local mx, my
  for _, t in ipairs({ 0.5, 0.35, 0.65, 0.25, 0.75 }) do
    local x, y = cx + dx * t + tnx * 1 * MM, cy + dy * t + tny * 1 * MM
    if mx == nil then mx, my = x, y end
    if self:boxFree(self:angleBox(x, y, label, ang)) then mx, my = x, y; break end
  end
  self:textAngle(mx, my, label, ang)
end

function Draw:radius(cx, cy, px, py, label, sa, sw)
  local function place(qx, qy, l)
    local dx, dy = qx - cx, qy - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then return nil end
    dx, dy = dx / len, dy / len
    local side = (dx >= 0) and 1 or -1
    local align = side > 0 and "left" or "right"
    local ox, oy = qx + dx * l, qy + dy * l
    local sx = ox + side * 2 * MM
    local tx, ty = sx + side * 0.8 * MM, oy - self.fs * 0.35
    return { qx = qx, qy = qy, dx = dx, dy = dy, ox = ox, oy = oy, sx = sx, tx = tx, ty = ty, align = align,
             free = self:boxFree(TextBox(tx, ty, label, self.fs, false, align)) }
  end
  local best = place(px, py, 6 * MM)
  if not best then return end
  if not best.free and sa and sw then
    -- 1) entlang des Bogens seitlich ausweichen (gleiche kurze Hinweislinie)
    local r = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
    for _, t in ipairs({ 0.4, 0.6, 0.3, 0.7, 0.2, 0.8, 0.12, 0.88 }) do
      local a = sa + sw * t
      local c = place(cx + r * math.cos(a), cy + r * math.sin(a), 6 * MM)
      if c and c.free then best = c; break end
    end
  end
  if not best.free then
    -- 2) sonst die Hinweislinie verlaengern (Beschriftungen staffeln sich nach aussen)
    for step = 1, 8 do
      local c = place(px, py, 6 * MM + step * self.fs * 1.3)
      if c and c.free then best = c; break end
    end
  end
  self:line(best.qx, best.qy, best.ox, best.oy)
  self:line(best.ox, best.oy, best.sx, best.oy)
  self:arrowhead(best.qx, best.qy, -best.dx, -best.dy)
  self:text(best.tx, best.ty, label, nil, false, best.align)
end
-- senkrechtes Mass: von ya bis yb, Bezugskante xref, Masslinie bei xline (links)
function Draw:vdim(ya, yb, xref, xline, label)
  local gap, over = EXT_GAP, 1.5 * MM
  self:line(xref - gap, ya, xline - over, ya)
  self:line(xref - gap, yb, xline - over, yb)
  if self:narrow(yb - ya, label) then
    local e = self.arrow + 2 * MM
    local ty = ya - e - 1 * MM                       -- Zahl unten daneben
    self:line(xline, ty, xline, yb + e)
    self:arrowhead(xline, ya, 0, 1)
    self:arrowhead(xline, yb, 0, -1)
    self:text(xline + self.fs * 0.35, ty - 0.5 * MM, label, nil, true, "right")
    return
  end
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
-- Fenstergroesse und Zoomstufe merken, damit der Dialog beim naechsten
-- Start wieder so gross und so skaliert aufgeht wie zuletzt. Wird auch
-- bei "Abbrechen" gespeichert, sonst geht die Groesse wieder verloren.
-- ------------------------------------------------------------------
local WIN_W_DEFAULT = 520
local WIN_H_DEFAULT = 895

local function SaveWindowState(reg, dialog)
  if dialog.WindowWidth ~= nil and dialog.WindowWidth > 0 then
    reg:SetDouble("WindowWidth", dialog.WindowWidth)
  end
  if dialog.WindowHeight ~= nil and dialog.WindowHeight > 0 then
    reg:SetDouble("WindowHeight", dialog.WindowHeight)
  end
  reg:SetString("ZoomLevel", dialog:GetDropDownListValue("ZoomLevel") or "Auto")
end

-- ------------------------------------------------------------------
-- Hauptprogramm
-- ------------------------------------------------------------------
-- ------------------------------------------------------------------
-- Knopf im Dialog: Layer fuer die individuelle Bemassung anlegen
-- (VCarve ruft OnLuaButton_<Id> auf, wenn ein Knopf der Klasse "LuaButton" gedrueckt wird)
-- ------------------------------------------------------------------
function OnLuaButton_CreateDimLayer(dialog)
  local en = false
  pcall(function() en = dialog:GetRadioIndex("Lang") == 2 end)
  local function T(de, e) return en and e or de end
  local name = ""
  pcall(function() name = dialog:GetTextField("DimCustomLayer") or "" end)
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    DisplayMessageBox(T("Bitte zuerst einen Layernamen eintragen.", "Please enter a layer name first."))
    return true
  end
  local job = VectricJob()
  if not job.Exists then return true end
  local exists = false
  pcall(function()
    local lm = job.LayerManager
    local lpos = lm:GetHeadPosition()
    while lpos ~= nil do
      local layer
      layer, lpos = lm:GetNext(lpos)
      if NormName(LayerName(layer)) == NormName(name) then exists = true end
    end
  end)
  local layer = nil
  local ok = pcall(function() layer = job.LayerManager:GetLayerWithName(name) end)
  if not ok or layer == nil then
    DisplayMessageBox(T("Der Layer konnte nicht angelegt werden.", "The layer could not be created."))
    return true
  end
  if not exists then SetLayerColour(layer, CUSTOM_LAYER_RGB[1], CUSTOM_LAYER_RGB[2], CUSTOM_LAYER_RGB[3]) end
  pcall(function() layer.Visible = true end)
  pcall(function() job.LayerManager:SetActiveLayer(layer) end)   -- gleich zum Zeichnen auswaehlen
  pcall(function() job:Refresh2DView() end)
  if exists then
    DisplayMessageBox(T("Der Layer \"" .. name .. "\" ist bereits vorhanden.",
                        "The layer \"" .. name .. "\" already exists.") ..
      T("\n\nDialog schliessen, den Layer in VCarve als aktiven Layer waehlen und die Masslinien zeichnen.",
        "\n\nClose the dialog, make the layer active in VCarve and draw the dimension lines."))
  else
    DisplayMessageBox(T("Der Layer \"" .. name .. "\" wurde angelegt und kann jetzt bearbeitet werden.",
                        "The layer \"" .. name .. "\" has been created and can now be edited.") ..
      T("\n\nDialog schliessen (Abbrechen), den Layer in VCarve als aktiven Layer waehlen und Linien" ..
        " von Pfeil zu Pfeil zeichnen (3 Punkte = Winkel). Danach das Gadget erneut starten.",
        "\n\nClose the dialog (Cancel), make the layer active in VCarve and draw lines" ..
        " from arrow to arrow (3 points = angle). Then run the gadget again."))
  end
  return true
end

function main(script_path)
  local reg = Registry("PDF_Export")
  local lang = reg:GetInt("Lang", 1)                 -- 1 = Deutsch, 2 = English
  local function T(de, en) return (lang == 2) and en or de end

  local job = VectricJob()
  if not job.Exists then
    DisplayMessageBox(T("Kein Job geoeffnet.", "No job open."))
    return false
  end

  -- Zuletzt benutzte Fenstergroesse wiederherstellen (Standard, falls noch nichts
  -- gemerkt wurde oder ein unbrauchbar kleiner Wert in der Registry steht)
  local win_w = reg:GetDouble("WindowWidth", WIN_W_DEFAULT)
  local win_h = reg:GetDouble("WindowHeight", WIN_H_DEFAULT)
  if win_w < 300 then win_w = WIN_W_DEFAULT end
  if win_h < 300 then win_h = WIN_H_DEFAULT end

  -- Fenster nie groesser als der Bildschirm (Groesse meldet der Dialog beim letzten Oeffnen)
  local scr_w, scr_h = reg:GetInt("ScreenW", 0), reg:GetInt("ScreenH", 0)
  if scr_h > 300 then win_h = math.min(win_h, scr_h - 60) end
  if scr_w > 300 then win_w = math.min(win_w, scr_w - 40) end

  local dialog = HTML_Dialog(false, "file:" .. script_path .. "\\Vektor_PDF_".. G_version.. ".htm", win_w, win_h, G_title .. " - Version " .. VersionText())
  dialog:AddDropDownList("ZoomLevel", reg:GetString("ZoomLevel", "Auto"))
  dialog:AddRadioGroup("Lang", lang)
  dialog:AddTextField("Version", "v" .. VersionText())
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
  AddNum("Margin", 10)
  AddNum("FontSize", 3.5)
  dialog:AddRadioGroup("ScaleMode", reg:GetInt("ScaleMode", 1))
  dialog:AddRadioGroup("Orient", reg:GetInt("Orient", 1))
  -- Quelle: 1 = Auswahl, 2 = alle sichtbaren Layer, 3 = gewaehlte Layer (wird gemerkt)
  local src_def = job.Selection.IsEmpty and 2 or 1
  if reg:GetInt("Source", 0) == 3 then src_def = 3 end
  dialog:AddRadioGroup("Source", src_def)
  -- Layerliste fuer die Auswahl im Dialog: "1:Name" (sichtbar) bzw. "0:Name" (ausgeblendet)
  local layer_items = {}
  pcall(function()
    local lm = job.LayerManager
    local lpos = lm:GetHeadPosition()
    while lpos ~= nil do
      local layer
      layer, lpos = lm:GetNext(lpos)
      local n = LayerName(layer)
      -- interne Werkzeugweg-Layer von VCarve (z. B. "Werkzeugweg-Vorschauen") nicht anbieten:
      -- sie enthalten nur Werkzeugweg-Objekte und keine Vektoren
      local objs, tp = 0, 0
      pcall(function()
        local opos = layer:GetHeadPosition()
        while opos ~= nil do
          local obj
          obj, opos = layer:GetNext(opos)
          objs = objs + 1
          local ok, cn = pcall(function() return obj.ClassName end)
          if ok and type(cn) == "string" and cn:find("Toolpath") then tp = tp + 1 end
        end
      end)
      local printable = not (objs > 0 and tp == objs)
      local ln = n:lower()
      if ln:find("werkzeugweg") or ln:find("toolpath") then printable = false end
      if n ~= "" and printable then
        if NormName(n) ~= NormName(reg:GetString("DimCustomLayer", "pdf_dim")) then
          layer_items[#layer_items + 1] = (layer.Visible and "1:" or "0:") .. n:gsub("|", "/")
        end
      end
    end
  end)
  dialog:AddTextField("LayerList", table.concat(layer_items, "|"))
  dialog:AddTextField("LayerSel", reg:GetString("LayerSel", ""))
  dialog:AddRadioGroup("SheetMode", reg:GetInt("SheetMode", 1))
  dialog:AddCheckBox("DrawBorder", reg:GetBool("DrawBorder", false))
  dialog:AddCheckBox("DimAuto", reg:GetBool("DimAuto", true))
  dialog:AddCheckBox("DimCustom", reg:GetBool("DimCustom", true))
  dialog:AddTextField("DimCustomLayer", reg:GetString("DimCustomLayer", "pdf_dim"))
  dialog:AddCheckBox("DimOverall", reg:GetBool("DimOverall", true))
  dialog:AddCheckBox("DimEach", reg:GetBool("DimEach", false))
  dialog:AddCheckBox("DimCircle", reg:GetBool("DimCircle", true))
  dialog:AddCheckBox("DimPoly", reg:GetBool("DimPoly", false))
  AddNum("MinDim", 25)
  dialog:AddCheckBox("DimRadius", reg:GetBool("DimRadius", false))
  dialog:AddCheckBox("DimRadiusOnce", reg:GetBool("DimRadiusOnce", true))
  dialog:AddCheckBox("DimRadiusIn", reg:GetBool("DimRadiusIn", false))
  dialog:AddCheckBox("DimAngle", reg:GetBool("DimAngle", false))
  dialog:AddRadioGroup("DimColor", reg:GetInt("DimColor", 1))
  dialog:AddCheckBox("ShowScale", reg:GetBool("ShowScale", true))
  dialog:AddTextField("Title", reg:GetString("Title", ""))
  dialog:AddTextField("Note", "")

  dialog:AddTextField("ScrW", "")
  dialog:AddTextField("ScrH", "")
  local dialog_ok = dialog:ShowDialog()
  SaveWindowState(reg, dialog)
  -- Bildschirmgroesse merken (auch bei Abbrechen), damit das Fenster beim naechsten Mal passt
  local sw = tonumber(dialog:GetTextField("ScrW") or "")
  local sh = tonumber(dialog:GetTextField("ScrH") or "")
  if sw and sw > 300 then reg:SetInt("ScreenW", math.floor(sw)) end
  if sh and sh > 300 then reg:SetInt("ScreenH", math.floor(sh)) end
  if not dialog_ok then return false end

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
  local vec_color   = 6                                   -- Linien immer in der Layerfarbe
  local margin_mm   = GetNum("Margin")
  local font_mm     = GetNum("FontSize")
  local scale_mode  = dialog:GetRadioIndex("ScaleMode")      -- 1 = A4, 2 = 1:1
  local orient      = dialog:GetRadioIndex("Orient")         -- 1 = automatisch, 2 = hoch, 3 = quer
  local source      = dialog:GetRadioIndex("Source")
  local selected_only = source == 1
  local layer_sel   = dialog:GetTextField("LayerSel") or ""
  local sheet_mode  = dialog:GetRadioIndex("SheetMode")     -- 1 = aktuelle Seite, 2 = alle Seiten
  local draw_border = dialog:GetCheckBox("DrawBorder")
  local dim_overall = dialog:GetCheckBox("DimOverall")
  local dim_each    = dialog:GetCheckBox("DimEach")
  local dim_circle  = dialog:GetCheckBox("DimCircle")
  local dim_poly    = dialog:GetCheckBox("DimPoly")
  local min_dim_mm  = GetNum("MinDim")
  if #bad > 0 then
    DisplayMessageBox(T("Bitte gueltige Zahlen eingeben (Komma oder Punkt): ",
                        "Please enter valid numbers (comma or point): ") .. table.concat(bad, ", "))
    return false
  end
  local dim_radius  = dialog:GetCheckBox("DimRadius")
  local radius_once = dialog:GetCheckBox("DimRadiusOnce")
  local radius_in   = dialog:GetCheckBox("DimRadiusIn")
  local dim_angle   = dialog:GetCheckBox("DimAngle")
  local dim_auto    = dialog:GetCheckBox("DimAuto")
  custom_dims       = dialog:GetCheckBox("DimCustom")
  PDF_DIM_LAYER     = (dialog:GetTextField("DimCustomLayer") or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local dim_layer   = PDF_DIM_LAYER        -- Layer der individuellen Bemassung
  local hide_dims   = false
  local dim_color   = dialog:GetRadioIndex("DimColor")   -- 1 schwarz, 2 blau, 3 rot, 4 gruen, 5 grau
  local show_scale  = dialog:GetCheckBox("ShowScale")
  local title       = dialog:GetTextField("Title") or ""
  local note        = dialog:GetTextField("Note") or ""

  reg:SetDouble("LineWidth", line_mm)
  reg:SetDouble("DimLineWidth", dim_line_mm)
  reg:SetDouble("ArrowSize", arrow_mm)
  reg:SetDouble("Margin", margin_mm)
  reg:SetDouble("FontSize", font_mm)
  reg:SetInt("ScaleMode", scale_mode)
  reg:SetInt("Orient", orient)
  reg:SetInt("SheetMode", sheet_mode)
  reg:SetBool("DrawBorder", draw_border)
  reg:SetBool("DimOverall", dim_overall)
  reg:SetBool("DimEach", dim_each)
  reg:SetBool("DimCircle", dim_circle)
  reg:SetBool("DimPoly", dim_poly)
  reg:SetDouble("MinDim", min_dim_mm)
  reg:SetBool("DimRadius", dim_radius)
  reg:SetBool("DimRadiusOnce", radius_once)
  reg:SetBool("DimRadiusIn", radius_in)
  reg:SetBool("DimAngle", dim_angle)
  reg:SetBool("DimAuto", dim_auto)
  reg:SetBool("DimCustom", custom_dims)
  reg:SetString("DimCustomLayer", PDF_DIM_LAYER)

  -- Individuelle Bemassung: Layer muss benannt sein; fehlt er in der Datei, wird er angelegt
  local custom_created = false
  if custom_dims then
    if PDF_DIM_LAYER == "" then
      DisplayMessageBox(T("Bitte bei \"Individuelle Bemassung\" einen Layernamen eintragen.",
                          "Please enter a layer name for \"Custom dimensions\"."))
      return false
    end
    local exists = false
    pcall(function()
      local lm = job.LayerManager
      local lpos = lm:GetHeadPosition()
      while lpos ~= nil do
        local layer
        layer, lpos = lm:GetNext(lpos)
        if NormName(LayerName(layer)) == NormName(PDF_DIM_LAYER) then exists = true end
      end
    end)
    if not exists then
      local nl = nil
      local okc = pcall(function() nl = job.LayerManager:GetLayerWithName(PDF_DIM_LAYER) end)
      if okc then
        custom_created = true
        if nl then SetLayerColour(nl, CUSTOM_LAYER_RGB[1], CUSTOM_LAYER_RGB[2], CUSTOM_LAYER_RGB[3]) end
        pcall(function() job:Refresh2DView() end)
      end
    end
  end
  if not dim_auto then              -- Autobemassung aus: alle automatischen Masse aus (Haekchen bleiben gemerkt)
    dim_overall, dim_each, dim_poly, dim_radius, dim_angle, dim_circle = false, false, false, false, false, false
  end
  reg:SetInt("DimColor", dim_color)
  reg:SetBool("ShowScale", show_scale)
  reg:SetString("Title", title)
  reg:SetInt("Source", source)
  reg:SetString("LayerSel", layer_sel)

  -- gewaehlte Layer
  local layer_filter, layer_count = nil, 0
  if source == 3 then
    layer_filter = {}
    for n in (layer_sel .. "|"):gmatch("([^|]*)|") do
      if n ~= "" then layer_filter[NormName(n)] = true; layer_count = layer_count + 1 end
    end
    if layer_count == 0 then
      DisplayMessageBox(T("Bitte mindestens einen Layer ankreuzen.", "Please tick at least one layer."))
      return false
    end
  end

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
  skipped_dims = 0
  vdim_ok, vdim_unsure, snap_verts, snap_segs = 0, 0, nil, nil
  layer_color_ok, layer_color_fail, layer_color_diag = 0, 0, nil
  straight_bez = 0
  bezier_fallback = 0
  bezier_info = nil
  local sheet_list, active_id = JobSheets(job)
  known_sheets = sheet_list
  local active_key = SheetKey(active_id)
  local contours, dim_lines, dim_info = CollectContours(job, selected_only, dim_layer, layer_filter)
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
      p.color = c.color
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
    local dim_res = (dim_overall or dim_each or dim_poly) and (8 * MM + 2 * fs) or 0
    local lines = 0
    if title ~= "" then lines = lines + 1.4 end
    if note  ~= "" then lines = lines + 1 end
    local title_res = lines > 0 and (lines * fs * 1.5 + 3 * MM) or 0
    local foot_res  = show_scale and (fs * 1.5) or 0

    -- Seitenaufteilung; res = Platz fuer Masse links und unten (wird bei Bedarf vergroessert)
    local page_w, page_h, scale, offx, offy
    -- Radius-Beschriftungen ("R ..." mit Pfeil von aussen) brauchen rechts/oben Platz
    local has_r = dim_radius or dim_circle
    for _, l in ipairs(dim_lines) do if l.radius then has_r = true end end
    local rres = has_r and (TextWidth("R 000.000\"", fs) + 8 * MM) or 0
    local function Layout(res)
      if scale_mode == 2 then
        scale  = unit_pt
        page_w = w * scale + 2 * margin + res + rres
        page_h = h * scale + 2 * margin + res + title_res + foot_res + rres
      else
        page_w, page_h = 595.28, 841.89
        local landscape = (orient == 3) or (orient ~= 2 and w > h)
        if landscape then page_w, page_h = page_h, page_w end
        scale = math.min((page_w - 2 * margin - res - rres) / w,
                         (page_h - 2 * margin - res - title_res - foot_res - rres) / h)
      end
      local area_x = margin + res
      local area_y = margin + res + foot_res
      local area_w = page_w - margin - area_x - rres
      local area_h = page_h - margin - title_res - area_y - rres
      offx = area_x + (area_w - w * scale) / 2
      offy = area_y + (area_h - h * scale) / 2
    end
    local function tx(x) return offx + (x - minx) * scale end
    local function ty(y) return offy + (y - miny) * scale end

    -- Lineare Masse planen: jede Masslinie bekommt eine eigene Spur, damit keine
    -- Masslinie und keine Zahl auf einer anderen liegt
    local near = 5 * MM                  -- Abstand Einzelmasse
    local far  = near + 2 * fs + 3 * MM  -- Abstand Gesamtmasse (mindestens)
    local lane = fs + 2.5 * MM           -- Abstand zwischen zwei Masslinien
    local function PlanDims()
      local hs, vs, cs, ls = {}, {}, {}, {}
      local arrow_pt = (arrow_mm and arrow_mm > 0) and arrow_mm * MM or 2.5 * MM
      local function item(a, b, ref, line, label)
        local tw, mid = TextWidth(label, fs), (a + b) / 2
        if b - a < 2 * arrow_pt + tw + 2 * MM then     -- schmal: Pfeile aussen, Zahl links/unten daneben
          local e = arrow_pt + 2 * MM
          return { a = a, b = b, ref = ref, line = line, label = label,
                   lo = a - e - 1.5 * MM - tw - 1 * MM, hi = b + e + 1 * MM }
        end
        return { a = a, b = b, ref = ref, line = line, label = label,
                 lo = math.min(a, mid - tw / 2) - 1 * MM, hi = math.max(b, mid + tw / 2) + 1 * MM }
      end
      -- gerades Stueck bemassen: waagrecht/senkrecht in Spuren, schraeg parallel daneben
      local function StraightDim(s, min_len, tol)
        local x1, y1, x2, y2 = s[1], s[2], s[3], s[4]
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        if len < min_len or len <= tol then return end
        if math.abs(y2 - y1) < tol then
          hs[#hs + 1] = item(tx(math.min(x1, x2)), tx(math.max(x1, x2)), ty(y1), ty(y1) - near, fmt(len))
        elseif math.abs(x2 - x1) < tol then
          vs[#vs + 1] = item(ty(math.min(y1, y2)), ty(math.max(y1, y2)), tx(x1), tx(x1) - near, fmt(len))
        else
          ls[#ls + 1] = { tx(x1), ty(y1), tx(x2), ty(y2), fmt(len) }
        end
      end
      if dim_each then
        local tol = in_mm and 0.05 or 0.002
        local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4   -- Eingabe immer in mm
        for _, p in ipairs(paths) do
          local pw, ph = p.maxx - p.minx, p.maxy - p.miny
          local is_total = math.abs(p.minx - vminx) < tol and math.abs(p.maxx - vmaxx) < tol and
                           math.abs(p.miny - vminy) < tol and math.abs(p.maxy - vmaxy) < tol
          local big_enough = math.max(pw, ph) >= min_dim
          local s1 = (not p.closed) and #p.segs == 1 and type(p.segs[1]) == "table" and p.segs[1] or nil
          if s1 and not p.in_group then
            -- einzelne gerade Linie: Laenge bemassen (waagrecht/senkrecht mit Spuren, sonst schraeg)
            StraightDim(s1, min_dim, tol)
          elseif p.closed and not p.in_group and big_enough and pw > tol and ph > tol and
             not (is_total and dim_overall) then
            if IsCircle(p, tol) then
              -- Kreis: eigener Menuepunkt "Kreis Ø" (siehe unten)
            else
              local same_w = dim_overall and math.abs(p.minx - vminx) < tol and math.abs(p.maxx - vmaxx) < tol
              local same_h = dim_overall and math.abs(p.miny - vminy) < tol and math.abs(p.maxy - vmaxy) < tol
              if not same_w then
                hs[#hs + 1] = item(tx(p.minx), tx(p.maxx), ty(p.miny), ty(p.miny) - near, fmt(pw))
              end
              if not same_h then
                vs[#vs + 1] = item(ty(p.miny), ty(p.maxy), tx(p.minx), tx(p.minx) - near, fmt(ph))
              end
            end
          end
        end
      end
      if dim_circle then                   -- Kreise: Radius mit Pfeil von aussen
        local tol = in_mm and 0.05 or 0.002
        local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4
        for _, p in ipairs(paths) do
          local pw, ph = p.maxx - p.minx, p.maxy - p.miny
          if not p.in_group and IsCircle(p, tol) then   -- Kreise unabhaengig von "Einzelmasse ab"
            cs[#cs + 1] = { tx((p.minx + p.maxx) / 2), ty((p.miny + p.maxy) / 2), pw * scale / 2, "R " .. fmt(pw / 2) }
          end
        end
      end
      if dim_poly then
        local tol = in_mm and 0.05 or 0.002
        local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4
        for _, p in ipairs(paths) do
          local pw, ph = p.maxx - p.minx, p.maxy - p.miny
          if not p.closed and not p.in_group and #p.segs > 1 and math.max(pw, ph) >= min_dim then
            for _, s in ipairs(p.segs) do
              if type(s) == "table" then StraightDim(s, tol, tol) end
            end
          end
        end
      end
      -- naechstgelegene zuerst; wer kollidiert, rutscht eine Spur weiter nach aussen
      local function place(list, total)
        table.sort(list, function(p, q) return p.ref > q.ref end)
        if total then list[#list + 1] = total end
        local done = {}
        for _, it in ipairs(list) do
          local moved = true
          while moved do
            moved = false
            for _, q in ipairs(done) do
              if it.lo < q.hi and it.hi > q.lo and math.abs(it.line - q.line) < lane - 0.01 then
                it.line = q.line - lane
                moved = true
              end
            end
          end
          done[#done + 1] = it
        end
      end
      local th, tv
      if dim_overall then
        th = item(tx(vminx), tx(vmaxx), ty(vminy), ty(vminy) - far, fmt(vmaxx - vminx))
        tv = item(ty(vminy), ty(vmaxy), tx(vminx), tx(vminx) - far, fmt(vmaxy - vminy))
      end
      -- doppelte Masse (gleicher Wert, praktisch gleiche Strecke) nur 1x zeigen, auch gegen Gesamtmass
      local function dedupe(list, total)
        table.sort(list, function(p, q) return p.ref > q.ref end)   -- naechstgelegenes bleibt
        local out = {}
        local function same(p, q)
          local t = math.max(1.5 * MM, 0.02 * math.abs(q.b - q.a))
          return p.label == q.label and math.abs(p.a - q.a) < t and math.abs(p.b - q.b) < t
        end
        for _, it in ipairs(list) do
          local dup = total and same(it, total)
          for _, q in ipairs(out) do if not dup and same(it, q) then dup = true end end
          if not dup then out[#out + 1] = it end
        end
        return out
      end
      hs = dedupe(hs, th); vs = dedupe(vs, tv)
      place(hs, th); place(vs, tv)
      -- benoetigter Platz unter bzw. links neben der Zeichnung
      local depth = 0
      for _, it in ipairs(hs) do depth = math.max(depth, ty(vminy) - it.line) end
      for _, it in ipairs(vs) do depth = math.max(depth, tx(vminx) - it.line) end
      return hs, vs, cs, depth, ls
    end

    Layout(dim_res)
    local hdims, vdims, cdims, depth, ldims = PlanDims()
    if depth > dim_res + 0.5 then        -- mehr Spuren noetig -> mehr Platz reservieren
      Layout(depth)
      hdims, vdims, cdims, _, ldims = PlanDims()
    end

    -- 1) Zeichnung
    local s = { f(line_mm * MM) .. " w 1 J 1 j " .. ColorOps(vec_color) }
    local last_col = nil
    for _, p in ipairs(paths) do
      if vec_color == 6 then                 -- Farbe des Layers uebernehmen
        local rgb = p.color or { 0, 0, 0 }
        if rgb[1] > 0.9 and rgb[2] > 0.9 and rgb[3] > 0.9 then rgb = { 0.6, 0.6, 0.6 } end  -- weiss -> grau
        local col = string.format("%.3f %.3f %.3f", rgb[1], rgb[2], rgb[3])
        if col ~= last_col then
          s[#s + 1] = col .. " RG"
          last_col = col
        end
      end
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
    for _, it in ipairs(hdims) do d:hdim(it.a, it.b, it.ref, it.line, it.label) end
    for _, it in ipairs(vdims) do d:vdim(it.a, it.b, it.ref, it.line, it.label) end
    -- Kreise: Radius mit Pfeil von aussen (schraeg rechts oben, weicht bei Bedarf entlang des Kreises aus)
    for _, c in ipairs(cdims) do
      local a0 = math.pi / 4
      if radius_in then
        d:radiusInside(c[1], c[2], c[1] + c[3] * math.cos(a0), c[2] + c[3] * math.sin(a0), c[4])
      else
        d:radius(c[1], c[2], c[1] + c[3] * math.cos(a0), c[2] + c[3] * math.sin(a0), c[4], a0 - math.pi, 2 * math.pi)
      end
    end
    for _, l in ipairs(ldims) do d:offsetDim(l[1], l[2], l[3], l[4], l[5], near) end

    -- Radien an Boegen: alle Boegen; mit "gleiche Radien nur einmal" je Vektor jeder Radius nur 1x
    if dim_radius then
      local tol = in_mm and 0.05 or 0.002
      local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4
      local all_done = {}                  -- gleicher Bogen (Mittelpunkt + Radius) nur einmal
      for _, p in ipairs(paths) do
        local pw, ph = p.maxx - p.minx, p.maxy - p.miny
        local is_circle = IsCircle(p, tol)
        if not p.in_group and math.max(pw, ph) >= min_dim and not (is_circle and dim_circle) then
          local done = {}
          for _, a in ipairs(p.arcs) do
            local seen = false
            if radius_once then
              for _, r in ipairs(done) do if math.abs(r - a.r) < tol then seen = true end end
            end
            for _, q in ipairs(all_done) do
              if math.abs(q.r - a.r) < tol and math.abs(q.cx - a.cx) < tol and math.abs(q.cy - a.cy) < tol then seen = true end
            end
            if not seen and a.r > tol then
              done[#done + 1] = a.r
              all_done[#all_done + 1] = a
              if radius_in then
                d:radiusInside(tx(a.cx), ty(a.cy), tx(a.px), ty(a.py), "R " .. fmt(a.r))
              else
                d:radius(tx(a.cx), ty(a.cy), tx(a.px), ty(a.py), "R " .. fmt(a.r), a.sa, a.sw)
              end
            end
          end
        end
      end
    end

    -- Winkel an Ecken zwischen zwei Geraden (90 und 180 Grad werden ausgelassen)
    if dim_angle then
      local min_dim = in_mm and min_dim_mm or min_dim_mm / 25.4
      -- gleicher Winkel in der Naehe (z. B. Innen- und Aussenkontur einer Doppellinie)
      -- wird nur einmal bemasst
      local placed = {}
      local near_pt = 8 * MM
      local function already(x, y, deg)
        for _, q in ipairs(placed) do
          if math.abs(q[3] - deg) < 0.5 and (q[1] - x) ^ 2 + (q[2] - y) ^ 2 < near_pt * near_pt then
            return true
          end
        end
        placed[#placed + 1] = { x, y, deg }
        return false
      end
      for _, p in ipairs(paths) do
        local pw, ph = p.maxx - p.minx, p.maxy - p.miny
        if not p.in_group and math.max(pw, ph) >= min_dim then
          local shown = {}                 -- geschlossener Vektor: gleicher Winkel nur einmal
          for _, cn in ipairs(PathCorners(p)) do
            local deg = cn[7]
            local key = fmtAng(deg)
            if math.abs(deg - 90) > 0.5 and deg > 0.5 and deg < 179.5 and
               not (p.closed and shown[key]) and
               not already(tx(cn[1]), ty(cn[2]), deg) then
              shown[key] = true
              d:angleDim(tx(cn[1]), ty(cn[2]), tx(cn[3]), ty(cn[4]), tx(cn[5]), ty(cn[6]), key)
            end
          end
        end
      end
    end

    -- Manuelle Masse aus den Hilfslinien des Bemassungs-Layers
    -- Fuer die Masshilfslinien: alle Vektoren als gerade Stuecke (Modellkoordinaten)
    local segs = nil
    local function Segments()
      if segs then return segs end
      segs = {}
      for _, p in ipairs(paths) do
        local sx, sy, lx, ly = nil, nil, nil, nil
        for _, cmd in ipairs(p.cmds) do
          local k = cmd[1]
          if k == "m" then
            sx, sy, lx, ly = cmd[2], cmd[3], cmd[2], cmd[3]
          elseif k == "l" then
            segs[#segs + 1] = { lx, ly, cmd[2], cmd[3] }
            lx, ly = cmd[2], cmd[3]
          elseif k == "c" then                       -- Bezier abtasten
            local px, py = lx, ly
            for i = 1, 16 do
              local t = i / 16
              local a, b, c, e = (1 - t) ^ 3, 3 * (1 - t) ^ 2 * t, 3 * (1 - t) * t * t, t ^ 3
              local qx = a * lx + b * cmd[2] + c * cmd[4] + e * cmd[6]
              local qy = a * ly + b * cmd[3] + c * cmd[5] + e * cmd[7]
              segs[#segs + 1] = { px, py, qx, qy }
              px, py = qx, qy
            end
            lx, ly = cmd[6], cmd[7]
          elseif k == "h" and sx then
            segs[#segs + 1] = { lx, ly, sx, sy }
            lx, ly = sx, sy
          end
        end
      end
      return segs
    end
    -- naechster Treffer eines Strahls P + t*(nx,ny), t > 0, mit einem Vektor
    local max_reach = 0.3 * math.sqrt((vmaxx - vminx) ^ 2 + (vmaxy - vminy) ^ 2)
    local touch = in_mm and 0.5 or 0.02                 -- Strahl "streift" einen Punkt (Tangente, Ecke)
    local function RayHit(px, py, nx, ny)
      local best = nil
      for _, sg in ipairs(Segments()) do
        local dx, dy = sg[3] - sg[1], sg[4] - sg[2]
        local den = nx * dy - ny * dx
        if math.abs(den) > 1e-12 then
          local ax, ay = sg[1] - px, sg[2] - py
          local t = (ax * dy - ay * dx) / den
          local u = (ax * ny - ay * nx) / den
          if u >= -1e-9 and u <= 1 + 1e-9 and t > 1e-6 and t <= max_reach and (best == nil or t < best) then
            best = t
          end
        end
        -- Endpunkte, an denen der Strahl knapp vorbeigeht (z. B. Kreis-Tangente)
        for _, q in ipairs({ { sg[1], sg[2] }, { sg[3], sg[4] } }) do
          local qx, qy = q[1] - px, q[2] - py
          local t = qx * nx + qy * ny
          if t > 1e-6 and t <= max_reach and math.abs(qx * ny - qy * nx) <= touch and (best == nil or t < best) then
            best = t
          end
        end
      end
      return best
    end
    -- Masshilfslinie vom Vektor bis knapp ueber die Masslinie (senkrecht zur Masslinie)
    -- liegt der Punkt schon auf einem Vektor? Dann braucht er keine Hilfslinie
    local function OnVector(px, py)
      for _, sg in ipairs(Segments()) do
        local dx, dy = sg[3] - sg[1], sg[4] - sg[2]
        local l2 = dx * dx + dy * dy
        local t = 0
        if l2 > 0 then t = math.max(0, math.min(1, ((px - sg[1]) * dx + (py - sg[2]) * dy) / l2)) end
        local qx, qy = sg[1] + t * dx - px, sg[2] + t * dy - py
        if qx * qx + qy * qy <= touch * touch then return true end
      end
      return false
    end
    local function ExtLine(px, py, nx, ny)
      if OnVector(px, py) then return end
      local t1, t2 = RayHit(px, py, nx, ny), RayHit(px, py, -nx, -ny)
      local t, sx = t1, 1
      if t2 and (t == nil or t2 < t) then t, sx = t2, -1 end
      if not t then return end
      local hx, hy = px + sx * nx * t, py + sx * ny * t        -- Treffpunkt am Vektor
      local ax, ay = tx(px), ty(py)
      local bx, by = tx(hx), ty(hy)
      local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
      local gap, over = EXT_GAP, 1.5 * MM
      if len <= gap + 0.1 then return end
      local ux, uy = (ax - bx) / len, (ay - by) / len        -- vom Vektor zur Masslinie
      d:line(bx + ux * gap, by + uy * gap, ax + ux * over, ay + uy * over)
    end
    -- Hilfslinie vom bekannten Messpunkt (px, py) zum Masslinien-Ende (ex, ey)
    local function ExtTo(px, py, ex, ey)
      local ax, ay = tx(ex), ty(ey)
      local bx, by = tx(px), ty(py)
      local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
      local gap, over = EXT_GAP, 1.5 * MM
      if len <= gap + 0.1 then return end
      local ux, uy = (ax - bx) / len, (ay - by) / len
      -- Laeuft die Hilfslinie tangential vom Bauteil weg (z. B. Kreis-Scheitel), klebt sie anfangs
      -- an der Kontur -> erst dort beginnen, wo sie sich sichtbar von der Kontur geloest hat
      local clear = (line_mm * MM) / 2 + 0.5 * MM
      local start, sstep = 0, 0.25 * MM
      local seg = Segments()
      while start < len - gap do
        local mx, my = px + ux * start / scale, py + uy * start / scale
        local dmin = math.huge
        for _, sg in ipairs(seg) do
          local dx, dy = sg[3] - sg[1], sg[4] - sg[2]
          local l2 = dx * dx + dy * dy
          local t = 0
          if l2 > 0 then t = math.max(0, math.min(1, ((mx - sg[1]) * dx + (my - sg[2]) * dy) / l2)) end
          local qx, qy = sg[1] + t * dx - mx, sg[2] + t * dy - my
          local dd = qx * qx + qy * qy
          if dd < dmin then dmin = dd end
        end
        if math.sqrt(dmin) * scale >= clear then break end
        start = start + sstep
      end
      gap = math.max(gap, start + 0.5 * MM)
      if len <= gap + 0.1 then return end
      d:line(bx + ux * gap, by + uy * gap, ax + ux * over, ay + uy * over)
    end
    for _, l in ipairs(dim_lines) do
      if l.radius then
        local lab = l.diam and ("\195\152 " .. fmt(2 * l.r)) or ("R " .. fmt(l.r))
        if l.inside then
          d:radiusInside(tx(l.cx), ty(l.cy), tx(l.px), ty(l.py), lab)
        else
          local a0 = atan2(l.py - l.cy, l.px - l.cx)
          d:radius(tx(l.cx), ty(l.cy), tx(l.px), ty(l.py), lab, a0 - math.pi, 2 * math.pi)
        end
      elseif l.angle then
        local a1 = atan2(l[2] - l.vy, l[1] - l.vx)
        local sw = atan2(l[4] - l.vy, l[3] - l.vx) - a1
        while sw > math.pi do sw = sw - 2 * math.pi end
        while sw <= -math.pi do sw = sw + 2 * math.pi end
        d:angleDim(tx(l.vx), ty(l.vy), tx(l[1]), ty(l[2]), tx(l[3]), ty(l[4]),
                   fmtAng(math.abs(sw) * 180 / math.pi))
      else
        local len = math.sqrt((l[3] - l[1]) ^ 2 + (l[4] - l[2]) ^ 2)
        if len > 0 and #paths > 0 then
          local nx, ny = -(l[4] - l[2]) / len, (l[3] - l[1]) / len
          if l.p1 then                     -- Vectric-Mass: Messpunkte am Bauteil bekannt
            ExtTo(l.p1[1], l.p1[2], l[1], l[2])
            ExtTo(l.p2[1], l.p2[2], l[3], l[4])
          else
            ExtLine(l[1], l[2], nx, ny)
            ExtLine(l[3], l[4], nx, ny)
          end
        end
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
        local c2, d2 = CollectContours(job, false, dim_layer, layer_filter)
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
    local hint = ""
    if tostring(err):lower():find("permission") then
      hint = T("\n\nDie Datei ist vermutlich noch in einem PDF-Programm geoeffnet (oder OneDrive synchronisiert sie gerade)."
               .. "\nBitte das PDF schliessen oder einen anderen Dateinamen waehlen.",
               "\n\nThe file is probably still open in a PDF viewer (or OneDrive is syncing it)."
               .. "\nPlease close the PDF or choose a different file name.")
    end
    DisplayMessageBox(T("PDF konnte nicht geschrieben werden:\n", "Could not write PDF:\n") .. tostring(err) .. hint)
    return false
  end

  local msg = G_title .. " v" .. VersionText() .. "\n\n" ..
              T("PDF gespeichert:\n", "PDF saved:\n") .. fd.PathName ..
              "\n\n" .. #paths .. T(" Vektoren, Linienstaerke ", " vectors, line width ") .. NumStr(line_mm) .. " mm"
  if #pages > 1 then
    msg = msg .. "\n" .. #pages .. T(" Seiten (je VCarve-Seite eine PDF-Seite)", " pages (one PDF page per VCarve sheet)")
  elseif sheet_note then
    msg = msg .. "\n" .. sheet_note
  end
  if layer_filter then
    msg = msg .. "\n" .. T("Layer: ", "Layers: ") .. layer_sel:gsub("|", ", ")
  end
  if sheet_diag then msg = msg .. sheet_diag end
  local n_group = 0
  for _, p in ipairs(paths) do if p.in_group then n_group = n_group + 1 end end
  if #dim_lines > 0 then
    local n_ang = 0
    for _, l in ipairs(dim_lines) do if l.angle then n_ang = n_ang + 1 end end
    msg = msg .. "\n" .. (#dim_lines - n_ang) .. T(" Laengenmass(e), ", " length dimension(s), ") ..
          n_ang .. T(" Winkelmass(e)", " angle dimension(s)") ..
          (vdim_ok > 0 and (T(" - davon ", " - ") .. vdim_ok .. T(" aus Vectric-Bemassungen", " from Vectric dimensions")) or "")
  end
  if dim_each then
    msg = msg .. "\n(" .. n_group .. T(" davon in Gruppen - ohne Einzelmasse)", " of them in groups - no individual dimensions)")
  end
  if custom_created then
    msg = msg .. "\n\n" .. T("Layer \"", "Layer \"") .. PDF_DIM_LAYER ..
          T("\" fuer die individuelle Bemassung wurde angelegt.", "\" for custom dimensions was created.")
  end
  if vdim_unsure > 0 then
    msg = msg .. "\n\n" .. vdim_unsure ..
          T(" Vectric-Bemassung(en) nicht sicher erkannt (z. B. schraeg) - fehlen im PDF." ..
            "\nDafuer eine Linie von Pfeil zu Pfeil auf den Layer \"" .. PDF_DIM_LAYER .. "\" zeichnen.",
            " Vectric dimension(s) not recognised reliably (e.g. aligned) - missing in the PDF." ..
            "\nDraw a line from arrow to arrow on layer \"" .. PDF_DIM_LAYER .. "\" instead.")
  end
  if vec_color == 6 and layer_color_ok == 0 then
    msg = msg .. T("\n\nHinweis: Layerfarben konnten nicht gelesen werden - Linien schwarz gedruckt.",
                   "\n\nNote: layer colours could not be read - lines printed in black.") ..
          "\n(" .. tostring(layer_color_diag) .. ")"
  end
  if straight_bez > 0 then
    msg = msg .. "\n" .. straight_bez .. T(" gerade Kurve(n) als Linie erkannt (werden bemasst)",
          " straight curve(s) recognised as lines (dimensioned)")
  end
  local other = skipped - skipped_dims
  if other > 0 then
    msg = msg .. "\n\n" .. other .. T(" Objekt(e) ohne Vektorform (z. B. Vectric-Text) wurden uebersprungen.",
          " object(s) without vector shape (e.g. Vectric text) were skipped.")
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
