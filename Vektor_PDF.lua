-- VECTRIC LUA SCRIPT
--[[
  Vektor_PDF  -  exportiert Vektoren als PDF mit einstellbarer Linienstaerke,
                 automatischer Bemassung und Beschriftung
  Fuer Aspire / VCarve (Gadget-API)

  Installation:
    Ordner "Vektor_PDF" (mit Vektor_PDF.lua und Vektor_PDF.htm) nach
    C:\ProgramData\Vectric\<Programm>\V12.5\Gadgets\  kopieren
]]

local atan2 = math.atan2 or math.atan
local MM = 72 / 25.4            -- Punkte je mm (PDF-Einheit)
local skipped = 0

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

-- Kontur -> { cmds = {...}, closed, all_arcs, minx, miny, maxx, maxy }
local function ContourToPath(contour, seg_len)
  local p = { cmds = {}, all_arcs = true, closed = contour.IsClosed,
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
    elseif span.IsBezierType then
      p.all_arcs = false
      local bez = CastSpanToBezierSpan(span)
      local c1, c2 = bez.ControlPoint1, bez.ControlPoint2
      cmds[#cmds + 1] = { "c", c1.X, c1.Y, c2.X, c2.Y, p2.X, p2.Y }
    else
      p.all_arcs = false
      cmds[#cmds + 1] = { "l", p2.X, p2.Y }
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
local function AddObject(obj, contours)
  local ok, contour = pcall(function() return obj:GetContour() end)
  if ok and contour ~= nil then
    contours[#contours + 1] = contour
    return
  end
  local gok, group = pcall(function() return CastCadObjectToCadObjectGroup(obj) end)
  if gok and group ~= nil then
    local iok = pcall(function()
      local pos = group:GetHeadPosition()
      while pos ~= nil do
        local child
        child, pos = group:GetNext(pos)
        AddObject(child, contours)
      end
    end)
    if iok then return end
  end
  skipped = skipped + 1
end

local function CollectContours(job, selected_only)
  local contours = {}
  if selected_only then
    local sel = job.Selection
    local pos = sel:GetHeadPosition()
    while pos ~= nil do
      local obj
      obj, pos = sel:GetNext(pos)
      AddObject(obj, contours)
    end
  else
    local lm = job.LayerManager
    local lpos = lm:GetHeadPosition()
    while lpos ~= nil do
      local layer
      layer, lpos = lm:GetNext(lpos)
      if layer.Visible then
        local pos = layer:GetHeadPosition()
        while pos ~= nil do
          local obj
          obj, pos = layer:GetNext(pos)
          AddObject(obj, contours)
        end
      end
    end
  end
  return contours
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
  local shift = (align == "left") and 0 or w / 2
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
local function WritePdf(filename, page_w, page_h, stream)
  local objs = {
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " .. f(page_w) .. " " .. f(page_h) ..
      "] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    "<< /Length " .. #stream .. " >>\nstream\n" .. stream .. "\nendstream",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
  }
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
  local job = VectricJob()
  if not job.Exists then
    DisplayMessageBox("Kein Job geoeffnet.")
    return false
  end

  local reg = Registry("PDF_Export")
  local dialog = HTML_Dialog(false, "file:" .. script_path .. "\\Vektor_PDF.htm", 520, 640, "PDF Export")
  dialog:AddDoubleField("LineWidth", reg:GetDouble("LineWidth", 0.5))
  dialog:AddDoubleField("Margin", reg:GetDouble("Margin", 10))
  dialog:AddDoubleField("FontSize", reg:GetDouble("FontSize", 3.5))
  dialog:AddRadioGroup("ScaleMode", reg:GetInt("ScaleMode", 1))
  dialog:AddRadioGroup("Source", job.Selection.IsEmpty and 2 or 1)
  dialog:AddCheckBox("DrawBorder", reg:GetBool("DrawBorder", false))
  dialog:AddCheckBox("DimOverall", reg:GetBool("DimOverall", true))
  dialog:AddCheckBox("DimEach", reg:GetBool("DimEach", false))
  dialog:AddCheckBox("ShowScale", reg:GetBool("ShowScale", true))
  dialog:AddTextField("Title", reg:GetString("Title", ""))
  dialog:AddTextField("Note", "")

  if not dialog:ShowDialog() then return false end

  local line_mm     = dialog:GetDoubleField("LineWidth")
  local margin_mm   = dialog:GetDoubleField("Margin")
  local font_mm     = dialog:GetDoubleField("FontSize")
  local scale_mode  = dialog:GetRadioIndex("ScaleMode")      -- 1 = A4, 2 = 1:1
  local selected_only = dialog:GetRadioIndex("Source") == 1
  local draw_border = dialog:GetCheckBox("DrawBorder")
  local dim_overall = dialog:GetCheckBox("DimOverall")
  local dim_each    = dialog:GetCheckBox("DimEach")
  local show_scale  = dialog:GetCheckBox("ShowScale")
  local title       = dialog:GetTextField("Title") or ""
  local note        = dialog:GetTextField("Note") or ""

  reg:SetDouble("LineWidth", line_mm)
  reg:SetDouble("Margin", margin_mm)
  reg:SetDouble("FontSize", font_mm)
  reg:SetInt("ScaleMode", scale_mode)
  reg:SetBool("DrawBorder", draw_border)
  reg:SetBool("DimOverall", dim_overall)
  reg:SetBool("DimEach", dim_each)
  reg:SetBool("ShowScale", show_scale)
  reg:SetString("Title", title)

  if line_mm <= 0 or font_mm <= 0 then
    DisplayMessageBox("Linienstaerke und Schriftgroesse muessen groesser als 0 sein.")
    return false
  end
  if selected_only and job.Selection.IsEmpty then
    DisplayMessageBox("Es sind keine Vektoren ausgewaehlt.")
    return false
  end

  local in_mm   = job.InMM
  local unit_pt = in_mm and MM or 72
  local seg_len = in_mm and 0.2 or 0.008
  local function fmt(v)
    if in_mm then
      local s = string.format("%.1f", v):gsub("%.0$", "")
      return s:gsub("%.", ",")
    end
    return string.format('%.3f"', v)
  end

  -- Konturen
  skipped = 0
  local contours = CollectContours(job, selected_only)
  if #contours == 0 then
    DisplayMessageBox("Keine Vektoren gefunden.")
    return false
  end
  local paths = {}
  local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
  for _, c in ipairs(contours) do
    local p = ContourToPath(c, seg_len)
    paths[#paths + 1] = p
    minx = math.min(minx, p.minx); miny = math.min(miny, p.miny)
    maxx = math.max(maxx, p.maxx); maxy = math.max(maxy, p.maxy)
  end
  local vminx, vminy, vmaxx, vmaxy = minx, miny, maxx, maxy   -- nur Vektoren

  local border = nil
  if draw_border then
    local box = job.MaterialBlock.MaterialBox
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
    if w > h then page_w, page_h = page_h, page_w end
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
  local s = { f(line_mm * MM) .. " w 1 J 1 j 0 G 0 g" }
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
  local d = Draw.new(fs, 0.25 * MM)
  d:add("q " .. f(0.25 * MM) .. " w 0 G 0 g")
  local near = 5 * MM          -- Abstand Einzelmasse
  local far  = near + 2 * fs + 3 * MM  -- Abstand Gesamtmasse
  if dim_overall then
    d:hdim(tx(vminx), tx(vmaxx), ty(vminy), ty(vminy) - far, fmt(vmaxx - vminx))
    d:vdim(ty(vminy), ty(vmaxy), tx(vminx), tx(vminx) - far, fmt(vmaxy - vminy))
  end
  if dim_each then
    local tol = in_mm and 0.05 or 0.002
    for _, p in ipairs(paths) do
      local pw, ph = p.maxx - p.minx, p.maxy - p.miny
      local is_total = math.abs(p.minx - vminx) < tol and math.abs(p.maxx - vmaxx) < tol and
                       math.abs(p.miny - vminy) < tol and math.abs(p.maxy - vmaxy) < tol
      if p.closed and pw > tol and ph > tol and not (is_total and dim_overall) then
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

  -- 3) Titel, Notiz, Massstab
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
    local unit = in_mm and "mm" or "Zoll"
    d:text(margin, margin, "Ma\195\159stab " .. r .. "   \194\183   Ma\195\159e in " .. unit ..
           "   \194\183   " .. os.date("%d.%m.%Y"), fs * 0.8, false, "left")
  end
  d:add("Q")

  local stream = table.concat(s, "\n") .. "\n" .. table.concat(d.s, "\n")

  -- Speichern
  local fd = FileDialog()
  if not fd:FileSave("pdf", "Zeichnung.pdf", "PDF Dateien (*.pdf)|*.pdf|") then
    return false
  end
  local ok, err = WritePdf(fd.PathName, page_w, page_h, stream)
  if not ok then
    DisplayMessageBox("PDF konnte nicht geschrieben werden:\n" .. tostring(err))
    return false
  end

  local msg = "PDF gespeichert:\n" .. fd.PathName ..
              "\n\n" .. #paths .. " Vektoren, Linienstaerke " .. line_mm .. " mm"
  if skipped > 0 then
    msg = msg .. "\n\n" .. skipped .. " Objekt(e) ohne Vektorform (Vectric-Text/-Bemassung)" ..
          " wurden uebersprungen - Masse erzeugt das Gadget selbst."
  end
  DisplayMessageBox(msg)
  return true
end
