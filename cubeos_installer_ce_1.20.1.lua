-- ============================================================
--  CubeOS — самораспаковывающийся установщик для OpenOS
--  Запуск (из OpenOS):   lua cubeos_installer.lua
--  Поддерживает:
--    • OpenComputers Community Edition (Minecraft 1.20.1 Forge)
--    • OpenComputers Classic (Minecraft 1.7.10 / 1.12.2)
--  Файлов: 36. Нужен диск ≥ 300 КБ и экран/видеокарта Tier 3.
-- ============================================================
local component = require("component")
local computer = require("computer")

local FILES = {
  {"/init.lua", [[
-- ============================================================
--  CubeOS  —  загрузчик  (/init.lua)
--  Стандартный BIOS OpenComputers находит этот файл на диске
--  и запускает его. Здесь нет OpenOS: ядро, require, файловая
--  система, графика и рабочий стол — всё написано с нуля.
-- ============================================================
local component, computer, unicode = component, computer, unicode

local bootAddress = computer.getBootAddress()
local boot = component.proxy(bootAddress)

local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()
if not gpuAddress then error("CubeOS: нет видеокарты") end
if not screenAddress then error("CubeOS: нет монитора") end

local gpu = component.proxy(gpuAddress)
gpu.bind(screenAddress)

local maxW, maxH = gpu.maxResolution()
-- OpenComputers Classic Tier 3 — 160×50; Community Edition 1.20.1 Tier 4 — 190×60.
-- Берём максимум, который даёт монитор, но не больше 190×60.
local W, H = math.min(maxW, 190), math.min(maxH, 60)
-- На малом объёме ОЗУ берём разрешение поменьше (буфер экрана занимает память)
if computer.totalMemory() < 1300 * 1024 then
  W, H = math.min(maxW, 100), math.min(maxH, 32)
end
gpu.setResolution(W, H)
pcall(gpu.setDepth, gpu.maxDepth())

-- ------------------------------------------------------------
--  Заставка
-- ------------------------------------------------------------
local BG = 0x0B1020

local function fill(x, y, w, h, color)
  if w < 1 or h < 1 then return end
  gpu.setBackground(color)
  gpu.fill(x, y, w, h, " ")
end

local function center(y, text, fg, bg)
  gpu.setForeground(fg)
  gpu.setBackground(bg)
  gpu.set(math.floor((W - unicode.len(text)) / 2) + 1, y, text)
end

local function splash(progress, status)
  local cx, cy = math.floor(W / 2), math.floor(H / 2) - 4
  if progress == 0 then
    fill(1, 1, W, H, BG)
    fill(cx - 7, cy - 3, 14, 2, 0x86EFAC) -- верхняя грань куба
    fill(cx - 7, cy - 1, 7, 5, 0x22C55E)  -- левая грань
    fill(cx, cy - 1, 7, 5, 0x15803D)      -- правая грань
    center(cy + 6, "C U B E   O S", 0xE2E8F0, BG)
  end
  local bw = 32
  local bx = math.floor((W - bw) / 2) + 1
  local by = cy + 9
  fill(bx, by, bw, 1, 0x1E293B)
  fill(bx, by, math.floor(bw * progress), 1, 0x22C55E)
  fill(1, by + 2, W, 1, BG)
  center(by + 2, status or "", 0x64748B, BG)
end

-- ------------------------------------------------------------
--  Чтение файлов и собственный require
-- ------------------------------------------------------------
local function readFile(path)
  local handle = boot.open(path, "r")
  if not handle then return nil end
  local parts = {}
  repeat
    local chunk = boot.read(handle, math.huge)
    parts[#parts + 1] = chunk
  until not chunk
  boot.close(handle)
  return table.concat(parts)
end

local loaded = {component = component, computer = computer, unicode = unicode}
package = {loaded = loaded}

function require(name)
  local mod = loaded[name]
  if mod ~= nil then return mod end
  for _, dir in ipairs({"/Libraries/", "/System/"}) do
    local path = dir .. name .. ".lua"
    local code = readFile(path)
    if code then
      local fn, err = load(code, "=" .. path, "t")
      if not fn then error("Синтаксическая ошибка в " .. path .. ":\n" .. tostring(err), 2) end
      loaded[name] = true -- защита от циклических зависимостей
      local result = fn(name)
      if result ~= nil then loaded[name] = result end
      return loaded[name]
    end
  end
  error("Модуль не найден: " .. tostring(name), 2)
end

-- ------------------------------------------------------------
--  Экран критической ошибки
-- ------------------------------------------------------------
local function crash(err)
  gpu.setBackground(0x1D4ED8)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")
  gpu.set(3, 2, "CubeOS: критическая ошибка системы")
  gpu.setForeground(0xBFDBFE)
  local y = 4
  for line in (tostring(err):gsub("\t", "  ") .. "\n"):gmatch("(.-)\n") do
    if y > H - 3 then break end
    gpu.set(3, y, unicode.sub(line, 1, W - 4))
    y = y + 1
  end
  gpu.setForeground(0xFFFFFF)
  gpu.set(3, H - 1, "Нажмите любую клавишу для перезагрузки...")
  repeat
    local signal = computer.pullSignal()
  until signal == "key_down"
  computer.shutdown(true)
end

-- ------------------------------------------------------------
--  Запуск
-- ------------------------------------------------------------
splash(0, "Загрузка ядра...")

local order = {"System", "Screen", "GUI", "JSON", "HTTP", "Desktop"}

local ok, err = xpcall(function()
  for i, name in ipairs(order) do
    splash(i / (#order + 1), "Загрузка модуля: " .. name)
    require(name)
  end
  splash(1, "Запуск рабочего стола...")
  computer.pullSignal(0.3)
  require("Desktop").run()
end, function(e)
  if debug and debug.traceback then return debug.traceback(tostring(e), 2) end
  return tostring(e)
end)

crash(ok and "Рабочий стол завершил работу" or err)
]]},
  {"/Applications/Calculator.app/Info.lua", [[
return {
  title = "Калькулятор", short = "Калькул.", order = 4,
  icon = {
    "dddddddd",
    "dccccccd",
    "dddddddd",
    "dldldlod",
    "dddddddd",
    "dldldlod",
    "dddddddd",
    "dddddddd",
  },
}
]]},
  {"/Applications/Calculator.app/Main.lua", [[
-- Калькулятор
local ctx = ...
local GUI = require("GUI")

local win = ctx.window(31, 21, "Калькулятор")
local c = win.content

c:add(GUI.panel(2, 2, 29, 3, "input"))
local exprLabel = c:add(GUI.label(3, 2, "", "dim", "input", 27, "right"))
local display = c:add(GUI.label(3, 3, "0 ", "text", "input", 27, "right"))

local cur, acc, op, fresh = "0", nil, nil, true

local function fmt(n)
  if n ~= n or n == math.huge or n == -math.huge then return "Ошибка" end
  if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
  return string.format("%.10g", n)
end

local function compute(a, b, o)
  if o == "+" then return a + b
  elseif o == "−" then return a - b
  elseif o == "×" then return a * b
  elseif o == "÷" then
    if b == 0 then return nil end
    return a / b
  end
  return b
end

local function refresh()
  display:setText(cur .. " ")
  exprLabel:setText(acc and op and (fmt(acc) .. " " .. op) or "")
end

local function press(k)
  if cur == "Ошибка" and k ~= "C" then cur, acc, op, fresh = "0", nil, nil, true end
  if k:match("^%d$") then
    if fresh or cur == "0" then cur = k else cur = cur .. k end
    fresh = false
  elseif k == "." then
    if fresh then cur, fresh = "0.", false
    elseif not cur:find(".", 1, true) then cur = cur .. "." end
  elseif k == "C" then
    cur, acc, op, fresh = "0", nil, nil, true
  elseif k == "±" then
    local n = tonumber(cur)
    if n then cur = fmt(-n) end
  elseif k == "%" then
    local n = tonumber(cur)
    if n then cur = fmt(n / 100) fresh = true end
  elseif k == "⌫" then
    if not fresh then
      cur = cur:sub(1, -2)
      if cur == "" or cur == "-" then cur = "0" end
    end
  elseif k == "=" or k == "+" or k == "−" or k == "×" or k == "÷" then
    local n = tonumber(cur)
    if n then
      if acc and op and not fresh then
        local r = compute(acc, n, op)
        if r == nil then cur, acc, op, fresh = "Ошибка", nil, nil, true refresh() return end
        acc = r
        cur = fmt(r)
      elseif not acc or fresh and k ~= "=" and not op then
        acc = n
      end
      if k == "=" then
        op, acc, fresh = nil, nil, true
      else
        op, fresh = k, true
        acc = tonumber(cur) or acc
      end
    end
  end
  refresh()
end

local layout = {
  {"C", "±", "%", "÷"},
  {"7", "8", "9", "×"},
  {"4", "5", "6", "−"},
  {"1", "2", "3", "+"},
  {"0", ".", "⌫", "="},
}
for r, row in ipairs(layout) do
  for col, key in ipairs(row) do
    local style
    if key == "=" then style = "primary"
    elseif key:match("[÷×−+]") then style = "primary" end
    local b = GUI.button(3 + (col - 1) * 7, 6 + (r - 1) * 3, 6, 2, key, function() press(key) end, style)
    if not style and not key:match("%d") then b.color = "panel" end
    c:add(b)
  end
end

win.onKey = function(_, e)
  local ch = (e.char and e.char > 31 and e.char < 128) and string.char(e.char) or ""
  if ch:match("%d") then press(ch)
  elseif ch == "." or ch == "," then press(".")
  elseif ch == "+" then press("+")
  elseif ch == "-" then press("−")
  elseif ch == "*" then press("×")
  elseif ch == "/" then press("÷")
  elseif ch == "=" or e.code == 28 or e.code == 156 then press("=")
  elseif e.code == 14 then press("⌫")
  elseif ch == "c" or ch == "C" then press("C")
  else return false end
  return true
end

refresh()
]]},
  {"/Applications/Editor.app/Info.lua", [[
return {
  title = "Редактор", short = "Редактор", order = 2,
  icon = {
    ".wwwwww.",
    ".wbbbbw.",
    ".wwwwww.",
    ".wkkkkw.",
    ".wwwwww.",
    ".wkkkwl.",
    ".wwwwww.",
    ".wwwwww.",
  },
}
]]},
  {"/Applications/Editor.app/Main.lua", [[
-- Текстовый редактор с подсветкой Lua
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local win = ctx.window(88, 30, "Редактор")
win.resizable, win.minW, win.minH = true, 40, 10
local content = win.content

local COL = {comment = 0x6A737D, string = 0x98C379, number = 0xD19A66, keyword = 0xFF79C6, func = 0x61AFEF}
local KEYWORDS = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do
  KEYWORDS[w] = true
end

local function tokenize(line)
  local segs, i, n = {}, 1, #line
  local function push(t, c) segs[#segs + 1] = {t, c} end
  while i <= n do
    local ch = line:sub(i, i)
    if line:sub(i, i + 1) == "--" then
      push(line:sub(i), COL.comment)
      break
    elseif ch == '"' or ch == "'" then
      local j = i + 1
      while j <= n do
        local d = line:sub(j, j)
        if d == "\\" then j = j + 2 elseif d == ch then break else j = j + 1 end
      end
      push(line:sub(i, j), COL.string)
      i = j + 1
    elseif ch:match("%d") then
      local s = line:match("^%d[%w%.]*", i)
      push(s, COL.number)
      i = i + #s
    elseif ch:match("[%a_]") then
      local s = line:match("^[%w_]+", i)
      local col = C.text
      if KEYWORDS[s] then col = COL.keyword elseif line:sub(i + #s, i + #s) == "(" then col = COL.func end
      push(s, col)
      i = i + #s
    else
      local s = line:match("^[^%w_\"'%-]+", i) or ch
      push(s, C.text)
      i = i + #s
    end
  end
  return segs
end

-- ------------------------------------------------------------ виджет редактора
local Editor = GUI.class()
local ed = GUI.new(Editor, 1, 1, win.w, win.h - 2)
ed.focusable = true
ed.lines, ed.cx, ed.cy, ed.sx, ed.sy = {""}, 0, 1, 0, 0
ed.modified, ed.lua = false, true
content:add(ed)
content.focused = ed

local function gutterWidth(self) return #tostring(#self.lines) + 2 end

local function updateTitle()
  local name = ed.path and System.basename(ed.path) or "Без имени"
  win.title = "Редактор — " .. name .. (ed.modified and " •" or "")
end

function Editor:changed()
  self.modified = true
  updateTitle()
end

function Editor:clamp()
  local len = unicode.len(self.lines[self.cy])
  if self.cx > len then self.cx = len end
end

function Editor:drawSelf(ax, ay)
  local g = gutterWidth(self)
  local textW = self.w - g
  if self.cy < self.sy + 1 then self.sy = self.cy - 1 end
  if self.cy > self.sy + self.h then self.sy = self.cy - self.h end
  if self.cx < self.sx then self.sx = self.cx end
  if self.cx > self.sx + textW - 2 then self.sx = self.cx - textW + 2 end
  local curBg = Screen.blend(C.text, C.input, 0.07)
  for row = 1, self.h do
    local idx = self.sy + row
    local y = ay + row - 1
    local line = self.lines[idx]
    local bg = (idx == self.cy) and curBg or C.input
    Screen.rect(ax, y, g, 1, C.winAlt, nil, " ")
    Screen.rect(ax + g, y, textW, 1, bg, nil, " ")
    if line then
      local num = tostring(idx)
      Screen.text(ax + g - 1 - #num - 1 + 1, y, idx == self.cy and C.text or C.dim, num .. " ", C.winAlt)
      if self.lua then
        local off = 0
        for _, seg in ipairs(tokenize(line)) do
          local len = unicode.len(seg[1])
          local from, to = max(off, self.sx), min(off + len, self.sx + textW)
          if to > from then
            Screen.text(ax + g + (from - self.sx), y, seg[2], unicode.sub(seg[1], from - off + 1, to - off), bg)
          end
          off = off + len
        end
      else
        Screen.text(ax + g, y, C.text, unicode.sub(line, self.sx + 1, self.sx + textW), bg)
      end
    end
  end
  if self:isFocused() then
    local ch = unicode.sub(self.lines[self.cy], self.cx + 1, self.cx + 1)
    if ch == "" then ch = " " end
    Screen.text(ax + g + self.cx - self.sx, ay + self.cy - self.sy - 1, C.input, ch, C.accent)
  end
end

function Editor:onEvent(e, ax, ay)
  if e.type == "touch" then
    self:focus()
    local g = gutterWidth(self)
    self.cy = max(1, min(#self.lines, self.sy + (e.y - ay) + 1))
    self.cx = max(0, min(unicode.len(self.lines[self.cy]), self.sx + (e.x - ax - g)))
    return true
  elseif e.type == "scroll" then
    self.sy = max(0, min(max(0, #self.lines - self.h), self.sy - e.dir * 3))
    return true
  end
  return false
end

function Editor:insertText(s)
  s = s:gsub("\r", ""):gsub("\t", "  ")
  local parts = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = line end
  local cur = self.lines[self.cy]
  local before, after = unicode.sub(cur, 1, self.cx), unicode.sub(cur, self.cx + 1)
  if #parts == 1 then
    self.lines[self.cy] = before .. parts[1] .. after
    self.cx = self.cx + unicode.len(parts[1])
  else
    self.lines[self.cy] = before .. parts[1]
    for i = 2, #parts - 1 do table.insert(self.lines, self.cy + i - 1, parts[i]) end
    table.insert(self.lines, self.cy + #parts - 1, parts[#parts] .. after)
    self.cy = self.cy + #parts - 1
    self.cx = unicode.len(parts[#parts])
  end
  self:changed()
end

function Editor:onPaste(text)
  self:insertText(text)
  return true
end

local function text() return table.concat(ed.lines, "\n") end

-- ------------------------------------------------------------ файловые операции
local function loadFile(path)
  local data, err = System.readFile(path)
  if not data then GUI.alert("Ошибка", tostring(err)) return false end
  data = data:gsub("\r", ""):gsub("\t", "  ")
  ed.lines = {}
  for line in (data .. "\n"):gmatch("(.-)\n") do ed.lines[#ed.lines + 1] = line end
  if #ed.lines > 1 and ed.lines[#ed.lines] == "" then ed.lines[#ed.lines] = nil end
  ed.cx, ed.cy, ed.sx, ed.sy = 0, 1, 0, 0
  ed.path = path
  ed.lua = System.extension(path) == "lua" or System.extension(path) == "cfg"
  ed.modified = false
  updateTitle()
  return true
end

local function saveAs()
  local default = ed.path or "/Users/Documents/untitled.txt"
  local path = GUI.prompt("Сохранить как", "Полный путь к файлу:", default)
  if not path or path == "" then return false end
  path = System.normalize(path)
  local ok, err = System.writeFile(path, text() .. "\n")
  if not ok then GUI.alert("Ошибка сохранения", tostring(err)) return false end
  ed.path = path
  ed.lua = System.extension(path) == "lua"
  ed.modified = false
  updateTitle()
  Desktop.notify("Сохранено: " .. System.basename(path))
  return true
end

local function save()
  if not ed.path then return saveAs() end
  local ok, err = System.writeFile(ed.path, text() .. "\n")
  if not ok then GUI.alert("Ошибка сохранения", tostring(err)) return false end
  ed.modified = false
  updateTitle()
  Desktop.notify("Сохранено: " .. System.basename(ed.path))
  return true
end

local function confirmDiscard()
  if not ed.modified then return true end
  return GUI.confirm("Несохранённые изменения", "Отбросить изменения в текущем файле?", "Отбросить", "Отмена", true)
end

local function newFile()
  if not confirmDiscard() then return end
  ed.lines, ed.cx, ed.cy, ed.sx, ed.sy = {""}, 0, 1, 0, 0
  ed.path, ed.modified, ed.lua = nil, false, true
  updateTitle()
end

local function openDialog()
  if not confirmDiscard() then return end
  local path = GUI.prompt("Открыть файл", "Полный путь к файлу:", ed.path or "/Users/Documents/")
  if path and path ~= "" then
    path = System.normalize(path)
    if System.isDir(path) then GUI.alert("Ошибка", "Это папка, а не файл.") else loadFile(path) end
  end
end

local function run()
  local ok, out = System.runLua(text(), ed.path or "editor", {Desktop = Desktop, GUI = GUI, System = System})
  Desktop.showText(ok and "Выполнено" or "Ошибка выполнения", out ~= "" and out or "(скрипт ничего не вывел)")
end

function Editor:onKey(e)
  local code, ch = e.code, e.char
  if e.ctrl then
    if code == 31 then save()
    elseif code == 24 then openDialog()
    elseif code == 49 then newFile()
    else return false end
    return true
  end
  local len = unicode.len(self.lines[self.cy])
  if code == 200 then
    if self.cy > 1 then self.cy = self.cy - 1 self:clamp() end
  elseif code == 208 then
    if self.cy < #self.lines then self.cy = self.cy + 1 self:clamp() end
  elseif code == 203 then
    if self.cx > 0 then self.cx = self.cx - 1
    elseif self.cy > 1 then self.cy = self.cy - 1 self.cx = unicode.len(self.lines[self.cy]) end
  elseif code == 205 then
    if self.cx < len then self.cx = self.cx + 1
    elseif self.cy < #self.lines then self.cy = self.cy + 1 self.cx = 0 end
  elseif code == 199 then self.cx = 0
  elseif code == 207 then self.cx = len
  elseif code == 201 then self.cy = max(1, self.cy - self.h) self:clamp()
  elseif code == 209 then self.cy = min(#self.lines, self.cy + self.h) self:clamp()
  elseif code == 28 or code == 156 then
    local cur = self.lines[self.cy]
    local indent = cur:match("^%s*") or ""
    local trimmed = unicode.sub(cur, 1, self.cx):match("^(.-)%s*$")
    if trimmed:match("then$") or trimmed:match("do$") or trimmed:match("else$") or trimmed:match("function%s*%b()$") or trimmed:match("{$") then
      indent = indent .. "  "
    end
    self:insertText("\n" .. indent)
  elseif code == 14 then
    if self.cx > 0 then
      local cur = self.lines[self.cy]
      self.lines[self.cy] = unicode.sub(cur, 1, self.cx - 1) .. unicode.sub(cur, self.cx + 1)
      self.cx = self.cx - 1
      self:changed()
    elseif self.cy > 1 then
      local prevLen = unicode.len(self.lines[self.cy - 1])
      self.lines[self.cy - 1] = self.lines[self.cy - 1] .. self.lines[self.cy]
      table.remove(self.lines, self.cy)
      self.cy, self.cx = self.cy - 1, prevLen
      self:changed()
    end
  elseif code == 211 then
    local cur = self.lines[self.cy]
    if self.cx < len then
      self.lines[self.cy] = unicode.sub(cur, 1, self.cx) .. unicode.sub(cur, self.cx + 2)
      self:changed()
    elseif self.cy < #self.lines then
      self.lines[self.cy] = cur .. self.lines[self.cy + 1]
      table.remove(self.lines, self.cy + 1)
      self:changed()
    end
  elseif code == 15 then self:insertText("  ")
  elseif code == 63 then run()
  elseif ch and ch >= 32 and ch ~= 127 then self:insertText(unicode.char(ch))
  else return false end
  return true
end

-- ------------------------------------------------------------ строка состояния
local Status = GUI.class()
local status = GUI.new(Status, 1, win.h - 1, win.w, 1)
function Status:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, 1, C.title, nil, " ")
  local info = string.format(" Стр %d, стб %d   │   %s   │   строк: %d", ed.cy, ed.cx + 1, ed.lua and "Lua" or "Текст", #ed.lines)
  Screen.text(ax, ay, C.titleText, info, C.title)
  local right = ed.path and ed.path or "новый файл"
  right = GUI.fit(right, max(10, self.w - unicode.len(info) - 3))
  Screen.text(ax + self.w - unicode.len(right) - 1, ay, C.titleDim, right, C.title)
end
content:add(status)

win.onResize = function(_, w, h)
  ed.w, ed.h = w, h - 1
  status.y, status.w = h, w
end
win:resize(win.w, win.h)

win.onClose = function()
  if ed.modified then
    return GUI.confirm("Закрыть редактор", "Есть несохранённые изменения. Закрыть без сохранения?", "Закрыть", "Отмена", true)
  end
end

win.menu = {
  {title = "Файл", items = function()
    return {
      {text = "Новый", hint = "Ctrl+N", action = newFile},
      {text = "Открыть…", hint = "Ctrl+O", action = openDialog},
      {text = "Сохранить", hint = "Ctrl+S", action = save},
      {text = "Сохранить как…", action = saveAs},
    }
  end},
  {title = "Запуск", items = {
    {text = "Выполнить как Lua", hint = "F5", action = run},
  }},
}

if ctx.args.file then loadFile(ctx.args.file) else updateTitle() end
]]},
  {"/Applications/Finder.app/Info.lua", [[
return {
  title = "Файлы", short = "Файлы", order = 1,
  icon = {
    "........",
    "yyyy....",
    "yyyyyyyy",
    "yooooooy",
    "yooooooy",
    "yooooooy",
    "yooooooy",
    "yyyyyyyy",
  },
}
]]},
  {"/Applications/Finder.app/Main.lua", [[
-- Файловый менеджер
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local max = math.max

local win = ctx.window(80, 26, "Файлы")
win.resizable, win.minW, win.minH = true, 52, 12
local c = win.content

local cwd = "/"
local clipboard

local protected = {["/init.lua"] = true, ["/Libraries"] = true, ["/System"] = true, ["/Applications"] = true, ["/StorePackages"] = true}

local up, home, pathInput, list, status

local function fullPath(name)
  return System.join(cwd, (name:gsub("/$", "")))
end

local function refresh(keepSel)
  local sel = list.selected
  list:setItems(System.list(cwd))
  if not keepSel then
    list.selected = #list.items > 0 and 1 or 0
    list.scroll = 0
  else
    list.selected = math.min(sel, #list.items)
  end
  pathInput:setText(cwd)
  win.title = "Файлы — " .. (cwd == "/" and "/" or System.basename(cwd))
  local fs = System.fs
  status:setText(string.format(" %d объектов   │   занято %s из %s", #list.items, System.formatSize(fs.spaceUsed()), System.formatSize(fs.spaceTotal())))
end

local function go(path)
  path = System.normalize(path)
  if not System.isDir(path) then
    GUI.alert("Ошибка", "Нет такой папки:\n" .. path)
    pathInput:setText(cwd)
    return
  end
  cwd = path
  refresh(false)
end

local function openItem(name)
  local path = fullPath(name)
  if name:sub(-1) == "/" and not name:match("%.app/$") then go(path) else Desktop.openFile(path) end
end

local function isProtected(path)
  return protected[path] == true or path == "/"
end

local function deleteItem(name)
  local path = fullPath(name)
  if isProtected(path) then GUI.alert("Защищено", "Системный объект CubeOS нельзя удалить:\n" .. path) return end
  if GUI.confirm("Удаление", "Удалить «" .. name:gsub("/$", "") .. "» безвозвратно?", "Удалить", "Отмена", true) then
    System.remove(path)
    refresh(true)
  end
end

local function renameItem(name)
  local path = fullPath(name)
  if isProtected(path) then GUI.alert("Защищено", "Системный объект CubeOS нельзя переименовать.") return end
  local new = GUI.prompt("Переименовать", "Новое имя:", (name:gsub("/$", "")))
  if new and new ~= "" and not new:find("/", 1, true) then
    System.rename(path, System.join(cwd, new))
    refresh(true)
  end
end

local function newFile()
  local name = GUI.prompt("Новый файл", "Имя файла:", "новый.txt")
  if name and name ~= "" then
    local ok, err = System.writeFile(System.join(cwd, name), "")
    if not ok then GUI.alert("Ошибка", tostring(err)) end
    refresh(true)
  end
end

local function newFolder()
  local name = GUI.prompt("Новая папка", "Имя папки:", "Новая папка")
  if name and name ~= "" then
    System.mkdirs(System.join(cwd, name))
    refresh(true)
  end
end

local function copyItem(name)
  clipboard = fullPath(name)
  Desktop.notify("Скопировано: " .. System.basename(clipboard))
end

local function paste()
  if not clipboard or not System.exists(clipboard) then return end
  local base = System.basename(clipboard)
  local target = System.join(cwd, base)
  local n = 1
  while System.exists(target) do
    target = System.join(cwd, base .. " копия" .. (n > 1 and (" " .. n) or ""))
    n = n + 1
  end
  local ok, err = System.copy(clipboard, target)
  if not ok then GUI.alert("Ошибка копирования", tostring(err)) end
  refresh(true)
end

local function contextMenu(l, idx, e)
  local name = idx and l.items[idx]
  local items = {}
  if name then
    local isDir = name:sub(-1) == "/"
    items[#items + 1] = {text = "Открыть", action = function() openItem(name) end}
    if not isDir then
      items[#items + 1] = {text = "Открыть в редакторе", action = function() Desktop.launchById("Editor", {file = fullPath(name)}) end}
      if System.extension(name) == "lua" then
        items[#items + 1] = {text = "Выполнить", action = function() Desktop.runScript(fullPath(name)) end}
      end
    end
    items[#items + 1] = {separator = true}
    items[#items + 1] = {text = "Переименовать", action = function() renameItem(name) end}
    items[#items + 1] = {text = "Копировать", action = function() copyItem(name) end}
    items[#items + 1] = {text = "Вставить", disabled = clipboard == nil, action = paste}
    items[#items + 1] = {separator = true}
    items[#items + 1] = {text = "Удалить", action = function() deleteItem(name) end}
  else
    items = {
      {text = "Новый файл", action = newFile},
      {text = "Новая папка", action = newFolder},
      {separator = true},
      {text = "Вставить", disabled = clipboard == nil, action = paste},
    }
  end
  GUI.menu(e.x, e.y, items)
end

-- ------------------------------------------------------------ интерфейс
up = c:add(GUI.button(2, 1, 5, 1, " ↑ ", function() go(System.dirname(cwd)) end))
home = c:add(GUI.button(8, 1, 5, 1, " ⌂ ", function() go("/Users") end))
pathInput = c:add(GUI.input(14, 1, win.w - 14, "/", nil, {onSubmit = function(self, t) go(t) end}))

local function sel() return list.items[list.selected] end
local tools = {
  {"+ Файл", 8, newFile},
  {"+ Папка", 9, newFolder},
  {"Копировать", 12, function() if sel() then copyItem(sel()) end end},
  {"Вставить", 10, paste},
  {"Удалить", 9, function() if sel() then deleteItem(sel()) end end},
}
local tx = 2
for _, t in ipairs(tools) do
  local b = GUI.button(tx, 2, t[2], 1, t[1], t[3], "flat")
  b.color = "panel"
  c:add(b)
  tx = tx + t[2] + 1
end

list = c:add(GUI.list(1, 4, win.w, win.h - 5, {}))
list.striped = true
list.render = function(self, name, idx, x, y, w, selected, bg)
  local isDir = name:sub(-1) == "/"
  local isApp = name:match("%.app/$")
  local ext = System.extension(name)
  local glyph, col = "▫", C.text
  if isApp then glyph, col = "◆", C.accent
  elseif isDir then glyph, col = "▣", C.warning
  elseif ext == "lua" then glyph, col = "◈", 0x61AFEF end
  if selected then col = C.accentText end
  Screen.text(x + 1, y, col, glyph, bg)
  local label = (name:gsub("/$", ""))
  Screen.text(x + 3, y, selected and C.accentText or C.text, GUI.fit(label, w - 20), bg)
  local info = isApp and "Приложение" or isDir and "Папка" or System.formatSize(System.size(fullPath(name)))
  Screen.text(x + w - unicode.len(info) - 1, y, selected and C.accentText or C.dim, info, bg)
end
list.onActivate = function(_, idx) openItem(list.items[idx]) end
list.onContext = contextMenu
c.focused = list

status = c:add(GUI.label(1, win.h - 1, "", "titleText", "title", win.w, nil))

win.onResize = function(_, w, h)
  pathInput.w = w - 14
  list.w, list.h = w, h - 4
  status.y, status.w = h, w
end
win:resize(win.w, win.h)

win.onKey = function(_, e)
  if e.code == 14 then go(System.dirname(cwd)) return true end
  if e.code == 211 and sel() then deleteItem(sel()) return true end
  return false
end

go(ctx.args.path or "/")
]]},
  {"/Applications/Monitor.app/Info.lua", [[
return {
  title = "Монитор системы", short = "Монитор", order = 6,
  icon = {
    "........",
    "......r.",
    "...y..r.",
    "...y..r.",
    ".g.y..r.",
    ".g.y.yr.",
    ".g.ygyr.",
    "dddddddd",
  },
}
]]},
  {"/Applications/Monitor.app/Main.lua", [[
-- Системный монитор
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local computer, component, unicode = computer, component, unicode
local Desktop = ctx.Desktop
local floor = math.floor

local win = ctx.window(66, 24, "Системный монитор")
local c = win.content
win.tickInterval = 1

local function row(y, title)
  c:add(GUI.label(2, y, title, "dim"))
  local bar = c:add(GUI.progress(16, y, 30, 0))
  local val = c:add(GUI.label(48, y, "", "text"))
  return bar, val
end

local ramBar, ramVal = row(2, "ОЗУ")
local energyBar, energyVal = row(4, "Энергия")
local diskBar, diskVal = row(6, "Диск")
local upLabel = c:add(GUI.label(2, 8, "", "dim"))

c:add(GUI.label(2, 10, "Открытые окна", "text"))
local list = c:add(GUI.list(2, 11, 40, 10, {}))
list.striped = true
c:add(GUI.button(44, 11, 20, 1, "Закрыть окно", function()
  local item = list.items[list.selected]
  if item and item.win then item.win:close() end
end, "danger"))

local function refresh()
  local used, total = System.memory()
  ramBar.value = used / total
  ramVal:setText(System.formatSize(used) .. " / " .. System.formatSize(total))
  local e, me = computer.energy(), computer.maxEnergy()
  energyBar.value = (me and me > 0) and e / me or 0
  energyBar.color = energyBar.value < 0.2 and "danger" or "success"
  energyVal:setText(floor(energyBar.value * 100) .. "%")
  local fs = System.fs
  local du, dt = fs.spaceUsed(), fs.spaceTotal()
  diskBar.value = dt > 0 and du / dt or 0
  diskVal:setText(System.formatSize(du) .. " / " .. System.formatSize(dt))
  local w, h = Desktop.screenSize()
  upLabel:setText("Время работы: " .. System.uptimeText() .. "     Экран: " .. w .. "×" .. h .. "     Окон: " .. #Desktop.windows)
  local items = {}
  for _, wnd in ipairs(Desktop.windows) do
    if wnd ~= win then
      items[#items + 1] = {text = (wnd.app and wnd.app.title or "?") .. " — " .. tostring(wnd.title), win = wnd}
    end
  end
  list:setItems(items)
end

c:add(GUI.label(44, 13, "Компоненты", "dim"))
local comps = {}
for addr, t in component.list() do comps[#comps + 1] = t .. "  " .. addr:sub(1, 8) end
table.sort(comps)
c:add(GUI.textView(44, 14, 21, 8, table.concat(comps, "\n")))

win.onTick = function()
  refresh()
  return true
end
refresh()
]]},
  {"/Applications/Settings.app/Info.lua", [[
return {
  title = "Настройки", short = "Настройки", order = 7,
  icon = {
    "...aa...",
    ".a.aa.a.",
    "..aaaa..",
    "aaa..aaa",
    "aaa..aaa",
    "..aaaa..",
    ".a.aa.a.",
    "...aa...",
  },
}
]]},
  {"/Applications/Settings.app/Main.lua", [[
-- Настройки CubeOS
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local Locale = require("Locale")
local computer, component, unicode = computer, component, unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor = math.floor

local win = ctx.window(78, 25, "Настройки")
local c = win.content
local s = System.settings

local sections = {"Оформление", "Экран", "Время", "Система"}
local pane
local current = 1

local function save()
  System.saveSettings()
  Desktop.applyTheme()
end

-- Образец обоев: градиент с подписью
local Swatch = GUI.class()
function Swatch:drawSelf(ax, ay)
  GUI.gradient(ax, ay, self.w, self.h - 1, self.wp.c1, self.wp.c2)
  Screen.rect(ax, ay + self.h - 1, self.w, 1, C.win, nil, " ")
  local on = s.wallpaper == self.index
  Screen.text(ax, ay + self.h - 1, on and C.accent or C.dim, (on and "● " or "○ ") .. self.wp.name, C.win)
end
function Swatch:onEvent(e)
  if e.type == "touch" and e.button == 0 then
    s.wallpaper = self.index
    save()
    return true
  end
  return false
end

local build = {}

build[1] = function()
  pane:add(GUI.label(2, 2, "Тема", "dim"))
  for i, name in ipairs({"dark", "light"}) do
    local b = GUI.button(2 + (i - 1) * 14, 3, 12, 1, i == 1 and "Тёмная" or "Светлая", function()
      s.theme = name
      save()
      build.refresh()
    end)
    b.active = s.theme == name
    pane:add(b)
  end

  pane:add(GUI.label(2, 5, "Акцентный цвет", "dim"))
  for i, a in ipairs(GUI.accents) do
    local b = GUI.button(2 + (i - 1) * 8, 6, 7, 1, s.accent == i and "✓" or "", function()
      s.accent = i
      save()
      build.refresh()
    end)
    b.color, b.textColor = a.color, 0x0B1020
    pane:add(b)
  end

  pane:add(GUI.label(2, 8, "Обои рабочего стола", "dim"))
  for i, wp in ipairs(Desktop.wallpapers) do
    local sw = GUI.new(Swatch, 2 + ((i - 1) % 3) * 17, 9 + floor((i - 1) / 3) * 6, 15, 5)
    sw.wp, sw.index = wp, i
    pane:add(sw)
  end
end

build[2] = function()
  local mw, mh = Desktop.maxResolution()
  local cw, ch = Desktop.screenSize()
  pane:add(GUI.label(2, 2, string.format("Текущее разрешение: %d × %d   (максимум %d × %d)", cw, ch, mw, mh), "text"))
  local options, items = {}, {}
  -- 190×60 — монитор Tier 4 (OpenComputers Community Edition 1.20.1); 160×50 — Tier 3 (Classic)
  for _, r in ipairs({{190, 60}, {160, 50}, {140, 44}, {120, 40}, {100, 32}, {80, 25}, {70, 22}}) do
    if r[1] <= mw and r[2] <= mh then
      options[#options + 1] = r
      items[#items + 1] = string.format("%d × %d%s", r[1], r[2], (r[1] == cw and r[2] == ch) and "   ← сейчас" or "")
    end
  end
  pane:add(GUI.label(2, 4, "Выберите разрешение (двойной клик):", "dim"))
  local list = pane:add(GUI.list(2, 5, 40, 8, items))
  list.onActivate = function(_, idx)
    local r = options[idx]
    if Desktop.setResolution(r[1], r[2]) then
      Desktop.notify(string.format("Разрешение: %d × %d", r[1], r[2]))
    end
    build.refresh()
  end
  pane:add(GUI.label(2, 14, "Меньшее разрешение экономит ОЗУ компьютера.", "dim"))
end

build[3] = function()
  pane:add(GUI.label(2, 2, "Сейчас: " .. System.date("%d.%m.%Y  %H:%M:%S"), "text"))
  pane:add(GUI.label(2, 4, "Часовой пояс (UTC):", "dim"))
  local items = {}
  for tz = -12, 14 do items[#items + 1] = string.format("UTC%+d", tz) end
  local list = pane:add(GUI.list(2, 5, 24, 13, items))
  list.selected = s.timezone + 13
  list:ensureVisible()
  list.onSelect = function(_, idx)
    s.timezone = idx - 13
    System.saveSettings()
    Desktop.dirty = true
  end
  pane:add(GUI.label(30, 5, "Время берётся с компьютера-хоста", "dim"))
  pane:add(GUI.label(30, 6, "через lastModified файловой системы.", "dim"))
end

build[4] = function()
  local used, total = System.memory()
  local fs = System.fs
  local w, h = Desktop.screenSize()
  local mw, mh = Desktop.maxResolution()
  local rows = {
    {"Система", System.name .. " " .. System.version .. " (" .. System.build .. ")"},
    {"Платформа", System.platform or "OpenComputers"},
    {"Minecraft", System.minecraft or "1.20.1"},
    {"Монитор", "Tier " .. tostring(System.screenTier or 3) .. " · макс. " .. mw .. " × " .. mh},
    {"ОЗУ", System.formatSize(used) .. " из " .. System.formatSize(total)},
    {"Диск", System.formatSize(fs.spaceUsed()) .. " из " .. System.formatSize(fs.spaceTotal())},
    {"Экран", w .. " × " .. h},
    {"Internet Card", component.list("internet")() and "установлена" or "не найдена"},
    {"Время работы", System.uptimeText()},
  }
  for i, r in ipairs(rows) do
    pane:add(GUI.label(2, 1 + i, r[1], "dim"))
    pane:add(GUI.label(18, 1 + i, r[2], "text"))
  end
  pane:add(GUI.label(2, 10, "Имя пользователя", "dim"))
  local input = pane:add(GUI.input(2, 11, 30, s.username or "", nil, {onSubmit = function(self, t)
    if t ~= "" then
      s.username = t
      save()
      Desktop.notify("Имя сохранено")
    end
  end}))
  pane:add(GUI.button(34, 11, 12, 1, "Сохранить", function()
    if input.text ~= "" then
      s.username = input.text
      save()
      Desktop.notify("Имя сохранено")
    end
  end, "primary"))
  pane:add(GUI.button(2, 14, 28, 1, "Сбросить настройки", function()
    if GUI.confirm("Сброс настроек", "Вернуть тему, обои и остальные настройки по умолчанию?", "Сбросить", "Отмена", true) then
      System.resetSettings()
      s = System.settings
      Desktop.applyTheme()
      build.refresh()
    end
  end, "danger"))
  pane:add(GUI.label(2, 16, Locale.t("region") .. ": " .. System.regionName(s.region), "text"))
  pane:add(GUI.label(2, 17, Locale.t("language") .. ": " .. System.languageName(s.language), "text"))
  pane:add(GUI.label(2, 18, "Регион выбран при установке; язык можно изменить.", "dim"))
  pane:add(GUI.button(2, 20, 22, 1, "Сменить язык", function()
    local options = {}
    for _, item in ipairs(System.languages) do options[#options + 1] = item.name end
    local index = GUI.select("Язык / Language / 语言", options)
    if index then
      s.language = System.languages[index].id
      save()
      build.refresh()
    end
  end))
end

function build.refresh()
  pane:clear()
  s = System.settings
  build[current]()
end

local sidebar = c:add(GUI.list(1, 1, 20, win.h - 1, sections))
sidebar.bg = "panel"
sidebar.selected = 1
sidebar.onSelect = function(_, idx)
  current = idx
  build.refresh()
end
pane = c:add(GUI.panel(21, 1, win.w - 20, win.h - 1, "win"))
sidebar:focus()
build.refresh()
]]},
  {"/Applications/Snake.app/Info.lua", [[
return {
  title = "Змейка", short = "Змейка", order = 5,
  icon = {
    "kkkkkkkk",
    "kggggkrk",
    "kgkkgkkk",
    "kgkkgggk",
    "kgkkkkgk",
    "kggggggk",
    "kkkkkkkk",
    "kkkkkkkk",
  },
}
]]},
  {"/Applications/Snake.app/Main.lua", [[
-- Змейка
local ctx = ...
local GUI = require("GUI")
local Screen = require("Screen")
local C = GUI.color
local Desktop = ctx.Desktop

local COLS, ROWS = 24, 16
local win = ctx.window(COLS * 2 + 2, ROWS + 4, "Змейка")
local c = win.content
win.tickInterval = 0.13

local snake, dir, nextDir, food, score, over, paused
local best = 0

local scoreLabel = c:add(GUI.label(2, 1, "", "text"))
local hint = c:add(GUI.label(2, ROWS + 3, "Стрелки / WASD — движение, P — пауза, Пробел — заново", "dim"))

local function placeFood()
  while true do
    local x, y = math.random(1, COLS), math.random(1, ROWS)
    local free = true
    for _, s in ipairs(snake) do
      if s.x == x and s.y == y then free = false break end
    end
    if free then food = {x = x, y = y} return end
  end
end

local function reset()
  snake = {{x = 8, y = 8}, {x = 7, y = 8}, {x = 6, y = 8}}
  dir, nextDir = {x = 1, y = 0}, {x = 1, y = 0}
  score, over, paused = 0, false, false
  placeFood()
end

local Board = GUI.class()
local board = GUI.new(Board, 2, 2, COLS * 2, ROWS)
c:add(board)

function Board:drawSelf(ax, ay)
  for y = 1, ROWS do
    for x = 1, COLS do
      local shade = ((x + y) % 2 == 0) and 0x1B2A1F or 0x172419
      Screen.rect(ax + (x - 1) * 2, ay + y - 1, 2, 1, shade, nil, " ")
    end
  end
  Screen.rect(ax + (food.x - 1) * 2, ay + food.y - 1, 2, 1, 0xED4245, nil, " ")
  for i, s in ipairs(snake) do
    Screen.rect(ax + (s.x - 1) * 2, ay + s.y - 1, 2, 1, i == 1 and 0x86EFAC or 0x22C55E, nil, " ")
  end
  if over or paused then
    local msg = over and "  ИГРА ОКОНЧЕНА  " or "     ПАУЗА     "
    Screen.text(ax + math.floor((COLS * 2 - #msg) / 2), ay + math.floor(ROWS / 2), 0xFFFFFF, msg, 0x000000)
  end
end

win.onTick = function()
  scoreLabel:setText(string.format("Счёт: %d     Рекорд: %d", score, best))
  if over or paused or not Desktop.isFocused(win) then return false end
  dir = nextDir
  local head = snake[1]
  local nx, ny = head.x + dir.x, head.y + dir.y
  if nx < 1 or nx > COLS or ny < 1 or ny > ROWS then over = true return true end
  for i = 1, #snake - 1 do
    if snake[i].x == nx and snake[i].y == ny then over = true return true end
  end
  table.insert(snake, 1, {x = nx, y = ny})
  if nx == food.x and ny == food.y then
    score = score + 10
    if score > best then best = score end
    placeFood()
  else
    table.remove(snake)
  end
  return true
end

win.onKey = function(_, e)
  local code, ch = e.code, e.char and e.char > 0 and string.char(e.char % 256):lower() or ""
  local d
  if code == 200 or ch == "w" then d = {x = 0, y = -1}
  elseif code == 208 or ch == "s" then d = {x = 0, y = 1}
  elseif code == 203 or ch == "a" then d = {x = -1, y = 0}
  elseif code == 205 or ch == "d" then d = {x = 1, y = 0}
  elseif ch == "p" then paused = not paused return true
  elseif code == 57 then reset() return true end
  if d then
    if d.x ~= -dir.x or d.y ~= -dir.y then nextDir = d end
    return true
  end
  return false
end

reset()
]]},
  {"/Applications/Store.app/Info.lua", [[
return {
  title = "Магазин", short = "Магазин", order = 0, single = true,
  description = "Игры и приложения на Supabase: вход в аккаунт, шаблоны MineOS и CubeOS, установка в один клик. RYKEA и «Пиксели» тоже лежат здесь.",
  author = "CubeOS",
  icon = {
    "........",
    "..wwww..",
    ".wbbbbw.",
    "wbbbbbbw",
    "wbbbbbbw",
    "wbbbbbbw",
    "wwwwwwww",
    "........",
  },
}
]]},
  {"/Applications/Store.app/Main.lua", [[
-- ============================================================
--  CubeOS :: Магазин — игры и приложения на Supabase
--
--  • Каталог: локальные пакеты (/StorePackages) и облачные игры
--  • Аккаунты: первый зарегистрированный получает роль developer
--  • Разработка: шаблоны MineOS и CubeOS, публикация в базу
--  • Установка: раскладывает файлы в /Applications и обновляет док
--
--  REST: PostgREST проекта lzyiixywduzkioqpuigv.supabase.co.
--  Если таблиц в базе нет — интернет-карта сама переключается на
--  локальный режим (данные живут в браузере), магазин не падает.
-- ============================================================
local ctx = ...
local GUI = require("GUI")
local Screen = require("Screen")
local System = require("System")
local HTTP = require("HTTP")
local JSON = require("JSON")
local Policy = require("RegionPolicy")
local Locale = require("Locale")
local Desktop = ctx.Desktop
local unicode = unicode
local max = math.max

local session = System.loadData("/Users/Store.cfg")
local allowed, policyError = Policy.get("store")
if allowed ~= true and not (session and session.role == "developer") then
  GUI.alert("Региональный доступ", allowed == false and Policy.message("store") or ("Не удалось проверить регион: " .. tostring(policyError)))
  return
end

local CW, CH = 94, 29
local win = ctx.window(CW, CH + 1, "Магазин")
local c = win.content

local BASE = "https://lzyiixywduzkioqpuigv.supabase.co/rest/v1"
local KEY = "sb_publishable_XAMZUny0QRrfYAHURu44lQ_vtdWB_XB"
local HOST = "lzyiixywduzkioqpuigv.supabase.co"
local HEADERS = {
  apikey = KEY,
  ["Authorization"] = "Bearer " .. KEY,
  ["Content-Type"] = "application/json",
}

local PACKAGES = "/StorePackages"
local GAMES_DIR = "/Users/Games"
local SESSION_FILE = "/Users/Store.cfg"
local MANIFEST_FILE = "/Users/Store.lib"

local DEFAULT_ICON = {
  "........", "..pppp..", ".pccccp.", "pccwwccp",
  "pccwwccp", ".pccccp.", "..pppp..", "........",
}
local PALETTE = {
  r = 0xED4245, g = 0x3BA55D, b = 0x4C8DFF, y = 0xFAA61A, w = 0xFFFFFF, k = 0x1E1F22,
  a = 0x949BA4, d = 0x4E5058, o = 0xFF8A3D, p = 0xA78BFA, c = 0x22D3EE, n = 0x8B5E3C,
  l = 0xE3E5E8, t = 0x2DD4BF, m = 0xF472B6, s = 0x5865F2, e = 0x2B2D31, u = 0x1D4ED8,
}

-- ------------------------------------------------------------ состояние
local manifest = System.loadData(MANIFEST_FILE) or {installed = {}}
if type(manifest.installed) ~= "table" then manifest.installed = {} end

local screen = "catalog"
local selected = 1
local selectedInstalled = 1
local status, statusColor = "Загрузка каталога…", "dim"
local statusLabel
local packages, games, extras = {}, {}, {}

-- Системные приложения не показываются в каталоге как товары
local BUILTIN = {Store = true, Finder = true, Editor = true, Terminal = true, Calculator = true, Snake = true, Monitor = true, Settings = true}

local render -- заполняется ниже, используется из колбэков

local function setStatus(text, color)
  status, statusColor = tostring(text), color or "dim"
  if statusLabel then
    statusLabel:setText(text)
    statusLabel.fg = statusColor
  end
end

-- ------------------------------------------------------------ помощники
local function urlenc(s)
  return (tostring(s):gsub("[^%w%.%-_]", function(ch) return string.format("%%%02X", string.byte(ch)) end))
end

local function luaQuote(s)
  s = tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
  return '"' .. s .. '"'
end

local function saveManifest()
  System.writeFile(MANIFEST_FILE, "return " .. System.serialize(manifest))
end

local function saveSession()
  if session then
    System.writeFile(SESSION_FILE, "return " .. System.serialize(session))
  else
    System.remove(SESSION_FILE)
  end
end

local function appPath(id) return "/Applications/" .. id .. ".app" end

local function isInstalled(id)
  local p = manifest.installed[id]
  if p and System.exists(p .. "/Main.lua") then return true end
  -- поставлено с сайта или вручную: /Applications/<id>.app
  if System.exists(appPath(id) .. "/Main.lua") then
    manifest.installed[id] = appPath(id)
    return true
  end
  return false
end

--- GET/POST/DELETE. Возвращает (данные, статус) либо (nil, причина).
local function api(path, method, body)
  local text, code = HTTP.request(BASE .. path, body, HEADERS, method, 20)
  if not text then return nil, code end
  if type(code) == "number" and code >= 400 then return nil, text end
  if text == "" then return {}, code end
  local decoded, err = JSON.decode(text)
  if decoded == nil then return nil, err or "не удалось разобрать ответ" end
  return decoded, code
end

-- ------------------------------------------------------------ иконки
local function parseIconText(text)
  if type(text) ~= "string" or text == "" then return nil end
  local rows = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if #rows < 8 and line ~= "" then rows[#rows + 1] = line:sub(1, 8) end
  end
  if #rows == 0 then return nil end
  while #rows < 8 do rows[#rows + 1] = string.rep(".", 8) end
  return rows
end

local function iconFromFile(path)
  local info = System.loadData(path .. "/Info.lua")
  if type(info) ~= "table" then return nil, nil end
  local src = System.readFile(path .. "/Info.lua") or ""
  local rows = {}
  local icon = info.icon
  if type(icon) == "table" then
    for i = 1, #icon do rows[#rows + 1] = tostring(icon[i]):sub(1, 8) end
  end
  local pal = {}
  for k, v in pairs(PALETTE) do pal[k] = v end
  for key, hex in src:gmatch("(%w)%s*=%s*0x(%x%x%x%x%x%x)") do pal[key] = tonumber(hex, 16) end
  if #rows == 0 then rows = DEFAULT_ICON end
  while #rows < 8 do rows[#rows + 1] = "........" end
  return rows, info, pal
end

-- ------------------------------------------------------------ данные каталога
local function refreshPackages()
  packages = {}
  for _, name in ipairs(System.list(PACKAGES) or {}) do
    local dir = name:gsub("/$", "")
    if dir:match("%.app$") then
      local id = dir:gsub("%.app$", "")
      local rows, info = iconFromFile(PACKAGES .. "/" .. dir)
      if info then
        packages[#packages + 1] = {
          id = id, kind = "package", title = info.title or id,
          author = info.author or "CubeOS", description = info.description or "",
          template = "cubeos", rows = rows, palette = PALETTE,
        }
      end
    end
  end
  table.sort(packages, function(a, b) return a.title < b.title end)
end

--- Приложения, появившиеся в /Applications не через магазин (сайт, вручную)
local function refreshExtras()
  extras = {}
  local known = {}
  for _, p in ipairs(packages) do known[p.id] = true end
  for _, g in ipairs(games) do known[g.id] = true end
  for _, name in ipairs(System.list("/Applications") or {}) do
    local id = (name:gsub("%.app/$", ""))
    local rows, info = iconFromFile(appPath(id))
    if info and not BUILTIN[id] and not known[id] then
      extras[#extras + 1] = {
        id = id, kind = "app", title = info.title or id, author = info.author or "",
        description = info.description or "", template = "cubeos", rows = rows, palette = PALETTE,
      }
    end
  end
  table.sort(extras, function(a, b) return a.title < b.title end)
end

local function refreshGames()
  local rows, err = api("/store_games?select=*&order=created_at.desc")
  if type(rows) ~= "table" then
    setStatus("Supabase: " .. tostring(err):sub(1, 70), "warning")
    return false
  end
  games = {}
  for _, r in ipairs(rows) do
    -- category = "system" — служебные региональные правила (RegionPolicy), не игры
    if r.id and r.category ~= "system" then
      games[#games + 1] = {
        id = tostring(r.id), kind = "cloud",
        title = tostring(r.title or r.id),
        author = tostring(r.author or "—"), description = tostring(r.description or ""),
        category = tostring(r.category or "games"), template = tostring(r.template or "cubeos"),
        code = tostring(r.code or ""), version = tostring(r.version or "1.0"),
        rows = parseIconText(r.icon) or DEFAULT_ICON, palette = PALETTE,
      }
    end
  end
  setStatus(("Supabase: %s · пакетов: %d · игр: %d"):format(HOST, #packages, #games), "dim")
  return true
end

local function catalogItems()
  local out = {}
  for _, p in ipairs(packages) do out[#out + 1] = p end
  for _, g in ipairs(games) do out[#out + 1] = g end
  for _, e in ipairs(extras) do out[#out + 1] = e end
  return out
end

-- ------------------------------------------------------------ установка
local function installItem(it)
  local target = appPath(it.id)
  if it.kind == "package" then
    local ok, err = System.copy(PACKAGES .. "/" .. it.id .. ".app", target)
    if not ok then
      setStatus("Ошибка копирования: " .. tostring(err), "danger")
      return false
    end
  else
    if it.code == "" then
      setStatus("У игры нет кода", "danger")
      return false
    end
    local ok, err = System.installFiles(System.safeAppId(it.id), System.buildAppFiles(it))
    if not ok then
      setStatus("Ошибка установки: " .. tostring(err), "danger")
      return false
    end
  end
  manifest.installed[it.id] = target
  saveManifest()
  Desktop.refreshApps()
  Desktop.notify("Установлено: " .. it.title)
  setStatus("Установлено: " .. it.title, "success")
  return true
end

local function uninstallItem(it)
  local target = manifest.installed[it.id] or appPath(it.id)
  if not System.exists(target) then
    setStatus("Не установлено: " .. it.title, "warning")
    return false
  end
  local ok = System.remove(target)
  if not ok then
    setStatus("Не удалось удалить " .. target, "danger")
    return false
  end
  manifest.installed[it.id] = nil
  saveManifest()
  Desktop.refreshApps()
  setStatus("Удалено: " .. it.title, "warning")
  return true
end

local function runItem(it)
  if not isInstalled(it.id) then
    if not installItem(it) then return end
  end
  Desktop.launchById(it.id)
end

-- ------------------------------------------------------------ виджет иконки
local IconView = GUI.class()
function IconView:drawSelf(ax, ay)
  for j = 1, 8 do
    local row = self.rows and self.rows[j] or ""
    for i = 1, 8 do
      local ch = row:sub(i, i)
      local col = (ch ~= "" and ch ~= ".") and (self.palette[ch] or 0x949BA4) or nil
      if col then Screen.rect(ax + (i - 1) * 2, ay + (j - 1), 2, 1, col, nil, " ") end
    end
  end
end

-- ------------------------------------------------------------ аккаунты
local function doLogin(email, pass)
  local rows, err = api("/store_users?email=eq." .. urlenc(email) .. "&select=*")
  if type(rows) ~= "table" then return nil, tostring(err):sub(1, 70) end
  local u = rows[1]
  if not u or tostring(u.password) ~= tostring(pass) then
    return nil, "Неверный e-mail или пароль"
  end
  return {email = u.email, username = u.username or email, role = u.role or "user"}
end

local function doRegister(email, pass, username)
  local all, err = api("/store_users?select=*")
  if all == nil and err then return nil, tostring(err):sub(1, 70) end
  local isFirst = type(all) == "table" and #all == 0
  local role = isFirst and "developer" or "user"
  local body = JSON.encode({
    id = email, email = email, username = username, password = pass, role = role,
    created_at = System.isoNow(),
  })
  local _, codeResp = api("/store_users", "POST", body)
  if codeResp == nil then return nil, "нет связи с базой" end
  if codeResp == 409 then return doLogin(email, pass) end
  if type(codeResp) == "number" and codeResp >= 400 then
    return nil, tostring(codeResp):sub(1, 70)
  end
  return {email = email, username = username, role = role, fresh = isFirst}
end

local function authModal(mode)
  local isLogin = mode == "login"
  local done = nil
  local m = GUI.modalWindow(isLogin and "Вход в аккаунт" or "Регистрация аккаунта", 58, 17)
  local mc = m.content
  mc:add(GUI.label(3, 2, isLogin and "Введите e-mail и пароль" or "Первый аккаунт станет разработчиком", "dim"))
  mc:add(GUI.label(3, 4, "E-mail", "text"))
  local email = mc:add(GUI.input(3, 5, 50, (session and session.email) or "", "name@mail.ru"))
  mc:add(GUI.label(3, 7, "Пароль", "text"))
  local pass = mc:add(GUI.input(3, 8, 50, "", "минимум 6 символов", {mask = true}))
  local nick
  local errLabel = mc:add(GUI.label(3, 16, "", "danger"))
  local y
  if isLogin then
    y = 12
  else
    mc:add(GUI.label(3, 10, "Никнейм", "text"))
    nick = mc:add(GUI.input(3, 11, 50, "", "Как к вам обращаться"))
    y = 13
  end
  mc:add(GUI.button(3, y, 24, 1, isLogin and "Войти" or "Создать аккаунт", function()
    local mail = (email.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local pwd = pass.text or ""
    if not mail:find("^.+@.+%.%a%a+") then
      errLabel:setText("Некорректный e-mail")
      return
    end
    if isLogin then
      if pwd == "" then errLabel:setText("Введите пароль") return end
      local u, err = doLogin(mail, pwd)
      if not u then errLabel:setText(err or "Ошибка входа") return end
      done = u
    else
      if #pwd < 6 then errLabel:setText("Пароль минимум 6 символов") return end
      local name = (nick.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if name == "" then name = mail:match("^([^@]+)") or mail end
      local u, err = doRegister(mail, pwd, name)
      if not u then errLabel:setText(err or "Ошибка регистрации") return end
      done = u
    end
    m.closed = true
  end, "primary"))
  mc:add(GUI.button(29, y, 14, 1, "Отмена", function() m.closed = true end))
  mc.focused = email

  GUI.runModal(m)
  if done then
    session = done
    saveSession()
    if done.fresh then
      setStatus("Аккаунт создан — вы разработчик " .. done.username, "success")
      Desktop.notify("Роль: разработчик")
    else
      setStatus("Вы вошли: " .. tostring(done.username), "success")
    end
    screen = "catalog"
    render()
  end
end

-- ------------------------------------------------------------ шаблоны игр
local function tplCube(title)
  return ("-- %s\n-- Шаблон CubeOS: нативное окно и виджеты GUI.\nlocal ctx = ...\nlocal GUI = require(\"GUI\")\n\nlocal win = ctx.window(52, 14, %s)\nlocal c = win.content\n\nlocal score = 0\nlocal label = c:add(GUI.label(3, 3, \"Очки: 0\", \"accent\"))\nc:add(GUI.button(3, 5, 22, 1, \"Играть\", function()\n  score = score + 1\n  label:setText(\"Очки: \" .. score)\nend, \"primary\"))\nc:add(GUI.label(3, 7, \"Нажимайте кнопку — счёт растёт\", \"dim\"))\n"):format(title, luaQuote(title))
end

local function tplMine(title)
  return ("-- %s\n-- Шаблон MineOS: цикл событий. Отрабатывает через MineCompat.\nlocal GUI = require(\"GUI\")\nlocal event = require(\"event\")\n\nlocal workspace = GUI.workspace()\nlocal label = GUI.label(2, 3, \"Очки: 0\")\nworkspace:addChild(label)\n\nlocal score = 0\nlocal button = GUI.button(2, 5, 16, 1, \"+1 очко\")\nbutton.onTouch = function()\n  score = score + 1\n  label.text = \"Очки: \" .. score\n  workspace:draw()\nend\nworkspace:addChild(button)\nworkspace:draw()\n\nwhile true do\n  local name, addr, a, b = event.pull()\n  if name == \"key_down\" and b == 1 then break end   -- Escape выходит\n  workspace:event(name, addr, a, b)\nend\n"):format(title)
end

-- ------------------------------------------------------------ действия разработчика
local function newGameDialog()
  local tpl = GUI.select("Шаблон игры", {
    "MineOS — цикл event.pull (совместимость)",
    "CubeOS — нативные окна и виджеты GUI",
  })
  if not tpl then return end
  local isMine = tpl == 1
  local title = GUI.prompt("Новая игра", "Название игры:", isMine and "Игра под MineOS" or "Игра под CubeOS")
  if not title or title == "" then return end
  local desc = GUI.prompt("Новая игра", "Описание для карточки:", "Игра для CubeOS") or ""
  System.mkdirs(GAMES_DIR)
  local base = title:gsub("%s+", "_"):gsub("[^%w%-_\128-\255]", "")
  if base == "" then base = "game" end
  local path = GAMES_DIR .. "/" .. base .. ".lua"
  System.writeFile(path, isMine and tplMine(title) or tplCube(title))
  setStatus("Шаблон создан: " .. path, "success")
  Desktop.launchById("Editor", {file = path})
  render()
end

local function publishDialog()
  if not session then
    authModal("login")
    if not session then return end
  end
  local names = {}
  for _, n in ipairs(System.list(GAMES_DIR) or {}) do
    local file = n:gsub("/$", "")
    if file:match("%.lua$") then names[#names + 1] = file end
  end
  table.sort(names)
  if #names == 0 then
    GUI.alert("Публикация", "В " .. GAMES_DIR .. " нет файлов. Сначала создайте игру по шаблону.")
    return
  end
  local idx = GUI.select("Опубликовать файл из " .. GAMES_DIR, names)
  if not idx then return end
  local path = GAMES_DIR .. "/" .. names[idx]
  local code = System.readFile(path)
  if not code then
    GUI.alert("Ошибка", "Не удалось прочитать " .. path)
    return
  end
  local defTitle = (names[idx]:gsub("%.lua$", "")):gsub("_", " ")
  local title = GUI.prompt("Публикация", "Название в магазине:", defTitle)
  if not title or title == "" then return end
  local desc = GUI.prompt("Публикация", "Описание:", "Игра для CubeOS") or ""
  local guessMine = code:find("event.pull", 1, true) ~= nil or code:find('require("event")', 1, true) ~= nil
  local tpl = GUI.select("Шаблон (должен совпадать с кодом)", {
    (guessMine and "> " or "  ") .. "MineOS — цикл event.pull",
    (guessMine and "  " or "> ") .. "CubeOS — нативные окна",
  })
  if not tpl then return end
  local isMine = tpl == 1
  local id = "g" .. System.date("%y%m%d%H%M%S") .. tostring(math.random(10, 99))
  local body = JSON.encode({
    id = id, title = title, author = session.username or session.email,
    description = desc, category = "games",
    template = isMine and "mineos" or "cubeos",
    code = code, icon = "", version = "1.0", created_at = System.isoNow(),
  })
  local _, res = api("/store_games", "POST", body)
  if type(res) == "number" and res >= 200 and res < 300 then
    refreshGames()
    setStatus("Опубликовано: " .. title, "success")
  else
    setStatus("Ошибка публикации: " .. tostring(res):sub(1, 60), "danger")
    GUI.alert("Публикация не удалась", tostring(res))
  end
end

local function mineDialog()
  if not session then
    authModal("login")
    if not session then return end
  end
  local rows, err = api("/store_games?author=eq." .. urlenc(session.username) .. "&select=*")
  if type(rows) ~= "table" then
    GUI.alert("Мои публикации", "Не удалось загрузить: " .. tostring(err))
    return
  end
  local list, map = {}, {}
  for _, r in ipairs(rows) do
    if r.id then
      list[#list + 1] = tostring(r.title or r.id)
      map[#list] = tostring(r.id)
    end
  end
  if #list == 0 then
    GUI.alert("Мои публикации", "Вы ещё ничего не публиковали. Создайте игру и нажмите «Опубликовать файл…».")
    return
  end
  local idx = GUI.select("Мои публикации", list)
  if not idx then return end
  if not GUI.confirm("Снять с публикации", "Удалить «" .. list[idx] .. "» из магазина?", "Удалить", "Отмена", true) then
    return
  end
  local _, res = api("/store_games?id=eq." .. urlenc(map[idx]), "DELETE", "")
  if type(res) == "number" and res < 400 then
    refreshGames()
    setStatus("Снято с публикации: " .. list[idx], "warning")
  else
    setStatus("Ошибка: " .. tostring(res):sub(1, 60), "danger")
  end
end

-- ------------------------------------------------------------ региональный доступ (вкладка «Регионы»)
-- Всё состояние вкладки — локальные переменные модуля: ни одна функция ниже
-- не обращается к необъявленным глобальным именам (их проверяет scripts/globalsCheck.cjs).
local regionRules, regionError, regionSel = {}, nil, 1

local function padRight(text, width)
  text = tostring(text)
  local len = unicode.len(text)
  if len >= width then return unicode.sub(text, 1, width) end
  return text .. string.rep(" ", width - len)
end

--- Загрузить правила из облака (служебные строки store_games, см. RegionPolicy). Возвращает true либо false (текст ошибки — в regionError).
local function loadRegionRules()
  local rows, err = Policy.list()
  if type(rows) ~= "table" then
    regionError = tostring(err or "нет ответа от базы")
    return false
  end
  regionError = nil
  regionRules = {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and row.id then regionRules[tostring(row.id)] = row.enabled ~= false end
  end
  return true
end

local function regionEnabled(service, regionId)
  return regionRules[service .. "_" .. regionId] ~= false
end

local function serviceName(service)
  return service == "store" and "Магазин" or "RYKEA"
end

--- Включить или отключить сервис для выбранного региона и перерисовать вкладку
local function setRegionAccess(service, enabled)
  local region = System.regions[regionSel]
  if not region then return end
  local ok, err = Policy.set(service, region.id, enabled)
  if ok then
    loadRegionRules()
    setStatus(serviceName(service) .. ": " .. (enabled and "включён" or "отключён") .. " · " .. region.name,
      enabled and "success" or "warning")
  else
    setStatus("Ошибка: " .. tostring(err):sub(1, 70), "danger")
  end
  render()
end

local function renderRegions(body)
  if not (session and session.role == "developer") then
    body:add(GUI.label(3, 3, "Раздел доступен только разработчику", "text"))
    return
  end
  body:add(GUI.label(2, 1, "Региональный доступ к приложениям", "accent"))
  body:add(GUI.label(2, 2, "Выберите регион и включите или отключите для него Магазин и RYKEA.", "dim"))

  if regionError then
    body:add(GUI.label(2, 4, "Не удалось загрузить правила:", "danger"))
    body:add(GUI.textView(2, 5, 88, 4, regionError))
    body:add(GUI.button(2, 10, 18, 1, "Повторить", function()
      loadRegionRules()
      render()
    end, "primary"))
    return
  end

  if regionSel > #System.regions then regionSel = #System.regions end
  if regionSel < 1 then regionSel = 1 end

  local items = {}
  for i, r in ipairs(System.regions) do
    items[i] = padRight(r.name, 18)
      .. padRight("Магазин: " .. (regionEnabled("store", r.id) and "да" or "нет"), 16)
      .. "RYKEA: " .. (regionEnabled("rykea", r.id) and "да" or "нет")
  end
  local list = body:add(GUI.list(2, 4, 60, 10, items))
  list.striped = true
  list.selected = regionSel
  list.onSelect = function(_, idx)
    regionSel = idx
    render()
  end

  local region = System.regions[regionSel]
  local storeOn = regionEnabled("store", region.id)
  local rykeaOn = regionEnabled("rykea", region.id)

  body:add(GUI.label(65, 4, GUI.fit(region.name, 26), "accent"))
  body:add(GUI.label(65, 5, System.settings.region == region.id and "ваш регион" or "другой регион", "dim"))
  body:add(GUI.label(65, 7, "Магазин: " .. (storeOn and "включён" or "отключён"), storeOn and "success" or "danger"))
  body:add(GUI.label(65, 8, "RYKEA:   " .. (rykeaOn and "включена" or "отключена"), rykeaOn and "success" or "danger"))

  body:add(GUI.button(2, 15, 28, 1, storeOn and "Отключить магазин" or "Включить магазин", function()
    setRegionAccess("store", not storeOn)
  end, storeOn and "danger" or "primary"))
  body:add(GUI.button(32, 15, 28, 1, rykeaOn and "Отключить RYKEA" or "Включить RYKEA", function()
    setRegionAccess("rykea", not rykeaOn)
  end, rykeaOn and "danger" or "primary"))
  body:add(GUI.button(2, 17, 18, 1, "Обновить", function()
    if loadRegionRules() then setStatus("Правила обновлены", "dim") end
    render()
  end))
  body:add(GUI.label(2, 19, "Разработчик всегда может открыть магазин, чтобы вернуть доступ себе и другим.", "dim"))
end

-- ------------------------------------------------------------ экраны
local function hintFor()
  if screen == "catalog" then
    return "Enter / двойной клик — установить или запустить · колесо — прокрутка списка"
  elseif screen == "installed" then
    return "Выберите приложение слева — запустите или удалите его"
  elseif screen == "regions" then
    return "Правила хранятся в облаке и действуют на всех компьютерах · окна перепроверяют их каждые " .. Policy.pollSeconds .. " с"
  else
    return "Игры сохраняются в /Users/Games · публикация идёт в Supabase"
  end
end

local function renderCatalog(body)
  local items = catalogItems()
  if #items == 0 then
    body:add(GUI.label(3, 3, "Каталог пуст", "text"))
    body:add(GUI.label(3, 5, "Не найдено ни локальных пакетов, ни облачных игр.", "dim"))
    return
  end
  if selected > #items then selected = #items end
  if selected < 1 then selected = 1 end

  local labels = {}
  for i, it in ipairs(items) do
    labels[i] = (isInstalled(it.id) and "✓ " or "  ") .. it.title .. (it.kind == "cloud" and " ◆" or "")
  end
  local list = body:add(GUI.list(2, 1, 44, 22, labels))
  list.striped = true
  list.selected = selected
  list.onSelect = function(_, idx)
    selected = idx
    render()
  end
  list.onActivate = function(_, idx)
    selected = idx
    local it = items[idx]
    if not it then return end
    if isInstalled(it.id) then runItem(it) else installItem(it) end
    render()
  end

  local it = items[selected]
  local icon = GUI.new(IconView, 47, 2, 16, 8)
  icon.rows, icon.palette = it.rows, it.palette
  body:add(icon)
  body:add(GUI.label(65, 3, GUI.fit(it.title, 27), "accent"))
  body:add(GUI.label(65, 5, GUI.fit("Автор: " .. it.author, 27), "dim"))
  body:add(GUI.label(65, 6, it.kind == "cloud"
    and ("Шаблон: " .. (it.template == "mineos" and "MineOS" or "CubeOS"))
    or (it.kind == "app" and "Источник: сайт" or "Пакет: локальный"), "text"))
  if it.kind == "cloud" then
    body:add(GUI.label(65, 7, "Версия " .. it.version .. " · " .. it.category, "dim"))
  end
  body:add(GUI.textView(47, 11, 47, 7, it.description ~= "" and it.description or "Описание отсутствует."))

  local installedNow = isInstalled(it.id)
  body:add(GUI.button(47, 19, 20, 1, installedNow and Locale.t("launch") or Locale.t("install"), function()
    if installedNow then runItem(it) else installItem(it) end
    render()
  end, "primary"))
  body:add(GUI.button(68, 19, 14, 1, Locale.t("remove"), function()
    if not installedNow then
      setStatus("Не установлено: " .. it.title, "warning")
      render()
      return
    end
    if GUI.confirm("Удаление", "Удалить «" .. it.title .. "» из системы?", "Удалить", "Отмена", true) then
      uninstallItem(it)
      render()
    end
  end, installedNow and "danger" or nil))
  body:add(GUI.label(47, 21, it.kind == "cloud"
    and ("id: " .. it.id)
    or (it.kind == "app" and ("путь: " .. appPath(it.id)) or ("пакет: /StorePackages/" .. it.id .. ".app")), "dim"))
end

local function renderInstalled(body)
  local items = {}
  for _, it in ipairs(catalogItems()) do
    if isInstalled(it.id) then items[#items + 1] = it end
  end
  if #items == 0 then
    body:add(GUI.label(3, 3, "Ничего не установлено", "text"))
    body:add(GUI.textView(3, 5, 70, 8,
      "Откройте «Каталог» и нажмите «Установить». В магазине лежат RYKEA, «Пиксели» и облачные игры других авторов."))
    body:add(GUI.button(3, 15, 20, 1, "В каталог", function()
      screen = "catalog"
      render()
    end, "primary"))
    return
  end
  if selectedInstalled > #items then selectedInstalled = #items end
  if selectedInstalled < 1 then selectedInstalled = 1 end

  local labels = {}
  for i, it in ipairs(items) do labels[i] = it.title end
  local list = body:add(GUI.list(2, 1, 58, 22, labels))
  list.striped = true
  list.selected = selectedInstalled
  list.onSelect = function(_, idx)
    selectedInstalled = idx
    render()
  end
  list.onActivate = function(_, idx)
    selectedInstalled = idx
    if items[idx] then runItem(items[idx]) render() end
  end

  local it = items[selectedInstalled]
  local icon = GUI.new(IconView, 62, 2, 16, 8)
  icon.rows, icon.palette = it.rows, it.palette
  body:add(icon)
  body:add(GUI.label(62, 11, GUI.fit(it.title, 30), "accent"))
  body:add(GUI.textView(62, 12, 31, 6, it.description ~= "" and it.description or ""))
  body:add(GUI.button(62, 19, 16, 1, Locale.t("launch"), function()
    runItem(it)
    render()
  end, "primary"))
  body:add(GUI.button(62, 21, 16, 1, Locale.t("remove"), function()
    if GUI.confirm("Удаление", "Удалить «" .. it.title .. "»?", "Удалить", "Отмена", true) then
      uninstallItem(it)
      render()
    end
  end, "danger"))
end

local DEV_TEXT = table.concat({
  "РАЗРАБОТЧИК ИГР",
  "",
  "1. «Новая игра по шаблону…» создаёт файл в",
  "   /Users/Games и открывает Редактор (F5 — тест).",
  "2. «Опубликовать файл…» отправляет код в Supabase.",
  "3. «Мои публикации…» — список и снятие с публикации.",
  "",
  "Шаблоны:",
  "  MineOS — цикл event.pull + GUI.workspace.",
  "  Работает в CubeOS через библиотеку MineCompat.",
  "  CubeOS — нативное окно ctx.window и виджеты GUI.",
  "",
  "Таблицы базы: store_users, store_games.",
}, "\n")

local function renderDev(body)
  if not (session and session.role == "developer") then
    body:add(GUI.label(3, 3, "Раздел разработчика", "text"))
    body:add(GUI.textView(3, 5, 84, 10,
      "Публиковать игры может только разработчик. Первый зарегистрированный в базе аккаунт " ..
      "получает роль developer автоматически — достаточно один раз нажать «Регистрация» " ..
      "в правом верхнем углу. Остальные аккаунты получают роль user."))
    if not session then
      body:add(GUI.button(3, 17, 26, 1, "Зарегистрировать аккаунт", function()
        authModal("register")
      end, "primary"))
    else
      body:add(GUI.label(3, 17, "Вы вошли: " .. tostring(session.username) .. " · роль " .. tostring(session.role), "dim"))
      body:add(GUI.button(3, 19, 26, 1, "Войти другим аккаунтом", function()
        authModal("login")
      end))
    end
    return
  end
  body:add(GUI.button(3, 2, 30, 1, "Новая игра по шаблону…", function()
    newGameDialog()
  end, "primary"))
  body:add(GUI.button(3, 4, 30, 1, "Опубликовать файл…", function()
    publishDialog()
    render()
  end))
  body:add(GUI.button(3, 6, 30, 1, "Мои публикации…", function()
    mineDialog()
    render()
  end))
  body:add(GUI.button(3, 8, 30, 1, "Обновить каталог", function()
    refreshGames()
    render()
  end))
  body:add(GUI.button(3, 10, 30, 1, Locale.t("access") .. "…", function()
    screen = "regions"
    loadRegionRules()
    render()
  end))
  body:add(GUI.textView(36, 2, 56, 19, DEV_TEXT))
end

-- ------------------------------------------------------------ общий рендер
render = function()
  statusLabel = nil
  refreshExtras()
  c:clear()

  c:add(GUI.label(2, 1, "МАГАЗИН ИГР И ПРИЛОЖЕНИЙ", "accent"))
  local acc = session
    and (tostring(session.username) .. (session.role == "developer" and " · разработчик" or " · игрок"))
    or "Гость"
  c:add(GUI.label(CW - unicode.len(acc) - 3, 1, acc, session and "text" or "dim"))

  local tabs = {
    {"catalog", Locale.t("catalog"), 2, 11},
    {"installed", Locale.t("installed"), 14, 16},
  }
  if session and session.role == "developer" then
    tabs[#tabs + 1] = {"dev", Locale.t("development"), 31, 13}
    tabs[#tabs + 1] = {"regions", Locale.t("regions"), 45, 11}
  end
  for _, t in ipairs(tabs) do
    local id = t[1]
    c:add(GUI.button(t[3], 2, t[4], 1, t[2], function()
      screen = id
      if id == "regions" then loadRegionRules() end
      render()
    end, screen == id and "primary" or nil))
  end

  if session then
    c:add(GUI.button(CW - 12, 2, 10, 1, Locale.t("signOut"), function()
      session = nil
      saveSession()
      screen = "catalog"
      render()
      setStatus("Вы вышли из аккаунта", "dim")
    end))
  else
    c:add(GUI.button(CW - 26, 2, 11, 1, Locale.t("signIn"), function()
      authModal("login")
    end))
    c:add(GUI.button(CW - 14, 2, 12, 1, Locale.t("register"), function()
      authModal("register")
    end))
  end

  c:add(GUI.hline(2, 3, CW - 4, "border"))

  local body = c:add(GUI.panel(1, 4, CW, 22))
  if screen == "catalog" then
    renderCatalog(body)
  elseif screen == "installed" then
    renderInstalled(body)
  elseif screen == "regions" then
    renderRegions(body)
  else
    renderDev(body)
  end

  c:add(GUI.label(2, 26, hintFor(), "dim"))
  statusLabel = c:add(GUI.label(2, 29, status, statusColor))
  win:setTitle("Магазин — " .. (session and tostring(session.username) or "Гость"))
end

-- ------------------------------------------------------------ запуск
--- Активация магазина (первый запуск или повторный с сайта): обновить каталог, показать товар
local function activate(a)
  a = a or {}
  refreshExtras()
  refreshGames()
  screen = "catalog"
  if a.focus then
    local items = catalogItems()
    for i, it in ipairs(items) do
      if it.id == a.focus then selected = i break end
    end
    Desktop.notify("«" .. tostring(a.focus) .. "» в каталоге магазина")
  end
  render()
end

win.onArgs = function(_, a) activate(a) end
win.tickInterval = Policy.pollSeconds
win.onTick = function()
  if session and session.role == "developer" then return false end
  -- Закрываем окно только при явной блокировке. Сбой сети не должен выкидывать
  -- пользователя из магазина: get() вернёт nil, и мы просто проверим снова позже.
  if Policy.get("store") == false then
    win:close()
    GUI.alert("Региональный доступ", Policy.message("store"))
  end
  return false
end

refreshPackages()
activate(ctx.args)
]]},
  {"/Applications/Terminal.app/Info.lua", [[
return {
  title = "Терминал", short = "Терминал", order = 3,
  icon = {
    "dddddddd",
    "dkkkkkkd",
    "dkgkkkkd",
    "dkkgkkkd",
    "dkgkkkkd",
    "dkkkwwkd",
    "dkkkkkkd",
    "dddddddd",
  },
}
]]},
  {"/Applications/Terminal.app/Main.lua", [[
-- Терминал CubeOS
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local computer, unicode = computer, unicode
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local win = ctx.window(84, 26, "Терминал")
win.resizable, win.minW, win.minH = true, 40, 8
local content = win.content

local BG, FG = 0x0C0E12, 0xD7DAE0
local GREEN, BLUE, YELLOW, RED, GRAY = 0x4ADE80, 0x60A5FA, 0xFACC15, 0xF87171, 0x7C8594

local Term = GUI.class()
local term = GUI.new(Term, 1, 1, win.w, win.h - 1)
term.focusable = true
term.lines, term.input, term.cursor = {}, "", 0
term.history, term.histPos, term.scroll = {}, 0, 0
term.cwd = "/Users"
content:add(term)
content.focused = term

function term:print(text, color)
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r", ""):gsub("\t", "  ")
    local width = max(10, self.w - 2)
    if unicode.len(line) == 0 then
      self.lines[#self.lines + 1] = {"", color}
    else
      while unicode.len(line) > 0 do
        self.lines[#self.lines + 1] = {unicode.sub(line, 1, width), color}
        line = unicode.sub(line, width + 1)
      end
    end
  end
  while #self.lines > 500 do table.remove(self.lines, 1) end
  self.scroll = 0
end

function term:prompt()
  return "cube:" .. self.cwd .. "> "
end

function term:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, BG, nil, " ")
  local rows = self.h - 1
  local total = #self.lines
  local last = total - self.scroll
  for r = 1, rows do
    local idx = last - rows + r
    local line = self.lines[idx]
    if line then Screen.text(ax + 1, ay + r - 1, line[2] or FG, line[1], BG) end
  end
  local y = ay + self.h - 1
  local p = self:prompt()
  Screen.text(ax + 1, y, GREEN, p, BG)
  local px = ax + 1 + unicode.len(p)
  local avail = self.w - (px - ax) - 1
  local start = max(0, self.cursor - avail + 1)
  Screen.text(px, y, FG, unicode.sub(self.input, start + 1, start + avail), BG)
  if self:isFocused() then
    local ch = unicode.sub(self.input, self.cursor + 1, self.cursor + 1)
    if ch == "" then ch = " " end
    Screen.text(px + self.cursor - start, y, BG, ch, FG)
  end
end

function term:onEvent(e)
  if e.type == "touch" then
    self:focus()
    return true
  elseif e.type == "scroll" then
    self.scroll = max(0, min(max(0, #self.lines - (self.h - 1)), self.scroll + e.dir * 3))
    return true
  end
  return false
end

-- ------------------------------------------------------------ команды
local cmds = {}

local function path(arg) return System.join(term.cwd, arg or ".") end

local function say(t, c) term:print(t, c) end

cmds.help = function()
  say("Команды:", YELLOW)
  say("  ls [путь]        список файлов        cd <путь>   сменить папку")
  say("  pwd              текущая папка        cat <файл>  показать файл")
  say("  mkdir <папка>    создать папку        touch <файл> создать файл")
  say("  rm [-r] <путь>   удалить              cp / mv <откуда> <куда>")
  say("  echo <текст>     вывести текст        clear       очистить экран")
  say("  edit <файл>      открыть в Редакторе  run <файл>  выполнить Lua-файл")
  say("  lua <код>        выполнить строку     open <имя>  запустить приложение")
  say("  apps  mem  df  date  uptime  ver  neofetch  whoami")
  say("  reboot  shutdown  exit")
end

cmds.pwd = function() say(term.cwd) end
cmds.whoami = function() say(System.settings.username or "user") end
cmds.ver = function() say("CubeOS " .. System.version .. " (сборка " .. System.build .. ")") end
cmds.date = function() say(System.date("%d.%m.%Y %H:%M:%S")) end
cmds.uptime = function() say("Время работы: " .. System.uptimeText()) end
cmds.clear = function() term.lines = {} end
cmds.echo = function(a) say(table.concat(a, " ")) end

cmds.mem = function()
  local used, total = System.memory()
  say(string.format("ОЗУ: %s из %s (%d%%)", System.formatSize(used), System.formatSize(total), floor(used / total * 100)))
end

cmds.df = function()
  local fs = System.fs
  say(string.format("Диск: занято %s из %s", System.formatSize(fs.spaceUsed()), System.formatSize(fs.spaceTotal())))
end

cmds.ls = function(a)
  local p = path(a[1])
  if not System.exists(p) then say("ls: нет такого пути: " .. p, RED) return end
  if not System.isDir(p) then say(System.basename(p)) return end
  local items = System.list(p)
  if #items == 0 then say("(пусто)", GRAY) return end
  for _, name in ipairs(items) do
    local isDir = name:sub(-1) == "/"
    say(string.format("%-28s %s", name, isDir and "<папка>" or System.formatSize(System.size(p .. "/" .. name))), isDir and BLUE or FG)
  end
end

cmds.cd = function(a)
  local p = path(a[1] or "/Users")
  if System.isDir(p) then term.cwd = p else say("cd: нет такой папки: " .. p, RED) end
end

cmds.cat = function(a)
  if not a[1] then say("cat: укажите файл", RED) return end
  local p = path(a[1])
  if System.isDir(p) then say("cat: это папка", RED) return end
  local data, err = System.readFile(p)
  if not data then say("cat: " .. tostring(err), RED) return end
  say(data)
end

cmds.mkdir = function(a)
  if not a[1] then say("mkdir: укажите имя", RED) return end
  System.mkdirs(path(a[1]))
end

cmds.touch = function(a)
  if not a[1] then say("touch: укажите имя", RED) return end
  local p = path(a[1])
  if not System.exists(p) then System.writeFile(p, "") end
end

cmds.rm = function(a)
  local target
  for _, v in ipairs(a) do if v:sub(1, 1) ~= "-" then target = v end end
  if not target then say("rm: укажите путь", RED) return end
  local p = path(target)
  for _, protected in ipairs({"/", "/init.lua", "/Libraries", "/System", "/Applications", "/StorePackages"}) do
    if p == protected then say("rm: системный объект защищён", RED) return end
  end
  if not System.exists(p) then say("rm: нет такого пути", RED) return end
  System.remove(p)
end

cmds.cp = function(a)
  if not a[2] then say("cp: нужно два пути", RED) return end
  local ok, err = System.copy(path(a[1]), path(a[2]))
  if not ok then say("cp: " .. tostring(err), RED) end
end

cmds.mv = function(a)
  if not a[2] then say("mv: нужно два пути", RED) return end
  System.rename(path(a[1]), path(a[2]))
end

cmds.edit = function(a)
  Desktop.launchById("Editor", {file = a[1] and path(a[1]) or nil})
end

cmds.run = function(a)
  if not a[1] then say("run: укажите файл", RED) return end
  local code, err = System.readFile(path(a[1]))
  if not code then say("run: " .. tostring(err), RED) return end
  local ok, out = System.runLua(code, a[1], {Desktop = Desktop, GUI = GUI, System = System})
  if out ~= "" then say(out, ok and FG or RED) end
end

cmds.lua = function(a)
  local code = table.concat(a, " ")
  if code == "" then say("lua: введите код, например: lua 2^10", RED) return end
  local expr = "local r = table.pack(" .. code .. ") for i = 1, r.n do print(r[i]) end"
  local chosen = load(expr, "=lua", "t") and expr or code
  local ok, out = System.runLua(chosen, "lua", {Desktop = Desktop, GUI = GUI, System = System})
  if out ~= "" then say(out, ok and FG or RED) end
end

cmds.apps = function()
  for _, app in ipairs(Desktop.apps) do say(string.format("  %-12s %s", app.id, app.title)) end
end

cmds.open = function(a)
  if not a[1] then say("open: укажите приложение (см. apps)", RED) return end
  Desktop.launchById(a[1])
end

cmds.neofetch = function()
  local used, total = System.memory()
  local w, h = Desktop.screenSize()
  local arch = (computer.getArchitecture and computer.getArchitecture()) or (_VERSION or "Lua 5.3")
  local rows = {
    {"   ▄▄▄▄▄▄   ", GREEN, System.settings.username .. "@cubeos"},
    {" ▄██████████▄", GREEN, "─────────────────"},
    {" ████▀▀▀▀████", GREEN, "ОС:      CubeOS " .. System.version},
    {" ██▀▀    ▀▀██", 0x15803D, "Мод:     " .. (System.platformShort or "OpenComputers")},
    {" ██  ▄▄▄▄  ██", 0x15803D, "MC:      " .. (System.minecraft or "1.20.1")},
    {" ██▄▄████▄▄██", 0x15803D, "ОЗУ:     " .. System.formatSize(used) .. " / " .. System.formatSize(total)},
    {"   ▀▀▀▀▀▀▀▀   ", 0x15803D, "Экран:   " .. w .. "×" .. h},
    {"              ", 0x15803D, "Ядро:    " .. arch},
  }
  for _, r in ipairs(rows) do say(r[1] .. "  " .. r[3], r[2]) end
end

cmds.reboot = function() computer.shutdown(true) end
cmds.shutdown = function() computer.shutdown() end
cmds.exit = function() win:close() end

function term:exec(line)
  self:print(self:prompt() .. line, GRAY)
  line = line:match("^%s*(.-)%s*$")
  if line == "" then return end
  self.history[#self.history + 1] = line
  self.histPos = #self.history + 1
  local args = {}
  for token in line:gmatch("%S+") do args[#args + 1] = token end
  local name = table.remove(args, 1)
  local fn = cmds[name]
  if not fn then
    self:print("Команда не найдена: " .. name .. " (введите help)", RED)
    return
  end
  local ok, err = pcall(fn, args)
  if not ok then self:print("Ошибка: " .. tostring(err), RED) end
end

function term:insert(s)
  self.input = unicode.sub(self.input, 1, self.cursor) .. s .. unicode.sub(self.input, self.cursor + 1)
  self.cursor = self.cursor + unicode.len(s)
end

function term:complete()
  local before = unicode.sub(self.input, 1, self.cursor)
  local word = before:match("(%S*)$") or ""
  local dir, prefix = word:match("^(.*/)([^/]*)$")
  if not dir then dir, prefix = "", word end
  local list = System.list(System.join(self.cwd, dir == "" and "." or dir))
  local found = {}
  for _, name in ipairs(list) do
    if name:sub(1, #prefix):lower() == prefix:lower() then found[#found + 1] = name end
  end
  if #found == 1 then
    self:insert(found[1]:sub(#prefix + 1))
  elseif #found > 1 then
    self:print(table.concat(found, "  "), BLUE)
  end
end

function term:onPaste(text)
  local line = tostring(text):match("^[^\r\n]*")
  if line then self:insert(line) end
  return true
end

function term:onKey(e)
  local code, ch = e.code, e.char
  if e.ctrl then
    if code == 38 then self.lines = {} return true end
    if code == 46 then self:print(self:prompt() .. self.input .. "^C", GRAY) self.input, self.cursor = "", 0 return true end
    return false
  end
  if code == 28 or code == 156 then
    local line = self.input
    self.input, self.cursor = "", 0
    self:exec(line)
  elseif code == 14 then
    if self.cursor > 0 then
      self.input = unicode.sub(self.input, 1, self.cursor - 1) .. unicode.sub(self.input, self.cursor + 1)
      self.cursor = self.cursor - 1
    end
  elseif code == 211 then
    self.input = unicode.sub(self.input, 1, self.cursor) .. unicode.sub(self.input, self.cursor + 2)
  elseif code == 203 then self.cursor = max(0, self.cursor - 1)
  elseif code == 205 then self.cursor = min(unicode.len(self.input), self.cursor + 1)
  elseif code == 199 then self.cursor = 0
  elseif code == 207 then self.cursor = unicode.len(self.input)
  elseif code == 200 then
    if self.histPos > 1 then
      self.histPos = self.histPos - 1
      self.input = self.history[self.histPos]
      self.cursor = unicode.len(self.input)
    end
  elseif code == 208 then
    if self.histPos < #self.history then
      self.histPos = self.histPos + 1
      self.input = self.history[self.histPos]
    else
      self.histPos = #self.history + 1
      self.input = ""
    end
    self.cursor = unicode.len(self.input)
  elseif code == 15 then self:complete()
  elseif code == 201 then self.scroll = min(max(0, #self.lines - (self.h - 1)), self.scroll + 10)
  elseif code == 209 then self.scroll = max(0, self.scroll - 10)
  elseif ch and ch >= 32 and ch ~= 127 then self:insert(unicode.char(ch))
  else return false end
  return true
end

win.onResize = function(_, w, h)
  term.w, term.h = w, h
end

term:print("CubeOS Terminal — введите help для списка команд.", YELLOW)
term:print("")
]]},
  {"/Libraries/GUI.lua", [[
-- ============================================================
--  CubeOS :: GUI
--  Виджеты (панель, метка, кнопка, поле ввода, список, текст,
--  переключатель, прогресс), окна, модальные диалоги и меню.
-- ============================================================
local computer, unicode = computer, unicode
local Screen = require("Screen")
local floor, max, min = math.floor, math.max, math.min

local GUI = {}

-- ------------------------------------------------------------ темы
GUI.themes = {
  dark = {
    menubar = 0x15161A, menubarText = 0xE3E5E8,
    title = 0x1E1F22, titleText = 0xDBDEE1, titleDim = 0x6D717A,
    win = 0x2B2D31, winAlt = 0x313338, panel = 0x232428,
    text = 0xF2F3F5, dim = 0x949BA4, border = 0x4A4D55,
    button = 0x404249, buttonText = 0xF2F3F5,
    input = 0x1A1B1E, inputText = 0xF2F3F5,
    danger = 0xED4245, success = 0x3BA55D, warning = 0xFAA61A,
  },
  light = {
    menubar = 0xE3E5E8, menubarText = 0x1E1F22,
    title = 0xD8DADE, titleText = 0x2E3338, titleDim = 0x8A8F98,
    win = 0xF2F3F5, winAlt = 0xE8EAED, panel = 0xDDDFE3,
    text = 0x1E1F22, dim = 0x5C6068, border = 0xB5BAC1,
    button = 0xD4D7DC, buttonText = 0x1E1F22,
    input = 0xFFFFFF, inputText = 0x1E1F22,
    danger = 0xD83C3E, success = 0x2D9D5B, warning = 0xC77F0A,
  },
}

GUI.accents = {
  {name = "Синий", color = 0x4C8DFF},
  {name = "Зелёный", color = 0x3DDC84},
  {name = "Оранжевый", color = 0xFF9F43},
  {name = "Фиолетовый", color = 0xA78BFA},
  {name = "Розовый", color = 0xFF6B9A},
  {name = "Бирюзовый", color = 0x22D3EE},
}

GUI.color = {}
local C = GUI.color

function GUI.setTheme(name, accent)
  local t = GUI.themes[name] or GUI.themes.dark
  for k, v in pairs(t) do C[k] = v end
  local a = GUI.accents[accent or 1] or GUI.accents[1]
  C.accent = a.color
  local r, g, b = floor(a.color / 65536) % 256, floor(a.color / 256) % 256, a.color % 256
  C.accentText = (0.299 * r + 0.587 * g + 0.114 * b) > 150 and 0x0B1020 or 0xFFFFFF
end
GUI.setTheme("dark", 1)

--- Цвет может быть числом или именем из темы ("dim", "accent"...)
local function rc(v, default)
  if type(v) == "string" then return C[v] or default end
  return v or default
end
GUI.rc = rc

-- ------------------------------------------------------------ утилиты
function GUI.fit(text, width)
  text = tostring(text)
  if unicode.len(text) <= width then return text end
  if width <= 1 then return unicode.sub(text, 1, width) end
  return unicode.sub(text, 1, width - 1) .. "…"
end

function GUI.wrap(text, width)
  local lines = {}
  for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    if para == "" then
      lines[#lines + 1] = ""
    else
      local line = ""
      for word in para:gmatch("%S+") do
        while unicode.len(word) > width do
          if line ~= "" then lines[#lines + 1] = line line = "" end
          lines[#lines + 1] = unicode.sub(word, 1, width)
          word = unicode.sub(word, width + 1)
        end
        if line == "" then
          line = word
        elseif unicode.len(line) + 1 + unicode.len(word) <= width then
          line = line .. " " .. word
        else
          lines[#lines + 1] = line
          line = word
        end
      end
      if line ~= "" then lines[#lines + 1] = line end
    end
  end
  return lines
end

--- Вертикальный градиент полублоками (2 «пикселя» на ячейку)
function GUI.gradient(x, y, w, h, c1, c2)
  local den = max(1, h * 2 - 1)
  for r = 1, h do
    local top = Screen.blend(c2, c1, (r * 2 - 2) / den)
    local bottom = Screen.blend(c2, c1, (r * 2 - 1) / den)
    Screen.rect(x, y + r - 1, w, 1, bottom, top, "▀")
  end
end

local basePal = {
  r = 0xED4245, g = 0x3BA55D, b = 0x4C8DFF, y = 0xFAA61A, w = 0xFFFFFF, k = 0x1E1F22,
  a = 0x949BA4, d = 0x4E5058, o = 0xFF8A3D, p = 0xA78BFA, c = 0x22D3EE, n = 0x8B5E3C,
  l = 0xE3E5E8, t = 0x2DD4BF, m = 0xF472B6, s = 0x5865F2, e = 0x2B2D31, u = 0x1D4ED8,
}

--- Иконка 8×8 «пикселей» → 8×4 символа (▀/▄). Строки иконки — 1..8.
function GUI.drawIcon(x, y, icon)
  if not icon.pal then icon.pal = {} end
  if not getmetatable(icon.pal) then setmetatable(icon.pal, {__index = basePal}) end
  local pal = icon.pal
  for r = 1, 4 do
    local top, bot = icon[r * 2 - 1] or "", icon[r * 2] or ""
    for c = 1, 8 do
      local tc, bc = pal[top:sub(c, c)], pal[bot:sub(c, c)]
      if tc and bc then
        Screen.set(x + c - 1, y + r - 1, bc, tc, "▀")
      elseif tc then
        Screen.set(x + c - 1, y + r - 1, nil, tc, "▀")
      elseif bc then
        Screen.set(x + c - 1, y + r - 1, nil, bc, "▄")
      end
    end
  end
end

-- ------------------------------------------------------------ базовый виджет
local Widget = {}
Widget.__index = Widget
GUI.Widget = Widget

local function class(base)
  local c = {}
  c.__index = c
  return setmetatable(c, {__index = base or Widget})
end
GUI.class = class

local function new(cls, x, y, w, h)
  return setmetatable({x = x, y = y, w = w, h = h, children = {}, visible = true}, cls)
end
GUI.new = new

function Widget:add(child)
  child.parent = self
  self.children[#self.children + 1] = child
  return child
end

function Widget:remove(child)
  for i, c in ipairs(self.children) do
    if c == child then
      table.remove(self.children, i)
      child.parent = nil
      return
    end
  end
end

function Widget:clear()
  self.children = {}
  self.focused = nil
  self.captured = nil
end

function Widget:root()
  local r = self
  while r.parent do r = r.parent end
  return r
end

function Widget:focus() self:root().focused = self end
function Widget:isFocused() return self:root().focused == self end
function Widget:capture() self:root().captured = self end

--- Абсолютные координаты виджета, если корень находится в (rx, ry)
function Widget:absPos(rx, ry)
  local chain, w = {}, self
  while w.parent do
    chain[#chain + 1] = w
    w = w.parent
  end
  local x, y = rx, ry
  for i = #chain, 1, -1 do
    x = x + chain[i].x - 1
    y = y + chain[i].y - 1
  end
  return x, y
end

function Widget:contains(px, py, ax, ay)
  return px >= ax and px < ax + self.w and py >= ay and py < ay + self.h
end

function Widget:draw(ax, ay)
  if not self.visible then return end
  if self.drawSelf then self:drawSelf(ax, ay) end
  if #self.children > 0 then
    Screen.pushClip(ax, ay, self.w, self.h)
    for _, c in ipairs(self.children) do
      c:draw(ax + c.x - 1, ay + c.y - 1)
    end
    Screen.popClip()
  end
end

function Widget:handle(e, ax, ay)
  if not self.visible or self.disabled then return false end
  if not self:contains(e.x, e.y, ax, ay) then return false end
  for i = #self.children, 1, -1 do
    local c = self.children[i]
    if c:handle(e, ax + c.x - 1, ay + c.y - 1) then return true end
  end
  if self.onEvent then return self:onEvent(e, ax, ay) end
  return false
end

-- ------------------------------------------------------------ панель
local Panel = class()
function Panel:drawSelf(ax, ay)
  if self.bg then Screen.rect(ax, ay, self.w, self.h, rc(self.bg, C.win), nil, " ") end
end
function GUI.panel(x, y, w, h, bg)
  local p = new(Panel, x, y, w, h)
  p.bg = bg
  return p
end

-- ------------------------------------------------------------ метка
local Label = class()
function Label:drawSelf(ax, ay)
  local bg = self.bg and rc(self.bg) or nil
  local s = self.text
  local x = ax
  if self.align == "right" then
    x = ax + self.w - unicode.len(s)
  elseif self.align == "center" then
    x = ax + floor((self.w - unicode.len(s)) / 2)
  end
  if bg then Screen.rect(ax, ay, self.w, 1, bg, nil, " ") end
  Screen.text(x, ay, rc(self.fg, C.text), s, bg)
end
function Label:setText(t)
  self.text = tostring(t)
  if not self.fixed then self.w = unicode.len(self.text) end
end
--- width задан → ширина фиксирована (нужно для выравнивания и заливки)
function GUI.label(x, y, text, fg, bg, width, align)
  local l = new(Label, x, y, width or 0, 1)
  l.fg, l.bg, l.align = fg, bg, align
  l.fixed = width ~= nil
  l:setText(text)
  return l
end

-- ------------------------------------------------------------ кнопка
local Button = class()
function Button:drawSelf(ax, ay)
  local bg, fg
  if self.disabled then
    bg, fg = C.panel, C.dim
  elseif self.active then
    bg, fg = C.accent, C.accentText
  elseif self.color then
    bg, fg = rc(self.color), self.textColor and rc(self.textColor) or C.text
  elseif self.style == "primary" then
    bg, fg = C.accent, C.accentText
  elseif self.style == "danger" then
    bg, fg = C.danger, 0xFFFFFF
  elseif self.style == "flat" then
    bg, fg = nil, C.text
  else
    bg, fg = C.button, C.buttonText
  end
  if bg then Screen.rect(ax, ay, self.w, self.h, bg, nil, " ") end
  local label = GUI.fit(self.text, self.w - 1)
  Screen.text(ax + floor((self.w - unicode.len(label)) / 2), ay + floor((self.h - 1) / 2), fg, label, bg)
end
function Button:onEvent(e)
  if e.type == "touch" and e.button == 0 then
    if self.onClick then self.onClick(self, e) end
    return true
  end
  return false
end
function GUI.button(x, y, w, h, text, onClick, style)
  local b = new(Button, x, y, w, h)
  b.text, b.onClick, b.style = text, onClick, style
  return b
end

-- ------------------------------------------------------------ поле ввода
local Input = class()
function Input:setText(t)
  self.text = tostring(t)
  self.cursor = unicode.len(self.text)
  self.scroll = 0
end
function Input:drawSelf(ax, ay)
  local focused = self:isFocused()
  local bg = rc(self.bg, C.input)
  Screen.rect(ax, ay, self.w, 1, bg, nil, " ")
  local shown = self.text
  if self.mask then shown = string.rep("•", unicode.len(shown)) end
  local avail = self.w - 2
  if self.cursor < self.scroll then self.scroll = self.cursor end
  if self.cursor > self.scroll + avail - 1 then self.scroll = self.cursor - avail + 1 end
  if self.scroll < 0 then self.scroll = 0 end
  if shown == "" and self.placeholder and not focused then
    Screen.text(ax + 1, ay, C.dim, GUI.fit(self.placeholder, avail), bg)
  else
    Screen.text(ax + 1, ay, rc(self.fg, C.inputText), unicode.sub(shown, self.scroll + 1, self.scroll + avail), bg)
  end
  if focused then
    local ch = unicode.sub(shown, self.cursor + 1, self.cursor + 1)
    if ch == "" then ch = " " end
    Screen.text(ax + 1 + self.cursor - self.scroll, ay, bg, ch, C.accent)
  end
end
function Input:onEvent(e, ax)
  if e.type == "touch" then
    self:focus()
    self.cursor = max(0, min(unicode.len(self.text), self.scroll + (e.x - ax - 1)))
    return true
  end
  return false
end
function Input:insert(s)
  self.text = unicode.sub(self.text, 1, self.cursor) .. s .. unicode.sub(self.text, self.cursor + 1)
  self.cursor = self.cursor + unicode.len(s)
  if self.onChange then self.onChange(self, self.text) end
end
function Input:onPaste(text)
  local line = tostring(text):match("^[^\r\n]*")
  if line and line ~= "" then self:insert(line) end
  return true
end
function Input:onKey(e)
  local code, ch = e.code, e.char
  if code == 28 or code == 156 then
    if self.onSubmit then self.onSubmit(self, self.text) return true end
    return false
  elseif code == 14 then
    if self.cursor > 0 then
      self.text = unicode.sub(self.text, 1, self.cursor - 1) .. unicode.sub(self.text, self.cursor + 1)
      self.cursor = self.cursor - 1
      if self.onChange then self.onChange(self, self.text) end
    end
  elseif code == 211 then
    if self.cursor < unicode.len(self.text) then
      self.text = unicode.sub(self.text, 1, self.cursor) .. unicode.sub(self.text, self.cursor + 2)
      if self.onChange then self.onChange(self, self.text) end
    end
  elseif code == 203 then
    self.cursor = max(0, self.cursor - 1)
  elseif code == 205 then
    self.cursor = min(unicode.len(self.text), self.cursor + 1)
  elseif code == 199 then
    self.cursor = 0
  elseif code == 207 then
    self.cursor = unicode.len(self.text)
  elseif ch and ch >= 32 and ch ~= 127 and not e.ctrl then
    self:insert(unicode.char(ch))
  else
    return false
  end
  return true
end
function GUI.input(x, y, w, text, placeholder, opts)
  local i = new(Input, x, y, w, 1)
  i.placeholder = placeholder
  i.focusable = true
  i.scroll = 0
  if opts then for k, v in pairs(opts) do i[k] = v end end
  i:setText(text or "")
  return i
end

-- ------------------------------------------------------------ список
local List = class()
function List:visibleRows() return floor(self.h / (self.rowHeight or 1)) end
function List:ensureVisible()
  local vis = self:visibleRows()
  if self.selected < self.scroll + 1 then self.scroll = self.selected - 1 end
  if self.selected > self.scroll + vis then self.scroll = self.selected - vis end
  if self.scroll < 0 then self.scroll = 0 end
end
function List:setItems(items)
  self.items = items
  if self.selected > #items then self.selected = #items end
  if self.selected < 0 then self.selected = 0 end
  self.scroll = max(0, min(self.scroll, #items - self:visibleRows()))
end
function List:drawSelf(ax, ay)
  local rh = self.rowHeight or 1
  local vis = self:visibleRows()
  local base = rc(self.bg, C.win)
  Screen.rect(ax, ay, self.w, self.h, base, nil, " ")
  local total = #self.items
  if self.scroll > total - vis then self.scroll = max(0, total - vis) end
  local textW = self.w - (total > vis and 1 or 0)
  for row = 1, vis do
    local idx = self.scroll + row
    local item = self.items[idx]
    if not item then break end
    local y = ay + (row - 1) * rh
    local sel = idx == self.selected
    local bg = sel and C.accent or ((self.striped and idx % 2 == 0) and C.winAlt or base)
    Screen.rect(ax, y, textW, rh, bg, nil, " ")
    if self.render then
      self.render(self, item, idx, ax, y, textW, sel, bg)
    else
      local label = type(item) == "table" and item.text or tostring(item)
      Screen.text(ax + 1, y, sel and C.accentText or C.text, GUI.fit(label, textW - 2), bg)
    end
  end
  if total > vis then
    local barH = max(1, floor(self.h * vis / total))
    local barY = floor((self.h - barH) * self.scroll / max(1, total - vis))
    Screen.rect(ax + self.w - 1, ay, 1, self.h, C.panel, nil, " ")
    Screen.rect(ax + self.w - 1, ay + barY, 1, barH, C.dim, nil, " ")
  end
end
function List:onEvent(e, ax, ay)
  local rh = self.rowHeight or 1
  if e.type == "touch" then
    self:focus()
    local idx = self.scroll + floor((e.y - ay) / rh) + 1
    if idx >= 1 and idx <= #self.items and (e.y - ay) < self:visibleRows() * rh then
      local now = computer.uptime()
      local dbl = self.lastIdx == idx and now - (self.lastTime or 0) < 0.6 and e.button == 0
      self.selected, self.lastIdx, self.lastTime = idx, idx, now
      if e.button == 1 then
        if self.onContext then self.onContext(self, idx, e) end
      else
        if self.onSelect then self.onSelect(self, idx) end
        if dbl then
          self.lastTime = 0
          if self.onActivate then self.onActivate(self, idx) end
        end
      end
    elseif e.button == 1 and self.onContext then
      self.onContext(self, nil, e)
    end
    return true
  elseif e.type == "scroll" then
    self.scroll = max(0, min(max(0, #self.items - self:visibleRows()), self.scroll - e.dir * 3))
    return true
  end
  return false
end
function List:onKey(e)
  local code, n = e.code, #self.items
  local old = self.selected
  if code == 200 then self.selected = max(1, self.selected - 1)
  elseif code == 208 then self.selected = min(n, self.selected + 1)
  elseif code == 201 then self.selected = max(1, self.selected - self:visibleRows())
  elseif code == 209 then self.selected = min(n, self.selected + self:visibleRows())
  elseif code == 199 then self.selected = min(n, 1)
  elseif code == 207 then self.selected = n
  elseif code == 28 then
    if self.onActivate and self.items[self.selected] then self.onActivate(self, self.selected) return true end
    return false
  else
    return false
  end
  self:ensureVisible()
  if old ~= self.selected and self.onSelect then self.onSelect(self, self.selected) end
  return true
end
function List:getSelected() return self.items[self.selected] end
function GUI.list(x, y, w, h, items)
  local l = new(List, x, y, w, h)
  l.items, l.selected, l.scroll = items or {}, 0, 0
  l.focusable = true
  return l
end

-- ------------------------------------------------------------ текстовый блок
local TextView = class()
function TextView:setText(text)
  self.raw = tostring(text)
  self.lines = GUI.wrap(self.raw, max(1, self.w - 1))
  self.scroll = 0
end
function TextView:drawSelf(ax, ay)
  local bg = self.bg and rc(self.bg) or nil
  if bg then Screen.rect(ax, ay, self.w, self.h, bg, nil, " ") end
  for row = 1, self.h do
    local line = self.lines[self.scroll + row]
    if not line then break end
    Screen.text(ax, ay + row - 1, rc(self.fg, C.text), line, bg)
  end
  if #self.lines > self.h then
    local barH = max(1, floor(self.h * self.h / #self.lines))
    local barY = floor((self.h - barH) * self.scroll / max(1, #self.lines - self.h))
    Screen.rect(ax + self.w - 1, ay + barY, 1, barH, C.dim, nil, " ")
  end
end
function TextView:onEvent(e)
  if e.type == "scroll" then
    self.scroll = max(0, min(max(0, #self.lines - self.h), self.scroll - e.dir * 2))
    return true
  end
  return false
end
function GUI.textView(x, y, w, h, text, fg, bg)
  local t = new(TextView, x, y, w, h)
  t.fg, t.bg, t.scroll = fg, bg, 0
  t:setText(text or "")
  return t
end

-- ------------------------------------------------------------ переключатель и прогресс
local Switch = class()
function Switch:drawSelf(ax, ay)
  local bg = self.on and C.accent or C.border
  Screen.rect(ax, ay, 6, 1, bg, nil, " ")
  Screen.rect(ax + (self.on and 4 or 0), ay, 2, 1, 0xFFFFFF, nil, " ")
end
function Switch:onEvent(e)
  if e.type == "touch" and e.button == 0 then
    self.on = not self.on
    if self.onChange then self.onChange(self, self.on) end
    return true
  end
  return false
end
function GUI.switch(x, y, on, onChange)
  local s = new(Switch, x, y, 6, 1)
  s.on, s.onChange = on and true or false, onChange
  return s
end

local Progress = class()
function Progress:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, 1, C.border, nil, " ")
  local n = floor(self.w * max(0, min(1, self.value)) + 0.5)
  if n > 0 then Screen.rect(ax, ay, n, 1, rc(self.color, C.accent), nil, " ") end
end
function GUI.progress(x, y, w, value, color)
  local p = new(Progress, x, y, w, 1)
  p.value, p.color = value or 0, color
  return p
end

function GUI.hline(x, y, w, color)
  local l = GUI.label(x, y, string.rep("─", w), color or "border")
  return l
end

-- ------------------------------------------------------------ окно
local Window = class()

function GUI.window(x, y, w, h, title)
  local win = new(Window, x, y, w, h)
  win.title = title
  win.minW, win.minH = 24, 6
  win.content = GUI.panel(1, 1, w, h - 1, "win")
  return win
end

function Window:hit(px, py)
  return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h
end

function Window:draw(focused)
  local x, y, w, h = self.x, self.y, self.w, self.h
  if not self.maximized then Screen.rect(x + 2, y + 1, w, h, 0x000000, nil, nil, 0.5) end
  Screen.rect(x, y, w, 1, C.title, nil, " ")
  local red, yel, grn = 0xED4245, 0xFAA61A, 0x3BA55D
  if not focused then red, yel, grn = C.titleDim, C.titleDim, C.titleDim end
  Screen.text(x + 1, y, red, "●", C.title)
  if not self.modal then
    Screen.text(x + 3, y, yel, "●", C.title)
    Screen.text(x + 5, y, self.resizable and grn or C.titleDim, "●", C.title)
  end
  local t = GUI.fit(self.title or "", max(1, w - 14))
  Screen.text(x + floor((w - unicode.len(t)) / 2), y, focused and C.titleText or C.titleDim, t, C.title)
  self.content.w, self.content.h = w, h - 1
  self.content:draw(x, y + 1)
  if self.resizable and not self.maximized then
    Screen.text(x + w - 1, y + h - 1, C.dim, "◢", rc(self.content.bg, C.win))
  end
end

function Window:setTitle(t) self.title = t end

function Window:resize(w, h)
  self.w, self.h = w, h
  self.content.w, self.content.h = w, h - 1
  if self.onResize then self.onResize(self, w, h - 1) end
end

function Window:close()
  if self.modal then
    self.closed = true
  elseif GUI.desktop then
    GUI.desktop.closeWindow(self)
  end
end

local function collectFocusable(w, out)
  for _, c in ipairs(w.children) do
    if c.visible and not c.disabled then
      if c.focusable then out[#out + 1] = c end
      collectFocusable(c, out)
    end
  end
end

function Window:focusNext(dir)
  local list = {}
  collectFocusable(self.content, list)
  if #list == 0 then return end
  local idx = 0
  for i, w in ipairs(list) do
    if w == self.content.focused then idx = i end
  end
  idx = idx + (dir or 1)
  if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
  self.content.focused = list[idx]
end

function Window:keyEvent(e)
  local f = self.content.focused
  if f and f.visible and not f.disabled then
    if e.type == "paste" and f.onPaste and f:onPaste(e.text) then return true end
    if e.type == "key" and f.onKey and f:onKey(e) then return true end
  end
  if self.onKey and self:onKey(e) then return true end
  if e.type == "key" then
    if e.code == 15 then
      self:focusNext(e.shift and -1 or 1)
      return true
    elseif e.code == 28 and self.onEnter then
      self.onEnter(self)
      return true
    elseif e.ctrl and e.code == 17 and not self.modal then
      self:close()
      return true
    end
  end
  return false
end

function Window:dispatch(e)
  local c, t = self.content, e.type
  if t == "touch" then
    c.captured = nil
    return c:handle(e, self.x, self.y + 1)
  elseif t == "scroll" then
    return c:handle(e, self.x, self.y + 1)
  elseif t == "drag" or t == "drop" then
    local cap = c.captured
    if cap and cap.onEvent then
      local ax, ay = cap:absPos(self.x, self.y + 1)
      cap:onEvent(e, ax, ay)
    end
    if t == "drop" then c.captured = nil end
    return true
  end
  return self:keyEvent(e)
end

--- Интерфейс модального окна для Desktop.runModal
function Window:event(e)
  if e.type == "touch" and e.y == self.y and e.x == self.x + 1 then
    self.closed = true
  elseif e.type == "key" and e.code == 1 then
    self.closed = true
  else
    self:dispatch(e)
  end
end

-- ------------------------------------------------------------ модальные окна и диалоги
function GUI.runModal(modal)
  return GUI.desktop.runModal(modal)
end

function GUI.modalWindow(title, w, h)
  local sw, sh = Screen.size()
  w, h = min(w, sw), min(h, sh - 2)
  local win = GUI.window(floor((sw - w) / 2) + 1, floor((sh - h) / 2) + 1, w, h, title)
  win.modal = true
  return win
end

function GUI.alert(title, message, okText)
  local lines = GUI.wrap(message, 46)
  local n = min(#lines, 18)
  local win = GUI.modalWindow(title, 50, n + 6)
  local c = win.content
  for i = 1, n do c:add(GUI.label(3, 1 + i, lines[i])) end
  c:add(GUI.button(19, n + 4, 12, 1, okText or "OK", function() win.closed = true end, "primary"))
  win.onEnter = function() win.closed = true end
  GUI.runModal(win)
end

--- Возвращает true / false
function GUI.confirm(title, message, yesText, noText, danger)
  local lines = GUI.wrap(message, 46)
  local n = min(#lines, 18)
  local win = GUI.modalWindow(title, 50, n + 6)
  local c = win.content
  for i = 1, n do c:add(GUI.label(3, 1 + i, lines[i])) end
  c:add(GUI.button(9, n + 4, 14, 1, yesText or "Да", function() win.result = true win.closed = true end, danger and "danger" or "primary"))
  c:add(GUI.button(28, n + 4, 14, 1, noText or "Отмена", function() win.result = false win.closed = true end))
  win.onEnter = function() win.result = true win.closed = true end
  return GUI.runModal(win) == true
end

--- Запрос строки. Возвращает текст или nil при отмене
function GUI.prompt(title, message, default, mask)
  local lines = GUI.wrap(message, 46)
  local n = min(#lines, 10)
  local win = GUI.modalWindow(title, 50, n + 8)
  local c = win.content
  for i = 1, n do c:add(GUI.label(3, 1 + i, lines[i])) end
  local input = c:add(GUI.input(3, n + 3, 44, default or "", nil, {mask = mask}))
  c.focused = input
  local function ok() win.result = input.text win.closed = true end
  input.onSubmit = ok
  c:add(GUI.button(9, n + 5, 14, 1, "OK", ok, "primary"))
  c:add(GUI.button(28, n + 5, 14, 1, "Отмена", function() win.closed = true end))
  return GUI.runModal(win)
end

--- Выбор из списка строк. Возвращает индекс или nil
function GUI.select(title, options)
  local h = min(#options, 14)
  local win = GUI.modalWindow(title, 44, h + 5)
  local c = win.content
  local list = c:add(GUI.list(2, 2, 42, h, options))
  list.selected = 1
  c.focused = list
  list.onActivate = function(_, idx) win.result = idx win.closed = true end
  c:add(GUI.button(8, h + 3, 12, 1, "Выбрать", function()
    if list.selected > 0 then win.result = list.selected win.closed = true end
  end, "primary"))
  c:add(GUI.button(24, h + 3, 12, 1, "Отмена", function() win.closed = true end))
  return GUI.runModal(win)
end

--- Контекстное меню. items: {text=, action=, hint=, disabled=, separator=}
--- Возвращает выбранный пункт (его action вызывается автоматически).
function GUI.menu(x, y, items)
  local sw, sh = Screen.size()
  local w = 8
  for _, it in ipairs(items) do
    if not it.separator then
      w = max(w, unicode.len(it.text) + (it.hint and unicode.len(it.hint) + 3 or 0) + 4)
    end
  end
  local h = #items
  x = max(1, min(x, sw - w))
  y = max(1, min(y, sh - h))
  local m = {x = x, y = y, w = w, h = h, items = items, noDim = true, closed = false}
  for i, it in ipairs(items) do
    if not it.separator and not it.disabled then m.sel = i break end
  end
  function m:draw()
    Screen.rect(self.x + 2, self.y + 1, self.w, self.h, 0x000000, nil, nil, 0.5)
    Screen.rect(self.x, self.y, self.w, self.h, C.title, nil, " ")
    for i, it in ipairs(self.items) do
      local yy = self.y + i - 1
      if it.separator then
        Screen.text(self.x, yy, C.border, string.rep("─", self.w), C.title)
      else
        local sel = i == self.sel
        local bg = sel and C.accent or C.title
        local fg = it.disabled and C.titleDim or (sel and C.accentText or C.titleText)
        Screen.rect(self.x, yy, self.w, 1, bg, nil, " ")
        Screen.text(self.x + 2, yy, fg, it.text, bg)
        if it.hint then
          Screen.text(self.x + self.w - unicode.len(it.hint) - 1, yy, sel and C.accentText or C.titleDim, it.hint, bg)
        end
      end
    end
  end
  function m:move(dir)
    local i = self.sel or 0
    for _ = 1, #self.items do
      i = i + dir
      if i < 1 then i = #self.items elseif i > #self.items then i = 1 end
      local it = self.items[i]
      if not it.separator and not it.disabled then self.sel = i return end
    end
  end
  function m:event(e)
    if e.type == "touch" then
      if e.x >= self.x and e.x < self.x + self.w and e.y >= self.y and e.y < self.y + self.h then
        local it = self.items[e.y - self.y + 1]
        if it and not it.separator and not it.disabled then
          self.result = it
          self.closed = true
        end
      else
        self.closed = true
      end
    elseif e.type == "key" then
      if e.code == 1 then self.closed = true
      elseif e.code == 200 then self:move(-1)
      elseif e.code == 208 then self:move(1)
      elseif e.code == 28 and self.sel then self.result = self.items[self.sel] self.closed = true end
    end
  end
  local it = GUI.runModal(m)
  if it and it.action then it.action() end
  return it
end

return GUI
]]},
  {"/Libraries/HTTP.lua", [[
-- ============================================================
--  CubeOS :: HTTP
--  Обёртка над Internet Card: синхронный запрос с таймаутом.
-- ============================================================
local component, computer = component, computer

local HTTP = {}

function HTTP.available()
  return component.list("internet")() ~= nil
end

--- Выполнить запрос. Возвращает тело, код ответа — либо nil, причина.
--- body — строка для POST/PUT/PATCH, method — "GET", "POST", "DELETE"...
function HTTP.request(url, body, headers, method, timeout)
  local address = component.list("internet")()
  if not address then return nil, "Нужна Internet Card" end
  local inet = component.proxy(address)

  local ok, handle, reason = pcall(inet.request, url, body, headers, method)
  if not ok then return nil, tostring(handle) end
  if not handle then return nil, tostring(reason or "запрос не удался") end

  local deadline = computer.uptime() + (timeout or 15)
  local chunks = {}
  while true do
    local chunk, err = handle.read(math.huge)
    if chunk then
      if #chunk > 0 then chunks[#chunks + 1] = chunk end
    else
      if err then
        pcall(handle.close)
        return nil, tostring(err)
      end
      break
    end
    if computer.uptime() > deadline then
      pcall(handle.close)
      return nil, "превышено время ожидания"
    end
  end

  local code
  if handle.response then
    local okResp, c = pcall(handle.response)
    if okResp then code = c end
  end
  pcall(handle.close)
  return table.concat(chunks), code
end

function HTTP.get(url, headers, timeout)
  return HTTP.request(url, nil, headers, "GET", timeout)
end

return HTTP
]]},
  {"/Libraries/JSON.lua", [[
-- ============================================================
--  CubeOS :: JSON
--  Полноценный кодировщик/декодировщик (в т.ч. \uXXXX и суррогаты)
-- ============================================================
local unicode = unicode

local JSON = {}

local escMap = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f'}

local function esc(s)
  return (s:gsub('[%c"\\]', function(c)
    return escMap[c] or string.format("\\u%04x", c:byte())
  end))
end

local function isArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return true end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local function encode(v, out)
  local t = type(v)
  if t == "nil" then
    out[#out + 1] = "null"
  elseif t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "null"
    elseif v == math.floor(v) and math.abs(v) < 1e15 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.14g", v)
    end
  elseif t == "string" then
    out[#out + 1] = '"' .. esc(v) .. '"'
  elseif t == "table" then
    if isArray(v) then
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = "," end
        encode(v[i], out)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = '"' .. esc(tostring(k)) .. '":'
        encode(v[k], out)
      end
      out[#out + 1] = "}"
    end
  else
    out[#out + 1] = "null"
  end
end

function JSON.encode(value)
  local out = {}
  encode(value, out)
  return table.concat(out)
end

-- ------------------------------------------------------------ декодер
local simpleEsc = {n = "\n", t = "\t", r = "\r", b = "\b", f = "\f"}

local function skip(s, i)
  return s:find("[^ \t\r\n]", i) or #s + 1
end

local parseValue

local function parseString(s, i)
  local out, j = {}, i + 1
  while true do
    local a = s:find('["\\]', j)
    if not a then error("незакрытая строка JSON") end
    out[#out + 1] = s:sub(j, a - 1)
    if s:sub(a, a) == '"' then return table.concat(out), a + 1 end
    local e = s:sub(a + 1, a + 1)
    if e == "u" then
      local code = tonumber(s:sub(a + 2, a + 5), 16) or 63
      j = a + 6
      if code >= 0xD800 and code < 0xDC00 and s:sub(j, j + 1) == "\\u" then
        local low = tonumber(s:sub(j + 2, j + 5), 16)
        if low and low >= 0xDC00 and low < 0xE000 then
          code = 0x10000 + (code - 0xD800) * 1024 + (low - 0xDC00)
          j = j + 6
        end
      end
      out[#out + 1] = unicode.char(code)
    else
      out[#out + 1] = simpleEsc[e] or e
      j = a + 2
    end
  end
end

parseValue = function(s, i)
  i = skip(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    return parseString(s, i)
  elseif c == "{" then
    local obj = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      i = skip(s, i)
      if s:sub(i, i) ~= '"' then error("ожидался ключ объекта на позиции " .. i) end
      local key
      key, i = parseString(s, i)
      i = skip(s, i)
      if s:sub(i, i) ~= ":" then error("ожидалось ':' на позиции " .. i) end
      local val
      val, i = parseValue(s, i + 1)
      obj[key] = val
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "}" then return obj, i + 1 end
      if d ~= "," then error("ожидалось ',' на позиции " .. i) end
      i = i + 1
    end
  elseif c == "[" then
    local arr, n = {}, 0
    i = skip(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local val
      val, i = parseValue(s, i)
      if val ~= nil then n = n + 1 arr[n] = val end
      i = skip(s, i)
      local d = s:sub(i, i)
      if d == "]" then return arr, i + 1 end
      if d ~= "," then error("ожидалось ',' в массиве на позиции " .. i) end
      i = i + 1
    end
  elseif s:sub(i, i + 3) == "true" then
    return true, i + 4
  elseif s:sub(i, i + 4) == "false" then
    return false, i + 5
  elseif s:sub(i, i + 3) == "null" then
    return nil, i + 4
  end
  local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
  if not num or num == "" then error("неожиданный символ на позиции " .. i) end
  return tonumber(num), i + #num
end

--- Возвращает значение либо nil, текст ошибки
function JSON.decode(str)
  local ok, val = pcall(function()
    local v = parseValue(tostring(str), 1)
    return v
  end)
  if ok then return val end
  return nil, tostring(val)
end

return JSON
]]},
  {"/Libraries/Locale.lua", [[
local System = require("System")

local texts = {
  ru = {
    welcome = "Добро пожаловать", openStore = "Открыть магазин", understood = "Понятно",
    intro = "Графическая оболочка для OpenComputers.\n\n• Док запускает приложения; правый клик открывает меню.\n• Окна можно двигать и разворачивать.\n• Магазин устанавливает RYKEA, Пиксели и игры.\n• Доступ к магазину и RYKEA зависит от региона.",
    catalog = "Каталог", installed = "Установленные", development = "Разработка",
    signIn = "Войти", signOut = "Выйти", register = "Регистрация",
    install = "Установить", launch = "Запустить", remove = "Удалить",
    access = "Доступ по регионам", regions = "Регионы", region = "Регион", language = "Язык",
  },
  en = {
    welcome = "Welcome", openStore = "Open Store", understood = "Got it",
    intro = "A graphical desktop for OpenComputers.\n\n• Launch apps from the dock; right-click for menus.\n• Move and maximize windows.\n• Install RYKEA, Pixels and games in the Store.\n• Store and RYKEA access depends on your region.",
    catalog = "Catalog", installed = "Installed", development = "Developer",
    signIn = "Sign in", signOut = "Sign out", register = "Register",
    install = "Install", launch = "Launch", remove = "Remove",
    access = "Regional access", regions = "Regions", region = "Region", language = "Language",
  },
  zh = {
    welcome = "欢迎使用", openStore = "打开商店", understood = "知道了",
    intro = "OpenComputers 图形桌面。\n\n• 从程序坞启动应用，右键打开菜单。\n• 移动或最大化窗口。\n• 在商店安装 RYKEA、像素和游戏。\n• 商店和 RYKEA 的访问取决于地区。",
    catalog = "目录", installed = "已安装", development = "开发者",
    signIn = "登录", signOut = "退出", register = "注册",
    install = "安装", launch = "运行", remove = "删除",
    access = "地区访问", regions = "地区", region = "地区", language = "语言",
  },
}

local Locale = {}
function Locale.t(key)
  local lang = texts[System.settings.language] or texts.ru
  return lang[key] or texts.ru[key] or key
end
return Locale]]},
  {"/Libraries/MineCompat.lua", [[
-- ============================================================
--  CubeOS :: MineCompat — запуск игр, написанных под MineOS
--
--  Игра выполняется в собственной корутине, поэтому привычный
--  цикл `while true do ... event.pull() ... end` работает:
--  корутина приостанавливается, а Desktop продолжает работать
--  и доставляет события (мышь, клавиатура, таймеры).
--
--  Что поддерживается:
--    require("GUI")       — workspace, container, button, label,
--                           addChild, draw, event, onTouch
--    require("event")     — pull/filter, push, listen, ignore
--    require("Filesystem")/require("filesystem") — MineOS API и алиас OpenOS
--    require("term")      — write, clear, println
--    require("GPU") и component.gpu — GPU поверх кадрового буфера
--    computer.pullSignal, os.sleep, os.exit
--
--  Ограничения: image.load, сложные виджеты GUI.* (radio,
--  comboBox, imageData) и многопоточность event.timer не
--  реализованы — перепишите их на нативный GUI CubeOS.
-- ============================================================
local Screen = require("Screen")
local System = require("System")
local GUIC = require("GUI")
local MineLibs = require("MineLibs")
local unicode = unicode
local computer = computer
local floor, min, max = math.floor, math.min, math.max
local C = GUIC.color

local MC = {}

-- ------------------------------------------------------------ виджеты в стиле MineOS
local Item = GUIC.class()
MC.Item = Item

function Item:addChild(child)
  return self:add(child)
end

function Item:move(dx, dy)
  self.x, self.y = self.x + dx, self.y + dy
  return self
end

function Item:drawSelf(ax, ay)
  if self.kind == "label" then
    if self.bg then Screen.rect(ax, ay, self.w, 1, GUIC.rc(self.bg, nil), nil, " ") end
    Screen.text(ax, ay, GUIC.rc(self.fg, C.text), GUIC.fit(tostring(self.text or ""), self.w))
  elseif self.kind == "button" then
    local bg, fg
    if self.style == "primary" or self.pressed then
      bg, fg = C.accent, C.accentText
    elseif self.style == "danger" then
      bg, fg = self.pressed and C.accent or C.danger, 0xFFFFFF
    else
      bg, fg = self.pressed and C.accent or C.button, self.pressed and C.accentText or C.buttonText
    end
    Screen.rect(ax, ay, self.w, self.h, bg, nil, " ")
    local t = GUIC.fit(tostring(self.text or ""), max(1, self.w - 1))
    Screen.text(ax + floor((self.w - unicode.len(t)) / 2), ay + floor(self.h / 2), fg, t)
  end
end

-- ------------------------------------------------------------ запуск игры
--- ctx — контекст приложения CubeOS, source — текст игры, meta — {title, w, h, fw, fh}
function MC.run(ctx, source, meta)
  meta = meta or {}
  local Desktop = ctx.Desktop
  local win = ctx.window(meta.w or 66, meta.h or 20, meta.title or ctx.title or "Игра")
  local content = win.content
  local CW, CH = content.w, content.h
  local screenAddr = component.list("screen")()
  local keyboardAddr = component.list("keyboard")()

  -- Предварительные объявления (используются замыканиями ws:addChild и др.)
  local mineRoots, mineWindows, wsRoot
  local systemShim

  -- ---------------------------------------------------- кадровый буфер игры
  local fw, fh = meta.fw or CW, meta.fh or CH
  local frame, curFg, curBg
  local function allocFrame()
    frame = {}
    for y = 1, fh do
      local row = {}
      for x = 1, fw do row[x] = {ch = " ", fg = 0xFFFFFF, bg = 0x000000} end
      frame[y] = row
    end
    curFg, curBg = 0xFFFFFF, 0x000000
  end
  allocFrame()

  local function markDirty() Desktop.dirty = true end

  local function writeAt(x, y, text, vertical)
    local chars = {}
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    for i = 1, #chars do
      local cx = vertical and x or (x + i - 1)
      local cy = vertical and (y + i - 1) or y
      if cx >= 1 and cx <= fw and cy >= 1 and cy <= fh then
        frame[cy][cx] = {ch = chars[i], fg = curFg, bg = curBg}
      end
    end
  end

  local function fillRect(x, y, w, h, ch)
    ch = tostring(ch or " "):sub(1, 1)
    if ch == "" then ch = " " end
    for yy = max(1, y), min(fh, y + h - 1) do
      for xx = max(1, x), min(fw, x + w - 1) do
        frame[yy][xx] = {ch = ch, fg = curFg, bg = curBg}
      end
    end
  end

  local gpu = {}
  function gpu.setResolution(w, h)
    fw, fh = max(1, floor(w)), max(1, floor(h))
    allocFrame()
    return true
  end
  function gpu.getResolution() return fw, fh end
  function gpu.maxResolution() return CW, CH end
  function gpu.set(x, y, text, vertical) writeAt(floor(x), floor(y), text, vertical) markDirty() return true end
  function gpu.fill(x, y, w, h, ch) fillRect(floor(x), floor(y), floor(w), floor(h), ch) markDirty() return true end
  function gpu.get(x, y)
    local cx, cy = floor(x), floor(y)
    if cx < 1 or cy < 1 or cx > fw or cy > fh then return nil, "index out of bounds" end
    local cell = frame[cy][cx]
    return cell.ch, cell.fg, cell.bg
  end
  function gpu.copy() return true end
  function gpu.bind() return true end
  function gpu.getForeground() return curFg, false end
  function gpu.getBackground() return curBg, false end
  function gpu.setForeground(c) local old = curFg curFg = (c or 0) % 0x1000000 return old, nil end
  function gpu.setBackground(c) local old = curBg curBg = (c or 0) % 0x1000000 return old, nil end
  function gpu.getDepth() return 8 end
  function gpu.maxDepth() return 8 end
  function gpu.setDepth() return true end

  -- ---------------------------------------------------- виджет-поверхность
  local Surface = GUIC.class()
  local surface
  local state = {win = win}

  function Surface:drawSelf(ax, ay)
    -- Оконные MineOS-приложения рисуют через MineLayer/screen напрямую;
    -- GPU-буфер здесь не нужен и иначе стёр бы верхнюю часть окна.
    if #mineWindows > 0 then return end
    for y = 1, fh do
      local row = frame[y]
      for x = 1, fw do
        local cell = row[x]
        Screen.rect(ax + x - 1, ay + y - 1, 1, 1, cell.bg, cell.fg, cell.ch)
      end
    end
  end

  -- ---------------------------------------------------- очередь и корутина
  local queue, waitKind, deadline = {}, nil, nil
  local co, finished, usedPull = nil, false, false

  local function findHit(node, dx, dy, cx, cy)
    local x0, y0 = dx + node.x, dy + node.y
    if cx >= x0 and cx < x0 + node.w and cy >= y0 and cy < y0 + node.h then
      for i = #node.children, 1, -1 do
        local hit = findHit(node.children[i], x0 - 1, y0 - 1, cx, cy)
        if hit then return hit end
      end
      return node
    end
    return nil
  end

  -- workspace и его модули ------------------------------------------------
  local ws = {children = {}, width = CW, height = CH}
  function ws:addChild(o)
    self.children[#self.children + 1] = o
    if o and o._mine then
      -- MineOS-объект: рендерится через MineLayer (абсолютные координаты)
      if wsRoot then wsRoot:addChild(o) end
    else
      content:add(o)
    end
    return o
  end
  function ws:removeChild(o)
    if o and o._mine and wsRoot then wsRoot:removeChild(o) else content:remove(o) end
  end
  function ws:draw() markDirty() end
  function ws:reposition() end
  function ws:resize() end
  function ws:event(name, ...)
    -- Срабатывание виджетов — только на touch (как в MineOS),
    -- drag/drop игнорируем, чтобы кнопки не наживались дважды.
    if name == "touch" then
      local _, x, y, button = ...
      for i = #self.children, 1, -1 do
        local node = findHit(self.children[i], 0, 0, x or 0, y or 0)
        if node and node.onTouch then
          local ok, err = pcall(node.onTouch, node, x, y, button)
          if not ok then Desktop.reportError(err) end
          return true
        end
      end
    elseif name == "scroll" then
      local _, x, y, dir = ...
      for i = #self.children, 1, -1 do
        local node = findHit(self.children[i], 0, 0, x or 0, y or 0)
        if node and node.onScroll then
          local ok, err = pcall(node.onScroll, node, dir)
          if not ok then Desktop.reportError(err) end
          return true
        end
      end
    end
    return false
  end

  local function makeNode(kind, x, y, w, h, text)
    local node = GUIC.new(Item, x, y, w or 1, h or 1)
    node.kind, node.text = kind, text
    return node
  end

  -- ---------------------------------------------------------- MineOS GUI-объекты
  -- В MineOS у объектов localX/localY — координаты относительно родителя,
  -- а x/y — абсолютные экранные (вычисляются при отрисовке). Игры вроде
  -- MineBlock рисуют через screen.drawRectangle(canvas.x, ...) и читают
  -- canvas.x в eventHandler, поэтому x/y обязаны быть абсолютными.
  mineRoots = {}
  mineWindows = {}

  local function newMineObject(x, y, w, h)
    local o = {
      localX = x or 1, localY = y or 1,
      x = x or 1, y = y or 1,
      width = w or 1, height = h or 1,
      children = {}, hidden = false, disabled = false,
      _mine = true,
    }
    function o:addChild(child)
      self.children[#self.children + 1] = child
      child.parent = self
      markDirty()
      return child
    end
    function o:removeChild(child)
      for i, c in ipairs(self.children) do
        if c == child then table.remove(self.children, i) break end
      end
      markDirty()
    end
    function o:remove()
      if self._isMineWindow then
        for i, mw in ipairs(mineWindows) do
          if mw == self then table.remove(mineWindows, i) break end
        end
        for i, r in ipairs(mineRoots) do
          if r == self then table.remove(mineRoots, i) break end
        end
        win.tickInterval = nil
        win:close()
        return
      end
      if self.parent then self.parent:removeChild(self) end
      markDirty()
    end
    return o
  end

  local function drawMineObject(o, ax, ay)
    if o.hidden then return end
    o.x, o.y = ax, ay
    if o.draw then
      local ok, err = pcall(o.draw, o)
      if not ok then Desktop.reportError(err) end
    elseif o.drawSelf then
      local ok, err = pcall(o.drawSelf, o, ax, ay)
      if not ok then Desktop.reportError(err) end
    end
    for _, child in ipairs(o.children) do
      drawMineObject(child, ax + (child.localX or 1) - 1, ay + (child.localY or 1) - 1)
    end
  end

  -- Корневой контейнер для объектов, добавленных прямо в workspace
  wsRoot = newMineObject(1, 1, CW, CH)
  mineRoots[1] = wsRoot

  local MineLayer = GUIC.class()
  function MineLayer:drawSelf(ax, ay)
    for _, root in ipairs(mineRoots) do
      drawMineObject(root, ax + (root.localX or 1) - 1, ay + (root.localY or 1) - 1)
    end
  end
  local mineLayerWidget = content:add(GUIC.new(MineLayer, 1, 1, CW, CH))

  local gui = {}
  function gui.workspace() return ws end
  function gui.container(x, y, w, h) return makeNode("container", x, y, w, h) end
  function gui.button(x, y, w, h, text) return makeNode("button", x, y, w, h, text) end

  --- GUI.label: MineOS (x, y, width, height, textColor, text) либо
  --- упрощённый (x, y, text, fg, bg, width) — различаем по типу 3-го аргумента.
  function gui.label(x, y, a3, a4, a5, a6)
    if type(a3) == "number" then
      local node = newMineObject(x, y, a3, a4 or 1)
      node.textColor = a5
      node.text = a6 or ""
      node.drawSelf = function(self, ax, ay)
        if self.backgroundColor then Screen.rect(ax, ay, self.width, self.height, self.backgroundColor, nil, " ") end
        Screen.text(ax, ay, self.textColor or C.text, GUIC.fit(tostring(self.text or ""), self.width), self.backgroundColor)
      end
      return node
    end
    local node = makeNode("label", x, y, a6 or max(1, unicode.len(tostring(a3 or ""))), 1, a3)
    node.fg, node.bg = a4, a5
    return node
  end

  --- GUI.object(x, y, w, h) — произвольный объект с пользовательским .draw(self)
  function gui.object(x, y, w, h)
    return newMineObject(x, y, w, h)
  end

  --- GUI.filledWindow(x, y, w, h, bgColor) — окно MineOS поверх окна CubeOS
  function gui.filledWindow(x, y, w, h, bgColor)
    local mw = newMineObject(x, y, w, h)
    mw._isMineWindow = true
    mw.backgroundColor = bgColor or C.win
    mw.backgroundPanel = {width = w, height = h, localX = 1, localY = 1, color = bgColor or C.win}
    mw.title = ctx.title or "MineOS"
    mw.drawSelf = function(self, ax, ay)
      local bp = self.backgroundPanel
      Screen.rect(ax, ay, bp.width or self.width, bp.height or self.height, bp.color or self.backgroundColor, nil, " ")
    end
    mineWindows[#mineWindows + 1] = mw
    mineRoots[#mineRoots + 1] = mw
    -- Подгоняем окно CubeOS под размер MineOS-окна и центрируем НАД доком,
    -- иначе низ окна (статус-строка, хотбар) перекрывается доком.
    local sw, sh = Screen.size()
    local dockH = (Desktop.dockHeight and Desktop.dockHeight()) or 5
    local tw = min(w, sw)
    local th = min(h, sh - dockH - 1)
    win:resize(tw, th)
    win.x = max(1, floor((sw - tw) / 2) + 1)
    win.y = max(2, floor((sh - dockH - th) / 2) + 1)
    mineLayerWidget.w, mineLayerWidget.h = win.content.w, win.content.h
    if surface then surface.w, surface.h = win.content.w, win.content.h end
    win.tickInterval = 0.08
    markDirty()
    return mw
  end
  gui.window = gui.filledWindow

  function gui.rectangle(x, y, w, h, bg)
    local node = makeNode("container", x, y, w, h)
    node.bg = bg
    node.drawSelf = function(self, ax, ay) Screen.rect(ax, ay, self.w, self.h, GUIC.rc(self.bg, nil), nil, " ") end
    return node
  end
  function gui.calculateTextPosition() return 1, 1 end

  -- system.addWindow(window) → workspace, window, menu (меню в строке CubeOS)
  systemShim = setmetatable({}, {__index = System})
  function systemShim.addWindow(mw)
    local menu = {}
    win.menu = win.menu or {}
    function menu:addContextMenuItem(title)
      local sub = {title = title, entries = {}}
      function sub:addItem(text)
        local item = {text = text}
        item.action = function() if item.onTouch then item.onTouch(item) end end
        self.entries[#self.entries + 1] = item
        return item
      end
      function sub:addSeparator()
        self.entries[#self.entries + 1] = {separator = true}
      end
      win.menu[#win.menu + 1] = {title = title, items = function() return sub.entries end}
      markDirty()
      return sub
    end
    return ws, mw, menu
  end
  function systemShim.getCurrentScript() return ctx.path or "/" end
  function systemShim.getLocalization() return {} end
  function systemShim.parseArguments(...) return {...}, {} end

  -- event -----------------------------------------------------------------
  local function yieldPull(timeout)
    if coroutine.isyieldable() then
      return coroutine.yield("pull", timeout)
    end
    return nil
  end

  local event = {}
  local eventHandlers = {}
  function event.pull(filter, timeout)
    if type(filter) == "number" then filter, timeout = nil, filter end
    while true do
      local a, b, cc, d, e = yieldPull(timeout)
      if filter == nil or a == filter then return a, b, cc, d, e end
      if a == nil then return nil end
    end
  end
  function event.push(...) if coroutine.isyieldable() then coroutine.yield("push", ...) end end
  function event.addHandler(handler)
    if type(handler) ~= "function" then return nil, "function expected" end
    eventHandlers[#eventHandlers + 1] = handler
    return true
  end
  function event.removeHandler(handler)
    for i = #eventHandlers, 1, -1 do
      if eventHandlers[i] == handler then table.remove(eventHandlers, i) end
    end
    return true
  end
  function event.listen() return true end
  function event.ignore() return true end
  function event.register() return true end
  function event.ignoreHandlers() end
  function event.skip() end
  function event.pullMultiple(timeout) return event.pull(nil, timeout) end
  function event._emit(...)
    local args = table.pack(...)
    for _, handler in ipairs(eventHandlers) do
      local ok, err = pcall(handler, table.unpack(args, 1, args.n))
      if not ok then Desktop.reportError(err) end
    end
  end

  -- MineOS Keyboard module (LWJGL/OpenComputers scan codes).
  local pressedCodes = {}
  local keyboard = {
    LEFT_CONTROL = 29, RIGHT_CONTROL = 157,
    LEFT_SHIFT = 42, RIGHT_SHIFT = 54,
    LEFT_ALT = 56, RIGHT_ALT = 184,
    COMMAND_KEY = 219, WINDOWS_KEY = 219,
    ONE = 2, TWO = 3, THREE = 4, FOUR = 5, FIVE = 6,
    SIX = 7, SEVEN = 8, EIGHT = 9, NINE = 10, ZERO = 11,
    A = 30, B = 48, C = 46, D = 32, E = 18, F = 33,
    G = 34, H = 35, I = 23, J = 36, K = 37, L = 38,
    M = 50, N = 49, O = 24, P = 25, Q = 16, R = 19,
    S = 31, T = 20, U = 22, V = 47, W = 17, X = 45,
    Y = 21, Z = 44,
    MINUS = 12, PLUS = 13, BACKSPACE = 14, TAB = 15,
    SINGLE_QUOTE = 26, EXCLAMATION = 27, ENTER = 28,
    OPEN_QUOTE = 40, COMMA = 51, DOT = 52, SPACE = 57,
    UP = 200, DOWN = 208, RIGHT = 205, LEFT = 203,
  }
  function keyboard.isKeyDown(code) return pressedCodes[code] or false end
  function keyboard.isControl(code)
    return type(code) == "number" and (code < 32 or (code >= 127 and code <= 159))
  end
  function keyboard.isAltDown() return pressedCodes[56] or pressedCodes[184] or false end
  function keyboard.isControlDown() return pressedCodes[29] or pressedCodes[157] or false end
  function keyboard.isShiftDown() return pressedCodes[42] or pressedCodes[54] or false end
  function keyboard.isCommandDown() return pressedCodes[keyboard.COMMAND_KEY] or false end
  event.addHandler(function(name, _, _, code)
    if name == "key_down" then pressedCodes[code] = true
    elseif name == "key_up" then pressedCodes[code] = nil end
  end)

  -- MineOS Filesystem ------------------------------------------------------
  -- MineOS uses the case-sensitive module name "Filesystem" and its own
  -- buffered file-handle API. CubeOS has one root volume, so setProxy keeps
  -- that volume (or switches to a supplied filesystem component proxy).
  local fs = System.fs
  local filesystem = {}

  local function canonical(path)
    path = tostring(path or ""):gsub("\\", "/")
    local absolute = path:sub(1, 1) == "/"
    local parts = {}
    for part in path:gmatch("[^/]+") do
      if part == ".." then
        if #parts > 0 then table.remove(parts) end
      elseif part ~= "." and part ~= "" then
        parts[#parts + 1] = part
      end
    end
    local result = table.concat(parts, "/")
    if absolute then result = "/" .. result end
    return result == "" and (absolute and "/" or ".") or result
  end

  local function readWhole(path)
    local handle, err = fs.open(path, "r")
    if not handle then return nil, err end
    local chunks = {}
    while true do
      local chunk, reason = fs.read(handle, math.huge)
      if chunk then
        chunks[#chunks + 1] = chunk
      else
        fs.close(handle)
        if reason then return nil, reason end
        return table.concat(chunks)
      end
    end
  end

  local function writeWhole(path, data, append)
    local handle, err = fs.open(path, append and "a" or "w")
    if not handle then return nil, err end
    local ok, reason = fs.write(handle, data)
    fs.close(handle)
    if not ok then return nil, reason end
    return true
  end

  function filesystem.setProxy(proxy)
    if type(proxy) == "string" then
      local ok, value = pcall(component.proxy, proxy)
      if not ok or not value then return nil, "no such filesystem" end
      proxy = value
    end
    if type(proxy) ~= "table" then return nil, "filesystem proxy expected" end
    local old = fs
    fs = proxy
    return true, old
  end

  function filesystem.exists(p) return fs.exists(canonical(p)) end
  function filesystem.isDirectory(p) return fs.isDirectory(canonical(p)) end
  function filesystem.list(p)
    local ok, result, reason = pcall(fs.list, canonical(p))
    if not ok then return nil, result end
    return result, reason
  end
  function filesystem.makeDirectory(p) return fs.makeDirectory(canonical(p)) end
  function filesystem.remove(p) return fs.remove(canonical(p)) end
  function filesystem.rename(a, b) return fs.rename(canonical(a), canonical(b)) end
  function filesystem.size(p) return fs.size(canonical(p)) end
  function filesystem.lastModified(p) return fs.lastModified(canonical(p)) end
  function filesystem.spaceUsed() return fs.spaceUsed() end
  function filesystem.spaceTotal() return fs.spaceTotal() end
  function filesystem.getFreeSpace() return max(0, fs.spaceTotal() - fs.spaceUsed()) end
  function filesystem.readAll(p) return readWhole(canonical(p)) end
  function filesystem.read(p) return readWhole(canonical(p)) end

  function filesystem.write(p, ...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    return writeWhole(canonical(p), table.concat(values), false)
  end

  function filesystem.append(p, ...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    return writeWhole(canonical(p), table.concat(values), true)
  end

  function filesystem.readLines(p)
    local data, err = readWhole(canonical(p))
    if not data then return nil, err end
    local lines = {}
    for line in (data .. "\n"):gmatch("(.-)\n") do
      line = line:gsub("\r$", "")
      if line ~= "" or #lines > 0 or data ~= "" then lines[#lines + 1] = line end
    end
    return lines
  end

  function filesystem.readTable(p)
    local data, err = readWhole(canonical(p))
    if not data then return nil, err end
    local ok, value = pcall(System.unserialize, data)
    if ok and value ~= nil then return value end
    local loaded, result = pcall(System.loadData, canonical(p))
    if loaded and result ~= nil then return result end
    return nil, "invalid serialized table"
  end

  function filesystem.writeTable(p, value)
    local ok, data = pcall(System.serialize, value)
    if not ok then return nil, tostring(data) end
    return writeWhole(canonical(p), data, false)
  end

  function filesystem.canonical(p) return canonical(p) end
  function filesystem.concat(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    return canonical(table.concat(values, "/"))
  end

  function filesystem.path(p)
    p = tostring(p or ""):gsub("\\", "/")
    local trailing = p:sub(-1) == "/"
    local clean = canonical(p):gsub("/+$", "")
    local parent = clean:match("^(.*)/[^/]*$")
    if not parent then parent = p:sub(1, 1) == "/" and "/" or "" end
    if parent ~= "/" then parent = parent:gsub("/+$", "") .. "/" end
    if trailing and clean == "" then return "/" end
    return parent
  end

  function filesystem.name(p)
    p = tostring(p or ""):gsub("\\", "/")
    local trailing = p:sub(-1) == "/"
    local clean = p:gsub("/+$", "")
    local name = clean:match("([^/]*)$") or clean
    return trailing and (name .. "/") or name
  end

  function filesystem.extension(p)
    local name = filesystem.name(p):gsub("/$", "")
    local ext = name:match("(%.[^%.]+)$")
    return ext or ""
  end

  function filesystem.hideExtension(p)
    local ext = filesystem.extension(p)
    if ext == "" then return p end
    return tostring(p):sub(1, #tostring(p) - #ext)
  end

  function filesystem.isHidden(p)
    return filesystem.name(p):gsub("/$", ""):sub(1, 1) == "."
  end

  function filesystem.removeSlashes(p)
    return canonical(p)
  end

  function filesystem.get(p) return fs, canonical(p) end
  function filesystem.proxy(filter)
    local ok, proxy = pcall(component.proxy, filter)
    if ok then return proxy end
    return nil, tostring(proxy)
  end

  function filesystem.mounts()
    local yielded = false
    return function()
      if yielded then return nil end
      yielded = true
      return fs, "/"
    end
  end

  function filesystem.mount(proxy, path)
    if path == "/" and (proxy == fs or (type(proxy) == "table" and proxy.address == fs.address)) then
      return true
    end
    return nil, "MineCompat exposes one root filesystem"
  end

  function filesystem.unmount(proxyOrPath)
    if proxyOrPath == "/" or proxyOrPath == fs or (type(proxyOrPath) == "table" and proxyOrPath.address == fs.address) then
      return nil, "cannot unmount the CubeOS root filesystem"
    end
    return false
  end

  function filesystem.open(p, mode)
    local handle, err = fs.open(canonical(p), mode or "r")
    if not handle then return nil, err end
    local closed = false
    local wrap = {handle = handle}

    function wrap:close()
      if closed then return true end
      closed = true
      return fs.close(handle)
    end

    function wrap:seek(whence, offset)
      if closed then return nil, "file is closed" end
      if type(whence) == "number" then offset, whence = whence, "cur" end
      return fs.seek(handle, whence or "cur", offset or 0)
    end

    function wrap:readString(count)
      if closed then return nil end
      return fs.read(handle, count or 1)
    end

    function wrap:readBytes(count, littleEndian)
      if closed then return nil end
      local bytes = fs.read(handle, count or 1)
      if not bytes then return nil end
      local value = 0
      if littleEndian then
        for i = #bytes, 1, -1 do value = value * 256 + bytes:byte(i) end
      else
        for i = 1, #bytes do value = value * 256 + bytes:byte(i) end
      end
      return value
    end

    function wrap:readUnicodeChar()
      local first = self:readString(1)
      if not first then return nil end
      local byte = first:byte(1)
      local count = byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4
      if count == 1 then return first end
      return first .. (fs.read(handle, count - 1) or "")
    end

    function wrap:readLine()
      if closed then return nil end
      local chars = {}
      while true do
        local ch = fs.read(handle, 1)
        if not ch then
          if #chars == 0 then return nil end
          break
        end
        if ch == "\n" then break end
        chars[#chars + 1] = ch
      end
      return table.concat(chars):gsub("\r$", "")
    end

    function wrap:readAll()
      if closed then return nil, "file is closed" end
      local parts = {}
      while true do
        local chunk, reason = fs.read(handle, math.huge)
        if chunk then
          parts[#parts + 1] = chunk
        else
          if reason then return nil, reason end
          return table.concat(parts)
        end
      end
    end

    function wrap:read(count) return self:readString(count) end
    function wrap:write(...)
      if closed then return nil, "file is closed" end
      local values = {...}
      for i = 1, #values do values[i] = tostring(values[i]) end
      return fs.write(handle, table.concat(values))
    end

    function wrap:writeBytes(...)
      if closed then return nil, "file is closed" end
      local values, bytes = {...}, {}
      for i = 1, #values do bytes[i] = string.char((tonumber(values[i]) or 0) % 256) end
      return fs.write(handle, table.concat(bytes))
    end

    return wrap
  end

  -- term ------------------------------------------------------------------
  local term = {cursorX = 1, cursorY = 1}
  function term.write(s)
    writeAt(term.cursorX, term.cursorY, tostring(s))
    term.cursorX = term.cursorX + unicode.len(tostring(s))
    markDirty()
  end
  function term.println(s)
    term.write(tostring(s) .. "\n")
    term.cursorX = 1
    term.cursorY = min(fh, term.cursorY + 1)
  end
  function term.clear()
    fillRect(1, 1, fw, fh, " ")
    term.cursorX, term.cursorY = 1, 1
    markDirty()
  end
  function term.setCursor(x, y) term.cursorX, term.cursorY = x, y end
  function term.getCursor() return term.cursorX, term.cursorY end
  function term.read() return "" end
  term.print = term.println

  -- computer / component / os ---------------------------------------------
  local realComputer = computer
  local computerShim = setmetatable({}, {__index = realComputer})
  function computerShim.pullSignal(timeout) return yieldPull(timeout) end
  function computerShim.pushSignal(...)
    if coroutine.isyieldable() then coroutine.yield("push", ...) else realComputer.pushSignal(...) end
  end

  local componentShim = setmetatable({gpu = gpu}, {__index = component})

  local osShim = setmetatable({}, {__index = os})
  function osShim.sleep(sec)
    if coroutine.isyieldable() then return coroutine.yield("sleep", sec or 0) end
  end
  function osShim.exit(code)
    if coroutine.isyieldable() then coroutine.yield("exit", code) end
    finished = true
  end

  -- ---------------------------------------------------- драйвер корутины
  local function onExit()
    waitKind, deadline = nil, nil
    finished = true
    if usedPull then
      win.tickInterval = nil
      win:close()
    else
      -- Событийное MineOS-приложение (MineBlock): чанк завершился, но окно
      -- живёт и получает события/тики через window.eventHandler.
      local hasEventHandler = false
      for _, mw in ipairs(mineWindows) do if mw.eventHandler then hasEventHandler = true end end
      win.tickInterval = hasEventHandler and 0.08 or nil
      markDirty()
    end
  end

  local function resumeGame(...)
    if not co or coroutine.status(co) == "dead" then return end
    local args = table.pack(...)
    while true do
      local res = table.pack(coroutine.resume(co, table.unpack(args, 1, args.n)))
      args = table.pack()
      local ok, kind = res[1], res[2]
      if not ok then
        waitKind, deadline = nil, nil
        finished = true
        win.tickInterval = nil
        Desktop.reportError("Игра: " .. tostring(kind))
        return
      end
      if coroutine.status(co) == "dead" then onExit() return end

      if kind == "pull" then
        usedPull = true
        if #queue > 0 then
          args = table.remove(queue, 1)
        else
          waitKind = "pull"
          local t = res[3]
          deadline = (type(t) == "number") and (realComputer.uptime() + t) or nil
          win.tickInterval = deadline and 0.05 or nil
          return
        end
      elseif kind == "sleep" then
        waitKind = "sleep"
        deadline = realComputer.uptime() + (res[3] or 0)
        win.tickInterval = 0.05
        return
      elseif kind == "push" then
        -- event.push(): игра кладёт событие в свою очередь и продолжает
        queue[#queue + 1] = table.pack(table.unpack(res, 3, res.n))
      elseif kind == "exit" then
        onExit()
        return
      else
        waitKind = nil
        return
      end
    end
  end

  local function pushEvent(...)
    if not co then return end
    local packed = table.pack(...)
    event._emit(table.unpack(packed, 1, packed.n))
    -- MineOS-приложения с окном получают события через window.eventHandler
    for i = #mineWindows, 1, -1 do
      local mw = mineWindows[i]
      if mw.eventHandler then
        local ok, err = pcall(mw.eventHandler, ws, mw, table.unpack(packed, 1, packed.n))
        if not ok then Desktop.reportError(err) end
        return
      end
    end
    if finished then
      ws:event(table.unpack(packed, 1, packed.n))
      return
    end
    if waitKind == "pull" then
      waitKind, deadline = nil, nil
      win.tickInterval = nil
      resumeGame(table.unpack(packed, 1, packed.n))
    else
      if #queue > 64 then table.remove(queue, 1) end
      queue[#queue + 1] = packed
    end
  end

  surface = content:add(GUIC.new(Surface, 1, 1, CW, CH))

  -- события окна ----------------------------------------------------------
  win.onKey = function(_, e)
    pushEvent("key_down", keyboardAddr, e.char or 0, e.code, "Player")
    return true
  end
  win.onKeyUp = function(_, e)
    pushEvent("key_up", keyboardAddr, e.char or 0, e.code, "Player")
    return true
  end
  win.onResize = function(_, w, contentH)
    for _, mw in ipairs(mineWindows) do
      mw.width, mw.height = w, contentH + 1
      if mw.onResize then
        local ok, err = pcall(mw.onResize, w, contentH + 1)
        if not ok then Desktop.reportError(err) end
      end
    end
    markDirty()
  end
  win.onTick = function()
    -- Событийные MineOS-приложения: eventHandler(nil) двигает физику/анимацию
    for i = #mineWindows, 1, -1 do
      local mw = mineWindows[i]
      if mw.eventHandler then
        local ok, err = pcall(mw.eventHandler, ws, mw, nil, nil, nil, nil, nil)
        if not ok then Desktop.reportError(err) end
        return true
      end
    end
    if waitKind and deadline and realComputer.uptime() >= deadline then
      local w = waitKind
      waitKind, deadline = nil, nil
      win.tickInterval = nil
      if w == "sleep" then resumeGame()
      else resumeGame(nil, nil, nil, nil, nil) end
    end
    return nil
  end
  function Surface:onEvent(e, ax, ay)
    local cx, cy = e.x - ax + 1, e.y - ay + 1
    -- MineOS-окна ждут абсолютные экранные координаты (canvas.x — абсолютный)
    local useAbs = #mineWindows > 0
    local px, py = cx, cy
    if useAbs then px, py = e.x, e.y end
    if e.type == "touch" then
      self:capture()
      pushEvent("touch", screenAddr, px, py, e.button, "Player")
      return true
    elseif e.type == "drag" or e.type == "drop" then
      pushEvent(e.type, screenAddr, px, py, e.button, "Player")
      return true
    elseif e.type == "scroll" then
      pushEvent("scroll", screenAddr, px, py, e.dir, "Player")
      return true
    end
    return false
  end

  -- ---------------------------------------------------- окружение игры
  local mods = {
    GUI = gui, GPU = gpu, Event = event, event = event,
    Keyboard = keyboard, keyboard = keyboard,
    Filesystem = filesystem, FileSystem = filesystem, filesystem = filesystem,
    term = term,
  }
  -- Ядро MineOS-совместимости имеет приоритет над общими библиотеками
  for name, module in pairs(MineLibs) do
    mods[name] = module
    mods[name:lower()] = module
  end
  mods.GUI = gui
  -- MineLibs.Filesystem реализует полный MineOS API; ядро совместимости
  -- использует его как filesystem, чтобы setProxy/readTable/open работали.
  mods.Filesystem = MineLibs.Filesystem or filesystem
  mods.FileSystem = mods.Filesystem
  mods.filesystem = mods.Filesystem
  mods.Event = event
  mods.event = event
  mods.Keyboard = keyboard
  mods.keyboard = keyboard
  mods.GPU = gpu
  mods.System = systemShim
  mods.system = systemShim
  mods.Computer = computerShim
  mods.computer = computerShim
  local function compatRequire(name)
    local m = mods[name] or mods[tostring(name):lower()]
    if m ~= nil then return m end
    return require(name)
  end

  local env = setmetatable({}, {__index = _G})
  env._G = env
  env.require = compatRequire
  env.component = componentShim
  env.computer = computerShim
  env.os = osShim
  env.event = event
  env.Keyboard = keyboard
  env.keyboard = keyboard
  env.term = term
  env.filesystem = filesystem
  env.Filesystem = filesystem
  for name, module in pairs(MineLibs) do
    env[name] = module
    env[name:lower()] = module
  end
  env.GUI = gui
  env.Filesystem = mods.Filesystem
  env.FileSystem = mods.Filesystem
  env.filesystem = mods.Filesystem
  env.Event = event
  env.event = event
  env.Keyboard = keyboard
  env.keyboard = keyboard
  env.GPU = gpu
  env.System = systemShim
  env.system = systemShim
  env.Computer = computerShim
  env.computer = computerShim
  env.GPU = gpu
  env.Desktop = Desktop
  env.GUI = gui
  env.workspace = ws
  env.print = function(...) term.println(table.concat({...}, "\t")) end

  local chunk, err = load(source, "=" .. (meta.title or "game"), "t", env)
  if not chunk then
    win:close()
    GUI.alert("Синтаксическая ошибка игры", tostring(err))
    return nil
  end

  Desktop.dirty = true
  co = coroutine.create(chunk)
  resumeGame()
  return win
end

return MC
]]},
  {"/Libraries/MineLibs.lua", [[
-- ============================================================
--  CubeOS :: MineLibs — стандартные библиотеки MineOS
--
--  Полноценные MineOS-игры (например, Mineblock) требуют модули
--  Unicode, Color, Text, Number, Component, Paths, Sides, Internet,
--  Image, Screen и System. Здесь они реализованы поверх ядра CubeOS
--  и передаются игре через MineCompat.require().
--
--  Модуль не модифицирует глобалы CubeOS — только то, что видит игра.
-- ============================================================
local Screen = require("Screen")
local System = require("System")
local GUI = require("GUI")
local JSON = require("JSON")
local HTTP = require("HTTP")
local unicode = unicode
local component = component
local computer = computer
local math, table, string = math, table, string
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local abs, cos, sin, sqrt = math.abs, math.cos, math.sin, math.sqrt

local M = {}

-- ------------------------------------------------------------ Unicode
local U = {}
for k, v in pairs(unicode) do U[k] = v end
function U.lower(s)
  local out = {}
  for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch:lower() end
  return table.concat(out)
end
function U.upper(s)
  local out = {}
  for ch in tostring(s):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch:upper() end
  return table.concat(out)
end
U.char = utf8 and utf8.char or U.char
function U.find(s, pattern, init, plain) return tostring(s):find(pattern, init, plain) end
function U.gmatch(s, pattern) return tostring(s):gmatch(pattern) end
function U.gsub(s, pattern, repl, n) return tostring(s):gsub(pattern, repl, n) end
function U.format(...) return string.format(...) end
function U.byte(s, i, j) return tostring(s):byte(i, j) end
function U.reverse(s) return unicode.reverse(s) end
M.Unicode = U
M.unicode = U

-- ------------------------------------------------------------ Filesystem (MineOS API)
-- Полная реализация поверх System.fs: easy methods, таблицы и дескрипторы.
local FS = {}
local function canonical(path)
  path = tostring(path or ""):gsub("\\", "/")
  local absolute = path:sub(1, 1) == "/"
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local result = table.concat(parts, "/")
  if absolute then result = "/" .. result end
  return result == "" and (absolute and "/" or ".") or result
end
local function readWhole(path)
  local handle, err = System.fs.open(path, "r")
  if not handle then return nil, err end
  local chunks = {}
  while true do
    local chunk, reason = System.fs.read(handle, math.huge)
    if chunk then chunks[#chunks + 1] = chunk
    else
      System.fs.close(handle)
      if reason then return nil, reason end
      return table.concat(chunks)
    end
  end
end
local function writeWhole(path, data, append)
  local handle, err = System.fs.open(path, append and "a" or "w")
  if not handle then return nil, err end
  local ok, reason = System.fs.write(handle, data)
  System.fs.close(handle)
  if not ok then return nil, reason end
  return true
end
function FS.setProxy(proxy)
  if proxy == nil then return nil, "filesystem proxy expected" end
  if type(proxy) == "string" then
    -- MineOS often passes a component address; accept both address and label.
    local ok, value = pcall(function()
      local p = component.proxy(proxy)
      if p then return p end
      for address, proxy2 in pairs(component.list("filesystem") or {}) do
        if address:sub(1, #proxy) == proxy then return component.proxy(address) end
      end
      return nil
    end)
    if not ok or not value then return nil, "no such filesystem" end
    proxy = value
  end
  if type(proxy) ~= "table" then return nil, "filesystem proxy expected" end
  -- MineCompat wraps the raw component with a proxy table, so no further
  -- component.proxy() call is needed — that would fail with "type proxy".
  return true
end
function FS.exists(path) return System.fs.exists(canonical(path)) end
function FS.isDirectory(path) return System.fs.isDirectory(canonical(path)) end
function FS.list(path)
  local ok, result, reason = pcall(System.fs.list, canonical(path))
  if not ok then return nil, result end
  return result, reason
end
function FS.makeDirectory(path) return System.fs.makeDirectory(canonical(path)) end
function FS.remove(path) return System.fs.remove(canonical(path)) end
function FS.rename(a, b) return System.fs.rename(canonical(a), canonical(b)) end
function FS.copy(a, b) return System.copy(canonical(a), canonical(b)) end
function FS.size(path) return System.fs.size(canonical(path)) end
function FS.lastModified(path) return System.fs.lastModified(canonical(path)) end
function FS.spaceUsed() return System.fs.spaceUsed() end
function FS.spaceTotal() return System.fs.spaceTotal() end
function FS.getFreeSpace() return max(0, System.fs.spaceTotal() - System.fs.spaceUsed()) end
function FS.readAll(path) return readWhole(canonical(path)) end
FS.read = FS.readAll
function FS.write(path, ...)
  local parts = {...}
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  return writeWhole(canonical(path), table.concat(parts), false)
end
function FS.append(path, ...)
  local parts = {...}
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  return writeWhole(canonical(path), table.concat(parts), true)
end
function FS.readLines(path)
  local data, err = readWhole(canonical(path))
  if not data then return nil, err end
  local lines = {}
  for line in (data .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("\r$", "")
    if line ~= "" or #lines > 0 or data ~= "" then lines[#lines + 1] = line end
  end
  return lines
end
function FS.readTable(path)
  local data = readWhole(canonical(path))
  if not data then return nil, "file not found" end
  local ok, value = pcall(System.unserialize, data)
  if ok and value ~= nil then return value end
  return nil, "invalid serialized table"
end
function FS.writeTable(path, value)
  local ok, data = pcall(System.serialize, value)
  if not ok then return nil, tostring(data) end
  return writeWhole(canonical(path), data, false)
end
function FS.canonical(path) return canonical(path) end
function FS.concat(...)
  local parts = {...}
  for i = 1, #parts do parts[i] = tostring(parts[i]) end
  return canonical(table.concat(parts, "/"))
end
function FS.path(path)
  path = tostring(path or ""):gsub("\\", "/")
  local clean = canonical(path):gsub("/+$", "")
  local parent = clean:match("^(.*)/[^/]*$")
  if not parent then parent = path:sub(1, 1) == "/" and "/" or "" end
  if parent ~= "/" then parent = parent:gsub("/+$", "") .. "/" end
  return parent
end
function FS.name(path)
  path = tostring(path or ""):gsub("\\", "/")
  local trailing = path:sub(-1) == "/"
  local clean = path:gsub("/+$", "")
  local name = clean:match("([^/]*)$") or clean
  return trailing and (name .. "/") or name
end
function FS.extension(path)
  local ext = FS.name(path):gsub("/$", ""):match("(%.[^%.]+)$")
  return ext or ""
end
function FS.hideExtension(path)
  local ext = FS.extension(path)
  return ext == "" and path or tostring(path):sub(1, #tostring(path) - #ext)
end
function FS.isHidden(path) return FS.name(path):gsub("/$", ""):sub(1, 1) == "." end
function FS.removeSlashes(path) return canonical(path) end
function FS.get(path) return System.fs, canonical(path) end
function FS.proxy(filter)
  if type(filter) == "table" then return filter end
  if type(filter) == "string" then
    local ok, proxy = pcall(component.proxy, filter)
    if ok and proxy then return proxy end
  end
  return nil, "filesystem not found"
end
function FS.mounts()
  local done = false
  return function()
    if done then return nil end
    done = true
    return System.fs, "/"
  end
end
function FS.mount(proxy, path)
  if path == "/" then return true end
  return nil, "MineCompat exposes one root filesystem"
end
function FS.unmount() return false end
function FS.open(path, mode)
  local handle, err = System.fs.open(canonical(path), mode or "r")
  if not handle then return nil, err end
  local closed = false
  local wrap = {handle = handle}
  function wrap:close() if closed then return true end closed = true return System.fs.close(handle) end
  function wrap:seek(whence, offset)
    if closed then return nil, "file is closed" end
    if type(whence) == "number" then offset, whence = whence, "cur" end
    return System.fs.seek(handle, whence or "cur", offset or 0)
  end
  function wrap:readString(count) if closed then return nil end return System.fs.read(handle, count or 1) end
  function wrap:read(count) return self:readString(count) end
  function wrap:readBytes(count, little)
    local bytes = self:readString(count or 1)
    if not bytes then return nil end
    local value = 0
    if little then for i = #bytes, 1, -1 do value = value * 256 + bytes:byte(i) end
    else for i = 1, #bytes do value = value * 256 + bytes:byte(i) end end
    return value
  end
  function wrap:readLine()
    if closed then return nil end
    local chars = {}
    while true do
      local ch = System.fs.read(handle, 1)
      if not ch then if #chars == 0 then return nil end break end
      if ch == "\n" then break end
      chars[#chars + 1] = ch
    end
    return table.concat(chars):gsub("\r$", "")
  end
  function wrap:readAll()
    if closed then return nil, "file is closed" end
    local parts = {}
    while true do
      local chunk, reason = System.fs.read(handle, math.huge)
      if chunk then parts[#parts + 1] = chunk
      else if reason then return nil, reason end return table.concat(parts) end
    end
  end
  function wrap:readUnicodeChar()
    local first = self:readString(1)
    if not first then return nil end
    local b = first:byte(1)
    local count = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    return first .. (self:readString(count - 1) or "")
  end
  function wrap:write(...)
    if closed then return nil, "file is closed" end
    local parts = {...}
    for i = 1, #parts do parts[i] = tostring(parts[i]) end
    return System.fs.write(handle, table.concat(parts))
  end
  function wrap:writeBytes(...)
    local parts, bytes = {...}, {}
    for i = 1, #parts do bytes[i] = string.char((tonumber(parts[i]) or 0) % 256) end
    return self:write(table.concat(bytes))
  end
  return wrap
end
M.Filesystem = FS
M.filesystem = FS
M.FileSystem = FS

-- ------------------------------------------------------------ Component
local Comp = {}
function Comp.get(kind)
  if kind == "gpu" then
    local ok, proxy = pcall(function() return component.proxy(component.list("gpu")()) end)
    if ok and proxy then return proxy end
  end
  local addr = component.list(kind)()
  if addr then
    local ok, proxy = pcall(component.proxy, addr)
    if ok and proxy then return proxy end
  end
  return nil, 'component with type "' .. kind .. '" doesn\'t exists'
end
function Comp.isAvailable(kind)
  if kind == "gpu" then return true end
  return component.list(kind)() and true or false
end
setmetatable(Comp, {
  __index = function(_, kind)
    local value = component[kind]
    if value ~= nil then return value end
    local proxy, reason = Comp.get(kind)
    if proxy then return proxy end
    error(reason)
  end,
})
M.Component = Comp
M.component = Comp

-- ------------------------------------------------------------ Color (MineOS palette)
local palette = {}
for i = 0, 255 do palette[i + 1] = ((i >> 5) & 7) * 36 * 65536 + ((i >> 2) & 7) * 36 * 256 + (i & 3) * 85 end
for i = 0, 15 do
  local v = floor(255 * (i + 1) / 17)
  palette[i + 1] = v * 65536 + v * 256 + v
end
local function to8Bit(rgb)
  local r, g, b = (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
  local best, bestD = 0, math.huge
  for i = 0, 255 do
    local c = palette[i + 1]
    local d = (r - ((c >> 16) & 255)) ^ 2 + (g - ((c >> 8) & 255)) ^ 2 + (b - (c & 255)) ^ 2
    if d < bestD then bestD, best = d, i end
  end
  return best
end
local function to24Bit(c8) return palette[(c8 or 0) + 1] or 0 end
local function integerToRGB(rgb) return (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255 end
local function RGBToInteger(r, g, b) return ((r or 0) % 256) * 65536 + ((g or 0) % 256) * 256 + ((b or 0) % 256) end
local function RGBToHSB(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = max(r, g, b), min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = (g - b) / d % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h % 360, mx > 0 and d / mx or 0, mx
end
local function HSBToRGB(h, s, b)
  h, s, b = (h or 0) / 60, s or 0, b or 0
  local c = b * s
  local x = c * (1 - abs(h % 2 - 1))
  local r, g, bv = 0, 0, 0
  if h < 1 then r, g = c, x
  elseif h < 2 then r, g = x, c
  elseif h < 3 then g, bv = c, x
  elseif h < 4 then g, bv = x, c
  elseif h < 5 then r, bv = x, c
  else r, bv = c, x end
  local m = b - c
  return floor((r + m) * 255), floor((g + m) * 255), floor((bv + m) * 255)
end
M.Color = {
  to8Bit = to8Bit, to24Bit = to24Bit, optimize = function(c) return to8Bit(to24Bit(c)) end,
  RGBToInteger = RGBToInteger, integerToRGB = integerToRGB,
  RGBToHSB = RGBToHSB, HSBToRGB = HSBToRGB,
  integerToHSB = function(c) return RGBToHSB(integerToRGB(c)) end,
  HSBToInteger = function(h, s, b) return RGBToInteger(HSBToRGB(h, s, b)) end,
  blend = function(a, b, t)
    local ar, ag, ab = integerToRGB(a)
    local br, bg, bb = integerToRGB(b)
    return RGBToInteger(floor(ar + (br - ar) * t), floor(ag + (bg - ag) * t), floor(ab + (bb - ab) * t))
  end,
  transition = function(from, to, steps)
    local result = {}
    for i = 1, steps do result[i] = M.Color.blend(from, to, (i - 1) / max(1, steps - 1)) end
    return result
  end,
}

-- ------------------------------------------------------------ Text
local Text = {}
function Text.serialize(value, pretty, indent, stack)
  pretty = pretty ~= false
  indent = indent or "  "
  stack = stack or {}
  local function ser(v, level)
    local t = type(v)
    if t == "string" then return string.format("%q", v)
    elseif t == "number" or t == "boolean" then return tostring(v)
    elseif t == "nil" then return "nil"
    elseif t == "table" then
      if stack[v] then return "nil" end
      stack[v] = true
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      local pad = pretty and string.rep(indent, level) or ""
      local pad2 = pretty and string.rep(indent, level + 1) or ""
      local parts = {}
      for _, k in ipairs(keys) do
        local key
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then key = k
        else key = "[" .. ser(k, level) .. "]" end
        parts[#parts + 1] = (pretty and "\n" .. pad2 or "") .. key .. (pretty and " = " or "=") .. ser(v[k], level + 1)
      end
      stack[v] = nil
      if #parts == 0 then return "{}" end
      return "{" .. table.concat(parts, pretty and "," or ",") .. (pretty and "\n" .. pad or "") .. "}"
    end
    return "nil"
  end
  return ser(value, 0)
end
function Text.deserialize(text)
  local fn = load("return " .. tostring(text), "=data", "t", {})
  if not fn then return nil end
  local ok, value = pcall(fn)
  if ok then return value end
end
function Text.split(text, separator)
  local out = {}
  local pattern = separator and ("([^" .. separator .. "]+)") or "([%S]+)"
  for part in tostring(text):gmatch(pattern) do out[#out + 1] = part end
  return out
end
function Text.limit(text, width, alignment)
  text = tostring(text)
  if unicode.len(text) <= width then
    local pad = max(0, width - unicode.len(text))
    if alignment == "center" then return string.rep(" ", floor(pad / 2)) .. text .. string.rep(" ", floor(pad / 2))
    elseif alignment == "right" then return string.rep(" ", pad) .. text end
    return text
  end
  return unicode.sub(text, 1, max(0, width - 1)) .. "…"
end
function Text.wrap(text, width)
  local lines = {}
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    if line == "" then lines[#lines + 1] = "" end
    local current = ""
    for word in line:gmatch("%S+") do
      if current == "" then current = word
      elseif unicode.len(current) + 1 + unicode.len(word) <= width then current = current .. " " .. word
      else lines[#lines + 1] = current current = word end
    end
    if current ~= "" then lines[#lines + 1] = current end
  end
  return lines
end
function Text.unicodeFind(s, pattern, init) return unicode.find(tostring(s), pattern, init or 1, true) end
function Text.brailleChar(pixels)
  local bits = {[0] = 1, 2, 4, 8, 16, 32, 64, 128}
  local code = 0x2800
  for i = 0, 7 do if pixels[i + 1] then code = code + bits[i] end end
  return unicode.char(code)
end
M.Text = Text

-- ------------------------------------------------------------ Number
M.Number = {
  round = function(n) return n >= 0 and floor(n + 0.5) or ceil(n - 0.5) end,
  roundToDecimalPlaces = function(n, places) local m = 10 ^ (places or 0) return floor(n * m + 0.5) / m end,
  getDigitCount = function(n) return #tostring(floor(abs(n))) end,
  shorten = function(n)
    local units = {"", "K", "M", "B", "T"}
    local i = 1
    while abs(n) >= 1000 and i < #units do n, i = n / 1000, i + 1 end
    return string.format("%.1f%s", n, units[i])
  end,
}

-- ------------------------------------------------------------ Paths
local Paths = {
  system = {libraries = "/Libraries/", applications = "/Applications/", icons = "/Icons/", localizations = "/Localizations/", extensions = "/Extensions/", users = "/Users/"},
  user = {home = "/Users/Player/", applicationData = "/Users/Player/Application data/", desktop = "/Users/Player/Desktop/", applications = "/Users/Player/Applications/", trash = "/Users/Player/Trash/", settings = "/Users/Player/Settings.cfg", versions = "/Users/Player/Versions.cfg"},
}
function Paths.create(path) System.mkdirs(path) end
function Paths.getUser(name)
  local home = "/Users/" .. tostring(name) .. "/"
  return {home = home, applicationData = home .. "Application data/", desktop = home .. "Desktop/", applications = home .. "Applications/", trash = home .. "Trash/", settings = home .. "Settings.cfg", versions = home .. "Versions.cfg"}
end
function Paths.updateUser(name) Paths.user = Paths.getUser(name or System.settings.username or "Player") end
M.Paths = Paths

-- ------------------------------------------------------------ Sides
M.Sides = {
  [0] = "bottom", [1] = "top", [2] = "back", [3] = "front", [4] = "right", [5] = "left", [6] = "unknown",
  bottom = 0, top = 1, back = 2, front = 3, right = 4, left = 5,
  down = 0, up = 1, north = 2, south = 3, west = 4, east = 5,
  negy = 0, posy = 1, negz = 2, posz = 3, negx = 4, posx = 5,
}

-- ------------------------------------------------------------ Internet (MineOS)
local Internet = {}
function Internet.encode(data)
  return tostring(data):gsub("([^%w%-%_%.%~])", function(ch) return string.format("%%%02X", ch:byte()) end)
end
function Internet.decode(data) return tostring(data):gsub("%%(%x%x)", function(ch) return string.char(tonumber(ch, 16)) end):gsub("+", " ") end
function Internet.request(url, body, headers, method)
  local text, code = HTTP.request(url, body, headers, method)
  if not text then return nil, code end
  return text
end
M.Internet = Internet

-- ------------------------------------------------------------ Image (.pic)
local Image = {}
function Image.create(width, height, color)
  local picture = {"OCIF", 4, width, height}
  for i = 1, width * height do picture[4 + i] = color or 0 end
  return picture
end
function Image.getSize(picture) return picture[3], picture[4] end
function Image.getWidth(picture) return picture[3] end
function Image.getHeight(picture) return picture[4] end
function Image.get(picture, x, y) return picture[4 + (y - 1) * picture[3] + x] end
function Image.set(picture, x, y, color)
  if x >= 1 and x <= picture[3] and y >= 1 and y <= picture[4] then picture[4 + (y - 1) * picture[3] + x] = color end
  return picture
end
function Image.copy(picture)
  local out = {}
  for i = 1, #picture do out[i] = picture[i] end
  return out
end
function Image.load(path)
  local data = System.readFile(path)
  if not data then return nil, "file not found" end
  if data:sub(1, 4) == "OCIF" then
    local encoding, width, height, pos = data:byte(5), 0, 0, 6
    width = data:byte(pos) * 256 + data:byte(pos + 1); pos = pos + 2
    height = data:byte(pos) * 256 + data:byte(pos + 1); pos = pos + 2
    local picture = {"OCIF", encoding, width, height}
    for i = 1, width * height do
      picture[4 + i] = data:byte(pos) * 65536 + data:byte(pos + 1) * 256 + data:byte(pos + 2)
      pos = pos + 3
    end
    return picture
  end
  -- CubeOS .cpic: каждая буква — индекс палитры
  local ok, rows = pcall(function() return load("return " .. data, "=pic", "t", {})() end)
  if ok and type(rows) == "table" and type(rows.rows) == "table" then
    local picture = Image.create(32, 20, 0)
    local letters = " rgybpcomwatdslnekufzhv"
    for y = 1, #rows.rows do
      for x = 1, #tostring(rows.rows[y]) do
        local idx = letters:find(tostring(rows.rows[y]):sub(x, x), 1, true)
        picture[4 + (y - 1) * 32 + x] = idx and (idx * 1000000) or 0
      end
    end
    return picture
  end
  return nil, "unsupported image format"
end
function Image.save(path, picture)
  local bytes = {"OCIF", string.char(picture[2] or 4, floor(picture[3] / 256), picture[3] % 256, floor(picture[4] / 256), picture[4] % 256)}
  for i = 5, #picture do
    local c = picture[i] or 0
    bytes[#bytes + 1] = string.char(floor(c / 65536) % 256, floor(c / 256) % 256, c % 256)
  end
  return System.writeFile(path, table.concat(bytes))
end
function Image.transform(picture, fn)
  local out = Image.copy(picture)
  for y = 1, out[4] do for x = 1, out[3] do out[4 + (y - 1) * out[3] + x] = fn(Image.get(out, x, y), x, y) end end
  return out
end
function Image.crop(picture, x, y, w, h)
  local out = {"OCIF", picture[2], w, h}
  for iy = 1, h do for ix = 1, w do out[4 + (iy - 1) * w + ix] = Image.get(picture, x + ix - 1, y + iy - 1) or 0 end end
  return out
end
function Image.flipHorizontally(picture)
  local out = Image.copy(picture)
  for yy = 1, out[4] do for x = 1, floor(out[3] / 2) do
    local a, b = x, out[3] - x + 1
    out[4 + (yy - 1) * out[3] + a], out[4 + (yy - 1) * out[3] + b] = out[4 + (yy - 1) * out[3] + b], out[4 + (yy - 1) * out[3] + a]
  end end
  return out
end
function Image.flipVertically(picture)
  local out = Image.copy(picture)
  for y = 1, floor(out[4] / 2) do for x = 1, out[3] do
    local a, b = 4 + (y - 1) * out[3] + x, 4 + (out[4] - y) * out[3] + x
    out[a], out[b] = out[b], out[a]
  end end
  return out
end
function Image.invert(picture)
  return Image.transform(picture, function(c) return (255 - ((c >> 16) & 255)) * 65536 + (255 - ((c >> 8) & 255)) * 256 + 255 - (c & 255) end)
end
function Image.blackAndWhite(picture)
  return Image.transform(picture, function(c)
    local v = (((c >> 16) & 255) + ((c >> 8) & 255) + (c & 255)) / 3
    v = v > 127 and 255 or 0
    return v * 65536 + v * 256 + v
  end)
end
function Image.brightness(picture, amount)
  return Image.transform(picture, function(c)
    local function ch(v) return max(0, min(255, floor(v + amount * 255))) end
    return ch((c >> 16) & 255) * 65536 + ch((c >> 8) & 255) * 256 + ch(c & 255)
  end)
end
Image.hue = Image.transform
Image.saturation = Image.transform
Image.colorBalance = Image.transform
function Image.rotate(picture)
  local out = {"OCIF", picture[2], picture[4], picture[3]}
  for y = 1, out[4] do for x = 1, out[3] do
    out[4 + (y - 1) * out[3] + x] = Image.get(picture, y, picture[4] - x + 1) or 0
  end end
  return out
end
function Image.toString(picture)
  local parts = {}
  for i = 1, #picture do parts[i] = type(picture[i]) == "number" and string.char(picture[i] % 256) or tostring(picture[i]) end
  return table.concat(parts)
end
function Image.fromString(text)
  return Image.load(text)
end
M.Image = Image

-- ------------------------------------------------------------ Screen (MineOS)
-- Работает поверх буфера MineCompat: каждый кадр — отдельный слой,
--owned by GUI Surface. MineOS-функции пишут в кадровый буфер через
--глобальные set/flush, которые MineCompat связывает при запуске игры.
-- MineOS Screen рисует ПРЯМО в двойной буфер CubeOS (абсолютные координаты).
--_games вроде MineBlock вызывают screen.drawRectangle(canvas.x, ...) внутри
-- отрисовки виджета, поэтому запись идёт в реальный Screen с текущим clip.
local Scr = {}
local realScreen = Screen
local gpuProxy = component.proxy(component.list("gpu")())
function Scr.getGPUAddress() return gpuProxy.address end
function Scr.setGPUAddress(addr) local ok,p = pcall(component.proxy, addr) if ok and p then gpuProxy = p end end
function Scr.getScreenAddress() return component.list("screen")() end
function Scr.setScreenAddress() end
function Scr.getMaxResolution() return realScreen.size() end
function Scr.getResolution() return realScreen.size() end
function Scr.getWidth() local w = realScreen.size() return w end
function Scr.getHeight() local _, h = realScreen.size() return h end
function Scr.setResolution(w, h) return realScreen.setResolution(w, h) end
function Scr.getMaxColorDepth() return 8 end
function Scr.getColorDepth() return 8 end
function Scr.setColorDepth() return true end
function Scr.getScreenAspectRatio() return 8, 4 end
function Scr.getScaledResolution(scale) local w,h = realScreen.size() return floor(w/scale), floor(h/scale) end
function Scr.setDrawLimit(x1, y1, x2, y2) realScreen.pushClip(x1, y1, x2 - x1 + 1, y2 - y1 + 1) end
function Scr.resetDrawLimit() realScreen.resetClip() end
function Scr.getDrawLimit() return 1, 1, Scr.getWidth(), Scr.getHeight() end
function Scr.rawSet(x, y, bg, fg, ch) realScreen.set(floor(x), floor(y), bg, fg, ch) end
function Scr.rawGet(x, y) local bg, fg, ch = realScreen.get(floor(x), floor(y)) return ch, fg, bg end
function Scr.get(x, y) return Scr.rawGet(x, y) end
function Scr.set(x, y, fg, ch, bg)
  if type(fg) == "table" then bg, fg, ch = fg[1], fg[2], fg[3] end
  realScreen.set(floor(x), floor(y), bg, fg, ch)
end
function Scr.drawRectangle(x, y, w, h, bg, fg, ch)
  realScreen.rect(floor(x), floor(y), floor(w), floor(h), bg, fg, ch or " ")
end
function Scr.clear(bg) local w,h = realScreen.size() realScreen.rect(1, 1, w, h, bg or 0x000000, 0xFFFFFF, " ") end
function Scr.drawText(x, y, fg, text, bg)
  realScreen.text(floor(x), floor(y), fg, tostring(text), bg)
end
function Scr.copy(x, y, w, h, tx, ty)
  local buf = {}
  for yy = 0, h - 1 do for xx = 0, w - 1 do local ch, fg, bg = Scr.rawGet(x + xx, y + yy) buf[#buf + 1] = {ch, fg, bg} end end
  local i = 1
  for yy = 0, h - 1 do for xx = 0, w - 1 do
    local c = buf[i]; i = i + 1
    realScreen.set(tx + xx, ty + yy, c[3], c[2], c[1])
  end end
end
function Scr.paste(x, y, picture)
  if type(picture) ~= "table" then return end
  local w, h = Image.getWidth(picture), Image.getHeight(picture)
  for yy = 1, h do for xx = 1, w do realScreen.set(x + xx - 1, y + yy - 1, Image.get(picture, xx, yy), 0xFFFFFF, " ") end end
end
Scr.drawImage = Scr.paste
Scr.drawFrame = Scr.drawRectangle
function Scr.drawLine(x1, y1, x2, y2, bg, fg, ch)
  local dx, dy = abs(x2 - x1), -abs(y2 - y1)
  local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
  local err = dx + dy
  while true do
    realScreen.set(x1, y1, bg, fg, ch or " ")
    if x1 == x2 and y1 == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then err, x1 = err + dy, x1 + sx end
    if e2 <= dx then err, y1 = err + dx, y1 + sy end
  end
end
function Scr.drawEllipse(cx, cy, rx, ry, bg, fg, ch)
  for i = 0, 360, 0.5 do
    local a = math.rad(i)
    realScreen.set(cx + floor(cos(a) * rx), cy + floor(sin(a) * ry), bg, fg, ch or " ")
  end
end
function Scr.drawPolygon(points, bg, fg, ch)
  for i = 1, #points - 1 do Scr.drawLine(points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], bg, fg, ch) end
  if #points > 2 then Scr.drawLine(points[#points][1], points[#points][2], points[1][1], points[1][2], bg, fg, ch) end
end
function Scr.calculatePosition(x, y, width, height, dx, dy)
  return floor(x + (width - dx) / 2), floor(y + (height - dy) / 2)
end
function Scr.semiPixelRawSet(x, y, bg, fg)
  local cx, cy = floor((x + 1) / 2), floor((y + 1) / 2)
  if x % 2 == 1 then
    realScreen.set(cx, cy, bg, fg, (y % 2 == 1) and "▀" or "▄")
  end
end
function Scr.drawSemiPixelRectangle(x, y, w, h, bg, fg)
  for yy = 0, h - 1 do for xx = 0, w - 1 do Scr.semiPixelRawSet(x + xx, y + yy, bg, fg) end end
end
function Scr.getIndex(x, y) return (floor(y) - 1) * Scr.getWidth() + floor(x) end
function Scr.getCurrentFrameTables() return {} end
function Scr.getNewFrameTables() return {} end
function Scr.rasterizeLine() end
function Scr.rasterizeEllipse() end
function Scr.rasterizeEllipsePoints() end
function Scr.rasterizePolygon() end
function Scr.round() end
function Scr.blur() end
function Scr.getPointTimedPosition() return 1, 1 end
function Scr.getConnectionPoints() return {} end
function Scr.getMainPointPosition() return 1, 1 end
function Scr.drawSemiPixelLine() end
function Scr.drawSemiPixelCurve() end
function Scr.drawSemiPixelEllipse() end
function Scr.update() realScreen.update() end
function Scr.flush() realScreen.update() end
M.Screen = Scr

-- ------------------------------------------------------------ System (MineOS)
local Sys = {}
for k, v in pairs(System) do Sys[k] = v end
-- Путь запущенной игры подставляет MineCompat (systemShim.getCurrentScript)
Sys.currentScript = "/"
Sys.getCurrentScript = function() return Sys.currentScript end
Sys.getLocalization = function() return {} end
Sys.parseArguments = function(...) return {...}, {} end
Sys.addWindow = function(workspace, window) workspace:addChild(window) return workspace, window end
Sys.authorize = function() return true end
Sys.call = function(fn, ...) local ok, err = pcall(fn, ...) return ok, err end
Sys.error = function(err) error(err) end
Sys.updateWorkspace = function() end
Sys.updateDesktop = function() end
M.System = Sys

return M
]]},
  {"/Libraries/RegionPolicy.lua", [[
-- ============================================================
--  CubeOS :: RegionPolicy — региональный доступ к Магазину и RYKEA
--
--  Правила хранятся в облаке (Supabase), поэтому одинаково действуют
--  на всех компьютерах, а не только на том, где их задали.
--
--  Модель данных: служебная строка в таблице store_games
--      id       = "access_<сервис>_<регион>"   (access_store_ru, access_rykea_cn…)
--      category = "system"
--  СУЩЕСТВУЕТ  → сервис в этом регионе ОТКЛЮЧЁН.
--  НЕТ СТРОКИ  → сервис включён.
--
--  Почему так: анонимному ключу Supabase разрешены только SELECT, INSERT и
--  DELETE — UPDATE молча отклоняется политиками RLS (ответ 200 без изменённых
--  строк). Поэтому правило не «обновляется», а создаётся (отключить) или
--  удаляется (включить). Отдельная таблица и SQL не нужны.
-- ============================================================
local System = require("System")
local HTTP = require("HTTP")
local JSON = require("JSON")

local Policy = {}

local BASE = "https://lzyiixywduzkioqpuigv.supabase.co/rest/v1/store_games"
local KEY = "sb_publishable_XAMZUny0QRrfYAHURu44lQ_vtdWB_XB"
local HEADERS = {
  apikey = KEY,
  Authorization = "Bearer " .. KEY,
  ["Content-Type"] = "application/json",
}

local CATEGORY = "system"
local PREFIX = "access_"
local SERVICES = {store = true, rykea = true}

--- Как часто открытое окно перепроверяет правило (секунды). Столько уходит на
--- то, чтобы блокировка, заданная на другом компьютере, дошла до этого.
Policy.pollSeconds = 10

local function rowId(service, region)
  return PREFIX .. service .. "_" .. region
end

local function knownRegion(region)
  for _, r in ipairs(System.regions) do
    if r.id == region then return true end
  end
  return false
end

--- Запрос к облаку. Возвращает (статус, данные) либо (nil, текст ошибки).
local function request(path, method, payload)
  local body, status = HTTP.request(BASE .. path, payload and JSON.encode(payload) or nil, HEADERS, method or "GET", 15)
  if not body then return nil, tostring(status) end
  status = tonumber(status) or 0
  if body == "" then return status, {} end
  local data = JSON.decode(body)
  if data == nil then
    return status, status >= 400 and body:sub(1, 120) or {}
  end
  return status, data
end

local function describe(status, data)
  if type(data) == "table" and data.message then return "HTTP " .. tostring(status) .. ": " .. tostring(data.message) end
  return "HTTP " .. tostring(status) .. ": " .. tostring(data)
end

--- Включён ли сервис в регионе. true / false, либо nil + причина, если проверить не удалось.
function Policy.get(service, region)
  if not SERVICES[service] then return nil, "unknown service" end
  region = region or System.settings.region
  if not region then return nil, "region not selected" end
  local status, data = request("?id=eq." .. rowId(service, region) .. "&select=id", "GET")
  if not status then return nil, data end
  if status >= 400 then return nil, describe(status, data) end
  -- строка есть — сервис отключён
  return not (type(data) == "table" and data[1] ~= nil)
end

--- Все отключённые сочетания: список {id = "store_ru", service, region, enabled = false}.
--- Включённые сочетания в списке отсутствуют (для них нет строки).
function Policy.list()
  local status, data = request("?category=eq." .. CATEGORY .. "&select=id", "GET")
  if not status then return nil, data end
  if status >= 400 then return nil, describe(status, data) end
  local rules = {}
  for _, row in ipairs(type(data) == "table" and data or {}) do
    local service, region = tostring(row.id or ""):match("^" .. PREFIX .. "(%a+)_(%a+)$")
    if service and SERVICES[service] then
      rules[#rules + 1] = {id = service .. "_" .. region, service = service, region = region, enabled = false}
    end
  end
  return rules
end

--- Включить (enabled = true) или отключить (false) сервис в регионе.
function Policy.set(service, region, enabled)
  if not SERVICES[service] then return nil, "unknown service" end
  if not knownRegion(region) then return nil, "unknown region" end
  local id = rowId(service, region)

  if enabled then
    -- включить = убрать запрещающую строку (удаление несуществующей — не ошибка)
    local status, data = request("?id=eq." .. id, "DELETE")
    if not status then return nil, data end
    if status >= 400 then return nil, describe(status, data) end
    return true
  end

  -- отключить = создать строку; 409 значит «уже отключено» — это тоже успех
  local status, data = request("", "POST", {
    id = id,
    title = "Доступ: " .. service .. " / " .. region,
    author = "system",
    description = "Региональное правило CubeOS: сервис отключён",
    category = CATEGORY,
    template = "rule",
    code = "off",
    icon = "",
    version = "1",
    created_at = System.isoNow(),
  })
  if not status then return nil, data end
  if status == 409 or (status >= 200 and status < 300) then return true end
  return nil, describe(status, data)
end

--- Сообщение о блокировке на языке системы
function Policy.message(service)
  local language = System.settings.language or "ru"
  local names = {
    store = {ru = "Магазин", en = "Store", zh = "商店"},
    rykea = {ru = "RYKEA", en = "RYKEA", zh = "RYKEA"},
  }
  local name = (names[service] and names[service][language]) or service
  local region = System.regionName(System.settings.region)
  if language == "en" then return name .. " is unavailable in your region: " .. region end
  if language == "zh" then return name .. " 在当前地区不可用: " .. region end
  return name .. " недоступен в регионе «" .. region .. "»."
end

return Policy
]]},
  {"/Libraries/Screen.lua", [[
-- ============================================================
--  CubeOS :: Screen
--  Двойная буферизация поверх GPU. Рисуем всё в память, а на
--  экран отправляем только изменившиеся ячейки, сгруппированные
--  по цветам (меньше вызовов gpu.set — быстрее и экономнее).
-- ============================================================
local floor = math.floor

local Screen = {}

local gpu, W, H = nil, 0, 0
local curBg, curFg, curCh = {}, {}, {} -- что сейчас на мониторе
local newBg, newFg, newCh = {}, {}, {} -- что должно быть
local dirty = {}
local clipStack = {}
local cx1, cy1, cx2, cy2 = 1, 1, 0, 0

--- Смешивание цветов: top поверх bottom с непрозрачностью a (0..1)
function Screen.blend(top, bottom, a)
  if a >= 1 then return top elseif a <= 0 then return bottom end
  local tr, tg, tb = floor(top / 65536) % 256, floor(top / 256) % 256, top % 256
  local br, bg, bb = floor(bottom / 65536) % 256, floor(bottom / 256) % 256, bottom % 256
  local b = 1 - a
  return floor(tr * a + br * b + 0.5) * 65536 + floor(tg * a + bg * b + 0.5) * 256 + floor(tb * a + bb * b + 0.5)
end
local blend = Screen.blend

function Screen.init(gpuProxy, w, h)
  gpu, W, H = gpuProxy, w, h
  curBg, curFg, curCh, newBg, newFg, newCh, dirty = {}, {}, {}, {}, {}, {}, {}
  for i = 1, w * h do
    curBg[i], curFg[i], curCh[i] = -1, -1, "" -- заведомо отличается → полная перерисовка
    newBg[i], newFg[i], newCh[i] = 0, 0, " "
  end
  for y = 1, h do dirty[y] = true end
  Screen.resetClip()
end

function Screen.size() return W, H end

function Screen.setResolution(w, h)
  gpu.setResolution(w, h)
  Screen.init(gpu, w, h)
end

--- Принудительно перерисовать весь экран при следующем update
function Screen.invalidate()
  for i = 1, W * H do curBg[i] = -1 end
  for y = 1, H do dirty[y] = true end
end

-- ------------------------------------------------------------ области отсечения
function Screen.resetClip()
  clipStack = {}
  cx1, cy1, cx2, cy2 = 1, 1, W, H
end

function Screen.pushClip(x, y, w, h)
  clipStack[#clipStack + 1] = {cx1, cy1, cx2, cy2}
  if x > cx1 then cx1 = x end
  if y > cy1 then cy1 = y end
  if x + w - 1 < cx2 then cx2 = x + w - 1 end
  if y + h - 1 < cy2 then cy2 = y + h - 1 end
end

function Screen.popClip()
  local c = table.remove(clipStack)
  if c then cx1, cy1, cx2, cy2 = c[1], c[2], c[3], c[4] end
end

-- ------------------------------------------------------------ примитивы
--- Установить одну ячейку. nil вместо цвета/символа — оставить как есть.
function Screen.set(x, y, bg, fg, ch)
  if x < cx1 or x > cx2 or y < cy1 or y > cy2 then return end
  local i = (y - 1) * W + x
  if bg then newBg[i] = bg end
  if ch then newCh[i] = ch end
  if newCh[i] == " " then newFg[i] = newBg[i] elseif fg then newFg[i] = fg end
  dirty[y] = true
end

function Screen.get(x, y)
  if x < 1 or x > W or y < 1 or y > H then return 0, 0, " " end
  local i = (y - 1) * W + x
  return newBg[i], newFg[i], newCh[i]
end

--- Прямоугольник. alpha < 1 — полупрозрачная заливка (затемнение, тени).
function Screen.rect(x, y, w, h, bg, fg, ch, alpha)
  local x1, y1 = x > cx1 and x or cx1, y > cy1 and y or cy1
  local x2, y2 = x + w - 1, y + h - 1
  if x2 > cx2 then x2 = cx2 end
  if y2 > cy2 then y2 = cy2 end
  if x1 > x2 or y1 > y2 then return end
  if alpha and alpha < 1 then
    for yy = y1, y2 do
      local base = (yy - 1) * W
      for xx = x1, x2 do
        local i = base + xx
        newBg[i] = blend(bg, newBg[i], alpha)
        newFg[i] = blend(bg, newFg[i], alpha)
        if ch then newCh[i] = ch end
      end
      dirty[yy] = true
    end
    return
  end
  ch = ch or " "
  for yy = y1, y2 do
    local base = (yy - 1) * W
    if ch == " " then
      for xx = x1, x2 do
        local i = base + xx
        newBg[i], newFg[i], newCh[i] = bg, bg, " "
      end
    else
      for xx = x1, x2 do
        local i = base + xx
        newBg[i], newCh[i] = bg, ch
        if fg then newFg[i] = fg end
      end
    end
    dirty[yy] = true
  end
end

--- Текст. Если bg не задан — сохраняется фон под буквами.
function Screen.text(x, y, fg, str, bg)
  if y < cy1 or y > cy2 then return end
  local base = (y - 1) * W
  local xx = x
  for ch in tostring(str):gmatch("[\0-\127\194-\244][\128-\191]*") do
    if xx > cx2 then break end
    if xx >= cx1 then
      local i = base + xx
      if bg then newBg[i] = bg end
      newCh[i] = ch
      if ch == " " then newFg[i] = newBg[i] else newFg[i] = fg end
    end
    xx = xx + 1
  end
  dirty[y] = true
end

function Screen.clear(bg)
  Screen.rect(1, 1, W, H, bg or 0, nil, " ")
end

-- ------------------------------------------------------------ вывод на монитор
function Screen.update()
  local gBg, gFg = -1, -1
  local concat = table.concat
  for y = 1, H do
    if dirty[y] then
      dirty[y] = false
      local base = (y - 1) * W
      local x = 1
      while x <= W do
        local i = base + x
        local bg, fg, ch = newBg[i], newFg[i], newCh[i]
        if bg ~= curBg[i] or fg ~= curFg[i] or ch ~= curCh[i] then
          local startX = x
          local run, n = {ch}, 1
          curBg[i], curFg[i], curCh[i] = bg, fg, ch
          x = x + 1
          while x <= W do
            local j = base + x
            local c = newCh[j]
            if newBg[j] == bg and newFg[j] == fg and (newBg[j] ~= curBg[j] or newFg[j] ~= curFg[j] or c ~= curCh[j]) then
              n = n + 1
              run[n] = c
              curBg[j], curFg[j], curCh[j] = bg, fg, c
              x = x + 1
            else
              break
            end
          end
          if bg ~= gBg then gpu.setBackground(bg) gBg = bg end
          if fg ~= gFg then gpu.setForeground(fg) gFg = fg end
          gpu.set(startX, y, concat(run))
        else
          x = x + 1
        end
      end
    end
  end
end

return Screen
]]},
  {"/Libraries/System.lua", [=[
-- ============================================================
--  CubeOS :: System
--  Файловая система, пути, настройки, время, список приложений.
-- ============================================================
local component, computer, unicode = component, computer, unicode

local System = {}
System.name = "CubeOS"
System.version = "1.4"
System.build = "2026.5"

local bootAddress = computer.getBootAddress()
local fs = component.proxy(bootAddress)
System.fs = fs
System.bootAddress = bootAddress

-- ------------------------------------------------------------ пути
function System.normalize(path)
  local parts = {}
  for part in tostring(path):gmatch("[^/]+") do
    if part == ".." then
      parts[#parts] = nil
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  return "/" .. table.concat(parts, "/")
end

function System.join(base, path)
  if path:sub(1, 1) == "/" then return System.normalize(path) end
  return System.normalize(base .. "/" .. path)
end

function System.basename(path)
  local p = path:gsub("/+$", "")
  return p:match("([^/]*)$")
end

function System.dirname(path)
  local d = System.normalize(path):match("^(.*)/[^/]*$")
  if not d or d == "" then return "/" end
  return d
end

function System.extension(path)
  return (path:match("%.([^./]+)/?$") or ""):lower()
end

-- ------------------------------------------------------------ файлы
function System.exists(path) return fs.exists(path) end
function System.isDir(path) return fs.isDirectory(path) end
function System.size(path) return fs.size(path) end

--- Содержимое папки: сначала папки (с «/» на конце), потом файлы
function System.list(path)
  local dirs, files = {}, {}
  for _, name in ipairs(fs.list(path) or {}) do
    if name:sub(-1) == "/" then dirs[#dirs + 1] = name else files[#files + 1] = name end
  end
  local function less(a, b) return a:lower() < b:lower() end
  table.sort(dirs, less)
  table.sort(files, less)
  for _, f in ipairs(files) do dirs[#dirs + 1] = f end
  return dirs
end

function System.readFile(path)
  local handle = fs.open(path, "r")
  if not handle then return nil, "не удалось открыть " .. path end
  local parts = {}
  repeat
    local chunk = fs.read(handle, math.huge)
    parts[#parts + 1] = chunk
  until not chunk
  fs.close(handle)
  return table.concat(parts)
end

function System.mkdirs(path)
  local cur = ""
  for part in System.normalize(path):gmatch("[^/]+") do
    cur = cur .. "/" .. part
    if not fs.exists(cur) then
      local ok, err = fs.makeDirectory(cur)
      if not ok then return nil, err end
    end
  end
  return true
end

function System.writeFile(path, data, append)
  System.mkdirs(System.dirname(path))
  local handle, err = fs.open(path, append and "a" or "w")
  if not handle then return nil, err or "не удалось открыть файл" end
  if #data > 0 then
    local ok, e = fs.write(handle, data)
    if not ok then fs.close(handle) return nil, e end
  end
  fs.close(handle)
  return true
end

function System.remove(path) return fs.remove(path) end
function System.rename(from, to) return fs.rename(from, to) end

function System.copy(from, to)
  if fs.isDirectory(from) then
    System.mkdirs(to)
    for _, name in ipairs(fs.list(from) or {}) do
      local n = name:gsub("/$", "")
      System.copy(from .. "/" .. n, to .. "/" .. n)
    end
    return true
  end
  local data, err = System.readFile(from)
  if not data then return nil, err end
  return System.writeFile(to, data)
end

-- ------------------------------------------------------------ установка приложений
-- Имена, под которыми лежат системные приложения
System.reservedApps = {Store = true, Finder = true, Editor = true, Terminal = true, Calculator = true, Snake = true, Monitor = true, Settings = true}

local function luaQuote(s)
  s = tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", ""):gsub("\n", "\\n")
  return '"' .. s .. '"'
end

--- Оставить только буквы, цифры, _ и -; id должен начинаться с буквы
function System.safeAppId(id)
  id = (tostring(id or ""):gsub("[^%w_%-]", ""))
  if id == "" then id = "app" end
  if not id:match("^[A-Za-z_]") then id = "a" .. id end
  return id
end

--- Записать файлы приложения. files: {[имя внутри .app] = текст}.
--- Возвращает true, путь — либо nil, ошибка.
function System.installFiles(appId, files)
  if System.reservedApps[appId] then return nil, "имя «" .. appId .. "» зарезервировано" end
  if type(files) ~= "table" or not files["Info.lua"] or not files["Main.lua"] then
    return nil, "нужны Info.lua и Main.lua"
  end
  local base = "/Applications/" .. appId .. ".app"
  System.mkdirs(base)
  for name, text in pairs(files) do
    if type(name) ~= "string" or name:find("/", 1, true) or name:find("\\", 1, true) or name == ".." then
      return nil, "недопустимое имя файла: " .. tostring(name)
    end
    local ok, err = System.writeFile(base .. "/" .. name, text)
    if not ok then return nil, tostring(err) end
  end
  -- обёртка MineOS больше не нужна — старый game.lua не должен оставаться
  if not files["game.lua"] then System.remove(base .. "/game.lua") end
  return true, base
end

local MINEOS_WRAPPER = [[-- Обёртка совместимости: игра написана под MineOS
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local MC = require("MineCompat")
local code = System.readFile(ctx.path .. "/game.lua")
if not code then
  GUI.alert("Ошибка установки", "Не найден game.lua")
  return nil
end
return MC.run(ctx, code, {title = ctx.title})
]]

--- Собрать файлы .app из описания игры.
--- g: {id, title, short, description, author, template = "mineos"|"cubeos", code,
---     icon = 8 строк через \n или таблица строк}
function System.buildAppFiles(g)
  g = g or {}
  local title = tostring(g.title or "Приложение")
  local short = tostring(g.short or title)
  if unicode.len(short) > 11 then short = unicode.sub(short, 1, 10) .. "…" end
  local files = {}
  if g.template == "mineos" then
    files["game.lua"] = tostring(g.code or "")
    files["Main.lua"] = MINEOS_WRAPPER
  else
    files["Main.lua"] = tostring(g.code or "")
  end
  local icon = g.icon or g.rows
  local rows = {}
  if type(icon) == "table" then
    for i = 1, 8 do rows[i] = tostring(icon[i] or "") end
  elseif type(icon) == "string" then
    local i = 0
    for line in (icon .. "\n"):gmatch("(.-)\n") do
      i = i + 1
      if i <= 8 and line ~= "" then rows[i] = line end
    end
  end
  local lines = {
    "return {",
    "  title = " .. luaQuote(title) .. ", short = " .. luaQuote(short) .. ", order = 20,",
    "  description = " .. luaQuote(g.description or "") .. ",",
    "  author = " .. luaQuote(g.author or "") .. ",",
    "  icon = {",
  }
  for i = 1, 8 do
    local row = (rows[i] or ""):sub(1, 8):gsub("[^%a.]", ".")
    if row == "" then row = "........" end
    lines[#lines + 1] = "    " .. luaQuote(row) .. ","
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  files["Info.lua"] = table.concat(lines, "\n") .. "\n"
  return files
end

--- Установить игру/приложение из кода. Возвращает путь — либо nil, ошибка.
function System.installApp(g)
  local id = System.safeAppId((g or {}).id)
  local ok, err = System.installFiles(id, System.buildAppFiles(g))
  if not ok then return nil, err end
  return "/Applications/" .. id .. ".app"
end

function System.formatSize(bytes)
  bytes = bytes or 0
  if bytes < 1024 then return bytes .. " Б" end
  if bytes < 1024 * 1024 then return string.format("%.1f КБ", bytes / 1024) end
  return string.format("%.2f МБ", bytes / 1024 / 1024)
end

-- ------------------------------------------------------------ сериализация
function System.serialize(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") and k ~= "end" and k ~= "function" then
        key = k
      else
        key = "[" .. System.serialize(k) .. "]"
      end
      out[#out + 1] = key .. "=" .. System.serialize(v[k])
    end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "nil"
end

function System.unserialize(str)
  local fn = load("return " .. tostring(str), "=data", "t", {})
  if not fn then return nil end
  local ok, res = pcall(fn)
  if ok then return res end
end

function System.loadData(path)
  local code = System.readFile(path)
  if not code then return nil end
  local fn = load(code, "=" .. path, "t", {})
  if not fn then return nil end
  local ok, res = pcall(fn)
  if ok then return res end
end

-- ------------------------------------------------------------ настройки
System.settingsPath = "/Users/Settings.cfg"
local defaults = {theme = "dark", accent = 1, wallpaper = 1, timezone = 3, username = "Игрок", language = "ru"}

System.regions = {
  {id = "ru", name = "Россия"}, {id = "by", name = "Беларусь"},
  {id = "cn", name = "Китай"}, {id = "kz", name = "Казахстан"},
  {id = "ua", name = "Украина"}, {id = "us", name = "США"},
  {id = "eu", name = "Европа"}, {id = "other", name = "Другие страны"},
}
System.languages = {
  {id = "ru", name = "Русский"}, {id = "en", name = "English"},
  {id = "zh", name = "中文 (Chinese)"},
}

function System.regionName(id)
  for _, r in ipairs(System.regions) do if r.id == id then return r.name end end
  return "Не выбран"
end

function System.languageName(id)
  for _, l in ipairs(System.languages) do if l.id == id then return l.name end end
  return "Русский"
end

-- ------------------------------------------------------------ платформа OpenComputers
function System.detectPlatform()
  local dev = {}
  if computer and computer.getDeviceInfo then
    local info = computer.getDeviceInfo()
    if type(info) == "table" then
      if info.product or info.vendor or info.mc then
        dev = info
      else
        for _, v in pairs(info) do
          if type(v) == "table" and (v.product or v.vendor or v.mc) then dev = v break end
        end
      end
    end
  end
  local arch = (computer and computer.getArchitecture and computer.getArchitecture()) or "Lua 5.3"
  local osver = _G._OSVERSION or ""
  local cfgEdition = System.settings and System.settings.edition

  local isOCCE = (dev.vendor == "OpenComputers Community Edition")
    or (dev.product == "OCCE 1.20.1")
    or (dev.mc == "1.20.1")
    or (arch:find("1.20.1") ~= nil)
    or (arch:find("OCCE") ~= nil)
    or (osver:find("Community Edition") ~= nil)
    or (cfgEdition == "occe_1_20_1")

  if isOCCE then
    System.edition = "occe_1_20_1"
    System.platform = "OpenComputers Community Edition 1.20.1"
    System.platformShort = "OCCE 1.20.1"
    System.minecraft = "1.20.1"
    System.modLoader = "Forge"
    System.screenTier = 4   -- монитор/видеокарта Tier 4: 190×60
  else
    System.edition = "classic"
    System.platform = "OpenComputers Classic (1.7.10 / 1.12.2)"
    System.platformShort = "OC Classic"
    System.minecraft = "1.7.10 / 1.12.2"
    System.modLoader = "Forge"
    System.screenTier = 3   -- монитор/видеокарта Tier 3: 160×50
  end
  -- Если железо сообщает свой уровень экрана — доверяем ему
  if type(dev.screenTier) == "number" then System.screenTier = dev.screenTier end
  return System.edition
end

function System.loadSettings()
  local s = {}
  for k, v in pairs(defaults) do s[k] = v end
  local data = System.readFile(System.settingsPath)
  if data then
    local t = System.unserialize(data)
    if type(t) == "table" then for k, v in pairs(t) do s[k] = v end end
  end
  local regionOk, languageOk = false, false
  for _, r in ipairs(System.regions) do if s.region == r.id then regionOk = true end end
  for _, l in ipairs(System.languages) do if s.language == l.id then languageOk = true end end
  if not regionOk then s.region = nil end
  if not languageOk then s.language = "ru" end
  if not s.edition then s.edition = System.detectPlatform() end
  System.settings = s
  System.detectPlatform()
  return s
end

function System.saveSettings()
  System.writeFile(System.settingsPath, System.serialize(System.settings))
end

function System.resetSettings()
  local region, language = System.settings.region, System.settings.language
  System.settings = {}
  for k, v in pairs(defaults) do System.settings[k] = v end
  System.settings.region = region
  System.settings.language = language or "ru"
  System.saveSettings()
end

System.loadSettings()

-- ------------------------------------------------------------ время
-- Реальное время берём как MineOS: пишем файл во временную ФС
-- и читаем lastModified — оно содержит время хост-машины.
local tmpFs = component.proxy(computer.tmpAddress())
local timeBase, timeUp = nil, 0

local function syncTime()
  local handle = tmpFs.open("/.clock", "w")
  if handle then
    tmpFs.write(handle, "x")
    tmpFs.close(handle)
  end
  local t = tmpFs.lastModified("/.clock")
  if t and t > 0 then
    if t > 1e11 then t = t / 1000 end
    timeBase, timeUp = math.floor(t), computer.uptime()
  else
    timeBase, timeUp = math.floor(os.time()), computer.uptime()
  end
end

--- Unix-время в секундах (UTC)
function System.time()
  if not timeBase or computer.uptime() - timeUp > 300 then pcall(syncTime) end
  if not timeBase then return math.floor(os.time()) end
  return timeBase + math.floor(computer.uptime() - timeUp)
end

local function civil(days)
  days = days + 719468
  local era = math.floor(days / 146097)
  local doe = days - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y, m, d
end

--- Форматирование даты (%Y %y %m %d %H %M %S). utc=true — без часового пояса.
function System.date(fmt, t, utc)
  local stamp = math.floor((t or System.time()) + (utc and 0 or (System.settings.timezone or 0) * 3600))
  local y, m, d = civil(math.floor(stamp / 86400))
  local secs = stamp % 86400
  local map = {
    Y = string.format("%04d", y), y = string.format("%02d", y % 100),
    m = string.format("%02d", m), d = string.format("%02d", d),
    H = string.format("%02d", math.floor(secs / 3600)),
    M = string.format("%02d", math.floor(secs / 60) % 60),
    S = string.format("%02d", secs % 60),
  }
  return (fmt:gsub("%%(%a)", function(c) return map[c] end))
end

--- Текущее время в формате ISO-8601 (UTC), как в базе RYKEA
function System.isoNow()
  return System.date("%Y-%m-%dT%H:%M:%SZ", nil, true)
end

function System.clock() return System.date("%H:%M") end

--- Ожидание (события за это время отбрасываются)
function System.sleep(sec)
  local deadline = computer.uptime() + sec
  repeat
    computer.pullSignal(math.max(0, deadline - computer.uptime()))
  until computer.uptime() >= deadline
end

function System.memory()
  local total = computer.totalMemory()
  return total - computer.freeMemory(), total
end

function System.uptimeText()
  local s = math.floor(computer.uptime())
  return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

-- ------------------------------------------------------------ приложения
function System.apps()
  local list = {}
  for _, name in ipairs(System.list("/Applications")) do
    if name:match("%.app/$") then
      local path = "/Applications/" .. name:sub(1, -2)
      local info = System.loadData(path .. "/Info.lua")
      if type(info) == "table" then
        info.path = path
        info.id = name:sub(1, -6)
        list[#list + 1] = info
      end
    end
  end
  table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
  return list
end

--- Выполнить Lua-код, перехватив print/io.write. Возвращает ok, вывод.
function System.runLua(code, name, extraEnv)
  local out = {}
  local env = setmetatable({}, {__index = _G})
  env.print = function(...)
    local t = table.pack(...)
    for i = 1, t.n do t[i] = tostring(t[i]) end
    out[#out + 1] = table.concat(t, "\t") .. "\n"
  end
  env.io = {write = function(...)
    for _, v in ipairs({...}) do out[#out + 1] = tostring(v) end
  end}
  for k, v in pairs(extraEnv or {}) do env[k] = v end
  local fn, err = load(code, "=" .. (name or "script"), "t", env)
  if not fn then return false, tostring(err) end
  local ok, res = xpcall(fn, function(e)
    if debug and debug.traceback then return debug.traceback(tostring(e), 2) end
    return tostring(e)
  end)
  local text = table.concat(out)
  if not ok then text = text .. tostring(res) end
  return ok, text
end

return System
]=]},
  {"/StorePackages/Paint.app/Info.lua", [[
return {
  title = "Пиксели", short = "Пиксели", order = 8,
  description = "Редактор пиксель-арта 32×20: кисть, заливка, пипетка, 16 цветов. Рисунки сохраняются в /Users/Pictures/*.cpic.",
  author = "CubeOS",
  icon = {
    "........",
    ".wwwwww.",
    ".wrgbyw.",
    ".wpcomw.",
    ".wwwwww.",
    ".....dw.",
    "......dw",
    "........",
  },
}
]]},
  {"/StorePackages/Paint.app/Main.lua", [[
-- ============================================================
--  Пиксели — редактор пиксель-арта для CubeOS
--  Пиксель = 2 ячейки экрана в ширину (получается квадрат 16×16 px).
--  ЛКМ — рисовать, ПКМ — стирать, перетаскивание — непрерывная линия.
--  Файлы сохраняются в /Users/Pictures/*.cpic (сериализованная таблица).
-- ============================================================
local ctx = ...
local GUI = require("GUI")
local Screen = require("Screen")
local System = require("System")
local Desktop = ctx.Desktop
local floor = math.floor

local PW, PH = 32, 20                -- холст в пикселях
local CW, CH = PW * 2, PH            -- холст в ячейках
local SIDE = 14                      -- ширина боковой панели
local PICTURES = "/Users/Pictures"

local PALETTE = {
  0x1E1F22, 0xFFFFFF, 0x949BA4, 0x4E5058,
  0xED4245, 0xFF8A3D, 0xFAA61A, 0xFFE066,
  0x3BA55D, 0x2DD4BF, 0x22D3EE, 0x4C8DFF,
  0x5865F2, 0xA78BFA, 0xF472B6, 0x8B5E3C,
}
local LETTERS = "ABCDEFGHIJKLMNOP"   -- индекс палитры → символ в файле, "." — пусто

local win = ctx.window(CW + SIDE + 4, CH + 4, "Пиксели")
local c = win.content

local pixels = {}                    -- pixels[y][x] = 0 (пусто) или индекс палитры
local color, tool, dirty, filePath = 5, "pen", false, nil
local tools = {}

local function newImage()
  for y = 1, PH do
    pixels[y] = {}
    for x = 1, PW do pixels[y][x] = 0 end
  end
end
newImage()

local function updateTitle()
  win:setTitle("Пиксели — " .. (filePath and System.basename(filePath) or "Без имени") .. (dirty and " •" or ""))
end

local function touch()
  if not dirty then dirty = true updateTitle() end
end

local function refreshTools()
  for name, b in pairs(tools) do b.style = (tool == name) and "primary" or nil end
end

-- ------------------------------------------------------------ холст
local Canvas = GUI.class()
local canvas = c:add(GUI.new(Canvas, 2, 2, CW, CH))

function Canvas:drawSelf(ax, ay)
  for y = 1, PH do
    local row = pixels[y]
    for x = 1, PW do
      local idx = row[x]
      local bg = idx > 0 and PALETTE[idx] or (((x + y) % 2 == 0) and 0x2B2D31 or 0x232428)
      Screen.rect(ax + (x - 1) * 2, ay + y - 1, 2, 1, bg, nil, " ")
    end
  end
end

local function plot(x, y, idx)
  if x < 1 or x > PW or y < 1 or y > PH then return end
  if pixels[y][x] ~= idx then
    pixels[y][x] = idx
    touch()
  end
end

local function floodFill(x, y, idx)
  local target = pixels[y][x]
  if target == idx then return end
  local stack = {{x, y}}
  while #stack > 0 do
    local p = table.remove(stack)
    local px, py = p[1], p[2]
    if px >= 1 and px <= PW and py >= 1 and py <= PH and pixels[py][px] == target then
      pixels[py][px] = idx
      stack[#stack + 1] = {px + 1, py}
      stack[#stack + 1] = {px - 1, py}
      stack[#stack + 1] = {px, py + 1}
      stack[#stack + 1] = {px, py - 1}
    end
  end
  touch()
end

-- Линия Брезенхэма, чтобы быстрые движения мыши не рвали штрих
local lastX, lastY
local function line(x0, y0, x1, y1, idx)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    plot(x0, y0, idx)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy x0 = x0 + sx end
    if e2 <= dx then err = err + dx y0 = y0 + sy end
  end
end

function Canvas:onEvent(e, ax, ay)
  if e.type ~= "touch" and e.type ~= "drag" then return false end
  local x, y = floor((e.x - ax) / 2) + 1, e.y - ay + 1
  if x < 1 or x > PW or y < 1 or y > PH then return true end
  local idx = (e.button == 1) and 0 or color
  if e.type == "touch" then
    self:capture()
    if tool == "fill" then
      floodFill(x, y, idx)
    elseif tool == "pick" then
      if pixels[y][x] > 0 then color = pixels[y][x] end
      tool = "pen"
      refreshTools()
    else
      plot(x, y, idx)
    end
    lastX, lastY = x, y
  elseif tool == "pen" then
    line(lastX or x, lastY or y, x, y, idx)
    lastX, lastY = x, y
  end
  return true
end

-- ------------------------------------------------------------ палитра
local Palette = GUI.class()
local palX = CW + 4
c:add(GUI.label(palX, 1, "Палитра", "dim"))
local palette = c:add(GUI.new(Palette, palX, 2, 12, 4))

function Palette:drawSelf(ax, ay)
  for i = 1, #PALETTE do
    local col, row = (i - 1) % 4, floor((i - 1) / 4)
    local x, y = ax + col * 3, ay + row
    Screen.rect(x, y, 3, 1, PALETTE[i], nil, " ")
    if i == color then
      local light = (i == 2 or i == 7 or i == 8 or i == 3)
      Screen.text(x + 1, y, light and 0x000000 or 0xFFFFFF, "●", PALETTE[i])
    end
  end
end

function Palette:onEvent(e, ax, ay)
  if e.type == "touch" then
    local i = (e.y - ay) * 4 + floor((e.x - ax) / 3) + 1
    if PALETTE[i] then
      color = i
      if tool == "pick" then tool = "pen" refreshTools() end
    end
    return true
  end
  return false
end

-- ------------------------------------------------------------ файлы
local function encode()
  local rows = {}
  for y = 1, PH do
    local t = {}
    for x = 1, PW do
      local v = pixels[y][x]
      t[x] = v > 0 and LETTERS:sub(v, v) or "."
    end
    rows[y] = table.concat(t)
  end
  return {format = "cpic", w = PW, h = PH, rows = rows}
end

local function decode(data)
  if type(data) ~= "table" or type(data.rows) ~= "table" then return false end
  newImage()
  for y = 1, math.min(PH, #data.rows) do
    local row = tostring(data.rows[y])
    for x = 1, math.min(PW, #row) do
      local ch = row:sub(x, x)
      local idx = LETTERS:find(ch, 1, true)
      pixels[y][x] = idx or 0
    end
  end
  return true
end

local function save(as)
  local path = filePath
  if as or not path then
    local name = GUI.prompt("Сохранить рисунок", "Имя файла (без расширения):", filePath and (System.basename(filePath):gsub("%.cpic$", "")) or "рисунок")
    if not name or name == "" then return false end
    path = PICTURES .. "/" .. (name:gsub("[/\\]", "_")) .. ".cpic"
  end
  System.mkdirs(PICTURES)
  local ok, err = System.writeFile(path, "return " .. System.serialize(encode()))
  if not ok then GUI.alert("Ошибка сохранения", tostring(err)) return false end
  filePath, dirty = path, false
  updateTitle()
  Desktop.notify("Сохранено: " .. path)
  return true
end

local function confirmDiscard()
  if not dirty then return true end
  return GUI.confirm("Несохранённые изменения", "Отбросить изменения в текущем рисунке?", "Отбросить", "Отмена", true)
end

local function openFile(path)
  local data = System.loadData(path)
  if not decode(data) then
    GUI.alert("Ошибка", "Файл " .. path .. " не похож на рисунок CubeOS (.cpic)")
    return
  end
  filePath, dirty = path, false
  updateTitle()
end

local function openDialog()
  if not confirmDiscard() then return end
  local names = {}
  for _, name in ipairs(System.list(PICTURES)) do
    if name:match("%.cpic$") then names[#names + 1] = name end
  end
  if #names == 0 then
    GUI.alert("Открыть", "В папке " .. PICTURES .. " пока нет рисунков.\nНарисуйте что-нибудь и нажмите «Сохранить».")
    return
  end
  table.sort(names)
  local idx = GUI.select("Открыть рисунок", names)
  if idx then openFile(PICTURES .. "/" .. names[idx]) end
end

-- ------------------------------------------------------------ панель инструментов
local function toolButton(y, name, text)
  tools[name] = c:add(GUI.button(palX, y, 12, 1, text, function()
    tool = name
    refreshTools()
  end))
end
c:add(GUI.label(palX, 7, "Инструмент", "dim"))
toolButton(8, "pen", "Кисть")
toolButton(9, "fill", "Заливка")
toolButton(10, "pick", "Пипетка")
refreshTools()

c:add(GUI.label(palX, 12, "Файл", "dim"))
c:add(GUI.button(palX, 13, 12, 1, "Новый", function()
  if not confirmDiscard() then return end
  newImage()
  filePath, dirty = nil, false
  updateTitle()
end))
c:add(GUI.button(palX, 14, 12, 1, "Открыть…", openDialog))
c:add(GUI.button(palX, 15, 12, 1, "Сохранить", function() save(false) end, "primary"))
c:add(GUI.button(palX, 16, 12, 1, "Сохранить как", function() save(true) end))
c:add(GUI.button(palX, 18, 12, 1, "Очистить", function()
  if GUI.confirm("Очистить холст", "Стереть весь рисунок?", "Стереть", "Отмена", true) then
    newImage()
    touch()
  end
end, "danger"))

c:add(GUI.label(2, CH + 2, "ЛКМ — рисовать, ПКМ — стирать, 1–9/0 — цвет, F — заливка, Ctrl+S — сохранить", "dim"))

-- ------------------------------------------------------------ клавиатура и закрытие
win.onKey = function(_, e)
  local ch = e.char and e.char > 0 and string.char(e.char % 256):lower() or ""
  if e.ctrl and e.code == 31 then save(false) return true end          -- Ctrl+S
  if e.ctrl and e.code == 24 then openDialog() return true end         -- Ctrl+O
  if e.code >= 2 and e.code <= 11 then                                 -- цифры 1..9, 0
    local n = e.code - 1
    color = e.shift and (n + 6) or n
    if color > #PALETTE then color = #PALETTE end
    return true
  end
  if ch == "f" then tool = "fill" refreshTools() return true end
  if ch == "b" then tool = "pen" refreshTools() return true end
  if ch == "i" then tool = "pick" refreshTools() return true end
  return false
end

win.onClose = function()
  if dirty then
    return GUI.confirm("Несохранённые изменения", "Закрыть без сохранения?", "Закрыть", "Отмена", true)
  end
end

-- Открытие файла, переданного через ctx.args (из Файлов)
if ctx.args and ctx.args.file then openFile(ctx.args.file) end
updateTitle()
]]},
  {"/StorePackages/RYKEA.app/Config.lua", [[
-- Настройки приложения RYKEA. Publishable key безопасно передавать клиенту,
-- но права на таблицы должны ограничиваться политиками RLS в Supabase.
-- Локальный администратор выключен по умолчанию: используйте учётную запись
-- из таблицы users либо настройте собственный admin_email / admin_pass.
-- Текущая схема users хранит пароль открытым текстом и требует Supabase Auth
-- для безопасного использования реальными покупателями.
return {
  supabase_url = "https://mvspqjfljpslfniiujoh.supabase.co",
  anon_key = "sb_publishable_qdNnYgdgmr5nspTVovWKTg_utDyFsFr",
  admin_email = nil,
  admin_pass = nil,
  delivery_price = 990,         -- стоимость доставки, руб.
  free_delivery_from = 30000,   -- бесплатная доставка от суммы, руб.
  currency = "руб.",
}
]]},
  {"/StorePackages/RYKEA.app/Info.lua", [[
return {
  title = "RYKEA — магазин", short = "RYKEA", order = 1,
  description = "Магазин мебели с вашего сайта: каталог, корзина и реальные заказы через Internet Card и Supabase.",
  author = "RYKEA",
  icon = {
    pal = {u = 0x0058A3, y = 0xFFDA1A},
    ".uuuuuu.",
    "uuuuuuuu",
    "uyyyyyyu",
    "uyuuuuyu",
    "uyyyyyyu",
    "uyuuyuyu",
    "uuuuuuuu",
    ".uuuuuu.",
  },
}
]]},
  {"/StorePackages/RYKEA.app/Main.lua", [=[
-- ============================================================
--  RYKEA — магазин мебели и товаров для дома
--  Графический порт Lua-приложения для OpenComputers:
--  каталог, карточка товара, корзина, заказы, аккаунт и
--  админ-панель работают с базой Supabase через Internet Card.
-- ============================================================
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local JSON = require("JSON")
local HTTP = require("HTTP")
local Policy = require("RegionPolicy")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local allowed, policyError = Policy.get("rykea")
if allowed ~= true then
  GUI.alert("Региональный доступ", allowed == false and Policy.message("rykea") or ("Не удалось проверить регион: " .. tostring(policyError)))
  return
end

local CFG = System.loadData(ctx.path .. "/Config.lua") or {}
-- Old installations used the original JWT key. Keep custom project settings,
-- but use the new publishable key for the known RYKEA project.
if CFG.supabase_url == "https://mvspqjfljpslfniiujoh.supabase.co" and type(CFG.anon_key) == "string" and CFG.anon_key:match("^eyJ") then
  CFG.anon_key = "sb_publishable_qdNnYgdgmr5nspTVovWKTg_utDyFsFr"
  if CFG.admin_email == "admin@rykea.ru" and CFG.admin_pass == "admin123" then
    CFG.admin_email, CFG.admin_pass = nil, nil
  end
end
local BLUE, YELLOW, WHITE = 0x0058A3, 0xFFDA1A, 0xFFFFFF

local W0, H0 = Desktop.screenSize()
local win = ctx.window(min(104, W0), min(36, H0 - 7), "RYKEA — мебель и товары для дома")
win.resizable, win.minW, win.minH = true, 72, 22
local c = win.content

local COLOR_HEX = {
  ["Белый"] = "#f5f5f4", ["Бежевый"] = "#d4b896", ["Серый"] = "#9ca3af", ["Тёмно-серый"] = "#52525b",
  ["Чёрный"] = "#1c1917", ["Коричневый"] = "#8b6f47", ["Дуб"] = "#c19a6b", ["Ясень"] = "#d2b48c",
  ["Орех"] = "#5c4033", ["Зелёный"] = "#65a30d", ["Светло-зелёный"] = "#a3e635", ["Жёлтый"] = "#facc15",
  ["Розовый"] = "#f9a8d4", ["Голубой"] = "#7dd3fc", ["Синий"] = "#3b82f6", ["Красный"] = "#ef4444",
  ["Светлый"] = "#e7e5e4", ["Антрацит"] = "#374151", ["Бирюзовый"] = "#2dd4bf", ["Лиловый"] = "#c084fc",
}

local STATUS = {
  new = {"Новый", 0x60A5FA}, processing = {"В обработке", 0xFAA61A}, shipped = {"Отправлен", 0xA78BFA},
  done = {"Выполнен", 0x3BA55D}, cancelled = {"Отменён", 0xED4245},
}

local S = {user = nil, cart = {}, products = {}, categories = {}, orders = {}, cat = nil, query = ""}

-- ------------------------------------------------------------ форматирование
local function fmtPrice(n)
  local s = tostring(floor(tonumber(n) or 0))
  local out, cnt = "", 0
  for i = #s, 1, -1 do
    if cnt > 0 and cnt % 3 == 0 then out = " " .. out end
    out = s:sub(i, i) .. out
    cnt = cnt + 1
  end
  return out .. " " .. (CFG.currency or "руб.")
end

local function fmtDate(iso)
  if not iso or #iso < 16 then return "—" end
  return iso:sub(9, 10) .. "." .. iso:sub(6, 7) .. "." .. iso:sub(1, 4) .. " " .. iso:sub(12, 16)
end

local function hexColor(name)
  local hex = COLOR_HEX[name]
  return hex and tonumber(hex:sub(2), 16) or 0x6B7280
end

local function isLight(color)
  local r, g, b = floor(color / 65536) % 256, floor(color / 256) % 256, color % 256
  return (0.299 * r + 0.587 * g + 0.114 * b) > 150
end

local function stars(rating)
  local n = max(0, min(5, floor((tonumber(rating) or 0) + 0.5)))
  return string.rep("★", n) .. string.rep("☆", 5 - n)
end

local function urlenc(s)
  return (tostring(s):gsub("[^%w%-_%.~]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

-- ------------------------------------------------------------ база данных (Supabase REST)
local BASE = tostring(CFG.supabase_url) .. "/rest/v1"

local function headers(extra)
  local h = {apikey = CFG.anon_key, ["Content-Type"] = "application/json"}
  -- Publishable keys are API keys, not user JWTs.
  if type(CFG.anon_key) == "string" and not CFG.anon_key:match("^sb_publishable_") then
    h.Authorization = "Bearer " .. CFG.anon_key
  end
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

local db = {}

local function responseError(code, body)
  local decoded = JSON.decode(body or "")
  local message = type(decoded) == "table" and (decoded.message or decoded.error or decoded.code) or body
  return "HTTP " .. tostring(code or "?") .. ": " .. tostring(message or "ошибка сервера"):sub(1, 120)
end

function db.select(tbl, query)
  local body, code = HTTP.request(BASE .. "/" .. tbl .. "?select=*" .. (query or ""), nil, headers(), "GET")
  if not body then return nil, tostring(code) end
  if code and code >= 300 then return nil, responseError(code, body) end
  local rows = JSON.decode(body)
  if type(rows) ~= "table" then return nil, "некорректный ответ сервера (" .. tostring(code) .. ")" end
  if rows.message and not rows[1] then return nil, tostring(rows.message) end
  return rows
end

function db.upsert(tbl, row)
  local body, code = HTTP.request(BASE .. "/" .. tbl, JSON.encode(row), headers({Prefer = "resolution=merge-duplicates,return=minimal"}), "POST")
  if not body then return nil, tostring(code) end
  if code and code >= 300 then return nil, responseError(code, body) end
  return true
end

function db.delete(tbl, id)
  local body, code = HTTP.request(BASE .. "/" .. tbl .. "?id=eq." .. urlenc(id), nil, headers({["X-HTTP-Method-Override"] = "DELETE"}), "DELETE")
  if not body then return nil, tostring(code) end
  if code and code >= 300 then return nil, responseError(code, body) end
  return true
end

local function rowsData(rows)
  local out = {}
  for _, row in ipairs(rows or {}) do
    if type(row) == "table" and type(row.data) == "table" then out[#out + 1] = row.data end
  end
  return out
end

-- ------------------------------------------------------------ каркас окна
local header = c:add(GUI.panel(1, 1, win.w, 2, BLUE))
local body = c:add(GUI.panel(1, 3, win.w, win.h - 4, "win"))
local statusBar = c:add(GUI.label(1, win.h - 1, " Готово", "titleText", "title", win.w))

local views, current, currentArgs = {}, "catalog", {}
local show, rerender

local function setStatus(text, kind)
  statusBar:setText(" " .. text)
  statusBar.fg = kind == "error" and "danger" or kind == "ok" and "success" or "titleText"
end

--- Показать сообщение и сразу перерисовать экран (перед долгим сетевым запросом)
local function busy(text)
  setStatus(text, "info")
  Desktop.render()
end

local function L(parent, x, y, text, fg, bg, w, align) return parent:add(GUI.label(x, y, text, fg, bg, w, align)) end
local function B(parent, x, y, w, text, fn, style) return parent:add(GUI.button(x, y, w, 1, text, fn, style)) end

local function cartCount()
  local n = 0
  for _, it in ipairs(S.cart) do n = n + it.qty end
  return n
end

local function cartTotals()
  local total = 0
  for _, it in ipairs(S.cart) do total = total + (tonumber(it.product.price) or 0) * it.qty end
  local delivery = (total > 0 and total < (CFG.free_delivery_from or 30000)) and (CFG.delivery_price or 990) or 0
  return total, delivery
end

local tabGroup = {product = "catalog", admProducts = "admProducts"}

local function buildHeader()
  header:clear()
  header.w = body.w
  header:add(GUI.label(2, 1, " RYKEA ", BLUE, YELLOW))
  header:add(GUI.label(11, 1, "Мебель и товары для дома", WHITE, BLUE))
  local who = S.user and ("● " .. tostring(S.user.name) .. (S.user.role == "admin" and " (админ)" or "")) or "Гость"
  header:add(GUI.label(max(40, win.w - unicode.len(who) - 2), 1, who, S.user and YELLOW or 0xBFD7F2, BLUE))
  local tabs = {
    {"catalog", "Каталог"},
    {"cart", "Корзина" .. (cartCount() > 0 and (" (" .. cartCount() .. ")") or "")},
    {"orders", "Мои заказы"},
    {"auth", S.user and "Аккаунт" or "Вход"},
  }
  if S.user and S.user.role == "admin" then
    tabs[#tabs + 1] = {"admProducts", "Товары"}
    tabs[#tabs + 1] = {"admOrders", "Все заказы"}
    tabs[#tabs + 1] = {"admUsers", "Пользователи"}
  end
  local x = 2
  local group = tabGroup[current] or current
  for _, t in ipairs(tabs) do
    local w = unicode.len(t[2]) + 4
    local active = group == t[1]
    local b = GUI.button(x, 2, w, 1, t[2], function() show(t[1]) end)
    b.color, b.textColor = active and YELLOW or BLUE, active and BLUE or WHITE
    header:add(b)
    x = x + w + 1
  end
end

show = function(name, ...)
  current, currentArgs = name, {...}
  body:clear()
  buildHeader()
  views[name](...)
end

rerender = function() show(current, table.unpack(currentArgs)) end

-- ------------------------------------------------------------ загрузка данных
local function loadCatalog()
  busy("Загрузка каталога из базы RYKEA…")
  local products, err = db.select("products", "&order=created_at.desc")
  if not products then
    S.catalogError = "Не удалось загрузить товары: " .. tostring(err)
    setStatus(S.catalogError, "error")
    return false
  end
  local cats, catError = db.select("categories", "&order=created_at.asc")
  if not cats then
    S.catalogError = "Не удалось загрузить категории: " .. tostring(catError)
    setStatus(S.catalogError, "error")
    return false
  end
  S.catalogError = nil
  S.products = rowsData(products)
  S.categories = rowsData(cats)
  setStatus("Загружено товаров: " .. #S.products .. ", категорий: " .. #S.categories, "ok")
  return true
end

local function addToCart(p, color)
  color = color or tostring(p.color or "—")
  for _, it in ipairs(S.cart) do
    if it.product.id == p.id and it.color == color then
      it.qty = it.qty + 1
      setStatus("Количество увеличено: " .. tostring(p.name) .. " (" .. color .. ")", "ok")
      return
    end
  end
  S.cart[#S.cart + 1] = {product = p, qty = 1, color = color}
  setStatus("Добавлено в корзину: " .. tostring(p.name) .. " (" .. color .. ")", "ok")
end

local function quickAdd(p)
  local color = tostring(p.color or "—")
  if type(p.colors) == "table" and #p.colors > 1 then
    local idx = GUI.select("Выберите цвет: " .. tostring(p.name), p.colors)
    if not idx then return end
    color = p.colors[idx]
  end
  addToCart(p, color)
  buildHeader()
end

-- ------------------------------------------------------------ картинка-«фото» товара
local ART = {
  sofa = {"..........", ".xxxxxxxx.", ".xhhhhhhx.", "xxXXXXXXxx", "xXXXXXXXXx", "xXXXXXXXXx", ".xxxxxxxx.", "..x....x.."},
  chair = {"...xxxx...", "..xhhhhx..", "..xXXXXx..", ".xxXXXXxx.", "xXXXXXXXXx", "xXXXXXXXXx", ".xxxxxxxx.", "..x....x.."},
  table = {"..........", "..........", "xxxxxxxxxx", "xhhhhhhhhx", "xxxxxxxxxx", ".x......x.", ".x......x.", ".x......x."},
  bed = {"xx........", "xx........", "xxhhhhhhh.", "xxXXXXXXXx", "xxXXXXXXXx", "xxxxxxxxxx", "xx......xx", ".........."},
  lamp = {"...xxxx...", "..xhhhhx..", ".xXXXXXXx.", ".xXXXXXXx.", "....xx....", "....xx....", "....xx....", "..xxxxxx.."},
  decor = {"..........", ".xxxxxxxx.", "xXXXXXXXXx", "xXhXXXXXXx", "xXXXXXXXXx", "xXXXXXXXXx", ".xxxxxxxx.", ".........."},
  box = {"..xxxxxx..", ".xhhhhhhx.", "xxxxxxxxxx", "xXXXXXXXXx", "xXXXXXXXXx", "xXXXXXXXXx", "xXXXXXXXXx", "xxxxxxxxxx"},
}

local function artFor(p)
  local cat = tostring(p.category or "")
  for key in pairs(ART) do
    if cat:find(key, 1, true) then return ART[key] end
  end
  if cat:find("light", 1, true) then return ART.lamp end
  return ART.box
end

local Art = GUI.class()
function Art:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, C.panel, nil, " ")
  local base = self.color
  local pal = {
    X = base,
    x = Screen.blend(0x000000, base, 0.38),
    h = Screen.blend(0xFFFFFF, base, 0.35),
  }
  local art = self.art
  local ox, oy = ax + floor((self.w - 20) / 2), ay + 1
  for r = 1, 4 do
    for col = 1, 10 do
      local tc, bc = pal[art[r * 2 - 1]:sub(col, col)], pal[art[r * 2]:sub(col, col)]
      for sx = 0, 1 do
        local x, y = ox + (col - 1) * 2 + sx, oy + r - 1
        if tc and bc then Screen.set(x, y, bc, tc, "▀")
        elseif tc then Screen.set(x, y, nil, tc, "▀")
        elseif bc then Screen.set(x, y, nil, bc, "▄") end
      end
    end
  end
end

-- ------------------------------------------------------------ КАТАЛОГ
views.catalog = function()
  local bw, bh = body.w, body.h
  if S.catalogError then
    L(body, 3, 2, "Нет подключения к базе RYKEA", "danger")
    body:add(GUI.textView(3, 4, max(20, bw - 6), 5, S.catalogError))
    B(body, 3, 10, 18, "Повторить", function()
      loadCatalog()
      rerender()
    end, "primary")
    return
  end
  local x = 2
  local function chip(label, id)
    local w = unicode.len(label) + 2
    local b = GUI.button(x, 1, w, 1, label, function() S.cat = id rerender() end)
    b.active = S.cat == id
    body:add(b)
    x = x + w + 1
  end
  chip("Все", nil)
  for _, cat in ipairs(S.categories) do chip(tostring(cat.label or cat.id), cat.id) end

  local count = L(body, bw - 24, 3, "", "dim", nil, 22, "right")
  local list = GUI.list(1, 5, bw, bh - 6, {})
  list.rowHeight = 2
  list.striped = true

  local function filtered()
    local out, q = {}, unicode.lower(S.query or "")
    for _, p in ipairs(S.products) do
      local hay = unicode.lower(tostring(p.name or "") .. " " .. tostring(p.categoryLabel or ""))
      if (not S.cat or p.category == S.cat) and (q == "" or hay:find(q, 1, true)) then out[#out + 1] = p end
    end
    return out
  end

  local function refreshList()
    local items = filtered()
    list:setItems(items)
    if list.selected == 0 and #items > 0 then list.selected = 1 end
    count:setText("Найдено: " .. #items)
  end

  body:add(GUI.input(2, 3, min(44, bw - 30), S.query, "Поиск по названию…", {onChange = function(_, t)
    S.query = t
    refreshList()
  end}))

  list.render = function(_, p, _, lx, ly, w, sel, bg)
    local fg1 = sel and C.accentText or C.text
    local fg2 = sel and C.accentText or C.dim
    local price = fmtPrice(p.price)
    local name = GUI.fit(tostring(p.name or "?"), max(8, w - unicode.len(price) - 24))
    Screen.text(lx + 1, ly, fg1, name, bg)
    if p.badge then
      Screen.text(lx + 3 + unicode.len(name), ly, sel and C.accentText or C.warning, "● " .. tostring(p.badge), bg)
    end
    Screen.text(lx + w - unicode.len(price) - 1, ly, sel and C.accentText or C.success, price, bg)
    Screen.text(lx + 1, ly + 1, fg2, GUI.fit(tostring(p.categoryLabel or ""), max(8, w - 40)), bg)
    local right = stars(p.rating) .. " " .. tostring(p.rating or "?")
    if p.oldPrice then right = "было " .. fmtPrice(p.oldPrice) .. "   " .. right end
    Screen.text(lx + w - unicode.len(right) - 1, ly + 1, fg2, right, bg)
  end
  list.onActivate = function(_, idx) show("product", list.items[idx]) end
  body:add(list)
  list:focus()

  B(body, 2, bh, 14, "Подробнее", function()
    local p = list.items[list.selected]
    if p then show("product", p) end
  end)
  B(body, 18, bh, 16, "В корзину", function()
    local p = list.items[list.selected]
    if p then quickAdd(p) end
  end, "primary")
  B(body, 36, bh, 12, "Обновить", function()
    loadCatalog()
    rerender()
  end)
  L(body, 50, bh, "Дважды щёлкните по товару, чтобы открыть карточку", "dim")
  refreshList()
end

-- ------------------------------------------------------------ КАРТОЧКА ТОВАРА
views.product = function(p)
  local bw = body.w
  local colors = (type(p.colors) == "table" and #p.colors > 0) and p.colors or {tostring(p.color or "—")}
  local state = {color = colors[1], qty = 1}
  local half = max(40, bw - 30)

  B(body, 2, 1, 12, "← Назад", function() show("catalog") end)
  L(body, 2, 3, tostring(p.name or "?"), "accent")
  L(body, 2, 4, "RYKEA  /  " .. tostring(p.categoryLabel or ""), "dim")
  local price = fmtPrice(p.price)
  L(body, 2, 6, price, "success")
  local px = 4 + unicode.len(price)
  if p.oldPrice then
    L(body, px, 6, "было " .. fmtPrice(p.oldPrice), "dim")
    px = px + unicode.len("было " .. fmtPrice(p.oldPrice)) + 2
  end
  if p.badge then L(body, px, 6, "● " .. tostring(p.badge), "warning") end
  L(body, 2, 7, stars(p.rating) .. "  " .. tostring(p.rating or "?") .. " / 5  (" .. tostring(p.reviews or 0) .. " отзывов)", "warning")
  body:add(GUI.textView(2, 9, half, 5, tostring(p.description or "")))

  L(body, 2, 15, "Цвет", "dim")
  local chips = {}
  local function paintChips()
    for _, ch in ipairs(chips) do
      ch.text = (ch.name == state.color and "✓ " or "  ") .. ch.name
    end
  end
  local cx, cy = 2, 16
  for _, name in ipairs(colors) do
    local w = unicode.len(name) + 4
    if cx + w > half + 2 then cx, cy = 2, cy + 1 end
    local hex = hexColor(name)
    local b = GUI.button(cx, cy, w, 1, name, nil)
    b.name = name
    b.color, b.textColor = hex, isLight(hex) and 0x111111 or 0xFFFFFF
    b.onClick = function()
      state.color = name
      paintChips()
      setStatus("Цвет: " .. name, "info")
    end
    chips[#chips + 1] = b
    body:add(b)
    cx = cx + w + 1
  end
  paintChips()

  local qy = cy + 2
  L(body, 2, qy, "Количество", "dim")
  local qtyLabel = L(body, 20, qy, "1", "text", nil, 3, "center")
  B(body, 14, qy, 5, " − ", function()
    state.qty = max(1, state.qty - 1)
    qtyLabel:setText(tostring(state.qty))
  end)
  B(body, 24, qy, 5, " + ", function()
    state.qty = min(99, state.qty + 1)
    qtyLabel:setText(tostring(state.qty))
  end)
  L(body, 2, qy + 2, "Доставка " .. fmtPrice(CFG.delivery_price or 990) .. ", бесплатно от " .. fmtPrice(CFG.free_delivery_from or 30000), "dim")
  L(body, 2, qy + 3, "Гарантия 10 лет  ·  Самовывоз сегодня", "dim")
  B(body, 2, qy + 5, 32, "Добавить в корзину", function()
    for _ = 1, state.qty do addToCart(p, state.color) end
    buildHeader()
  end, "primary")
  B(body, 36, qy + 5, 14, "Корзина →", function() show("cart") end)

  local art = GUI.new(Art, bw - 25, 3, 24, 8)
  art.art, art.color = artFor(p), hexColor(state.color)
  body:add(art)
  local oldPaint = paintChips
  paintChips = function()
    oldPaint()
    art.color = hexColor(state.color)
  end
  paintChips()
end

-- ------------------------------------------------------------ КОРЗИНА
local function checkout()
  if #S.cart == 0 then return end
  if not S.user then
    GUI.alert("Нужен аккаунт", "Войдите или зарегистрируйтесь, чтобы оформить заказ.")
    show("auth")
    return
  end
  local total, delivery = cartTotals()
  if not GUI.confirm("Оформление заказа", "Оформить заказ на " .. fmtPrice(total + delivery) .. "?\nДоставка: " .. (delivery == 0 and "бесплатно" or fmtPrice(delivery)), "Оформить", "Отмена") then
    return
  end
  local items = {}
  for _, it in ipairs(S.cart) do
    local p = it.product
    items[#items + 1] = {
      id = tostring(p.id or ""), name = tostring(p.name or ""), categoryLabel = tostring(p.categoryLabel or ""),
      price = tonumber(p.price) or 0, qty = it.qty, image = tostring(p.image or ""), color = tostring(it.color or ""),
    }
  end
  local orderId = "o" .. System.time() .. math.random(10, 99)
  local order = {
    id = orderId, userEmail = S.user.email, userName = S.user.name, items = items,
    total = total + delivery, delivery = delivery, status = "new", createdAt = System.isoNow(),
  }
  busy("Оформляем заказ…")
  local ok, err = db.upsert("orders", {id = orderId, data = order})
  if not ok then
    setStatus("Не удалось оформить заказ: " .. tostring(err), "error")
    return
  end
  S.cart = {}
  Desktop.notify("Заказ оформлен: " .. orderId)
  setStatus("Заказ оформлен! № " .. orderId, "ok")
  show("orders")
end

views.cart = function()
  local bw, bh = body.w, body.h
  if #S.cart == 0 then
    L(body, 3, 3, "Корзина пуста", "text")
    L(body, 3, 4, "Добавьте товары из каталога.", "dim")
    B(body, 3, 6, 22, "Перейти в каталог", function() show("catalog") end, "primary")
    return
  end
  local lw = bw - 36
  local list = body:add(GUI.list(1, 1, lw, bh, S.cart))
  list.rowHeight = 2
  list.striped = true
  list.selected = min(S.cartSel or 1, #S.cart)
  list.onSelect = function(_, idx) S.cartSel = idx end
  list.render = function(_, it, _, x, y, w, sel, bg)
    local p = it.product
    local fg1 = sel and C.accentText or C.text
    local fg2 = sel and C.accentText or C.dim
    local line = fmtPrice((tonumber(p.price) or 0) * it.qty)
    Screen.text(x + 1, y, fg1, GUI.fit(tostring(p.name), w - unicode.len(line) - 4), bg)
    Screen.text(x + w - unicode.len(line) - 1, y, sel and C.accentText or C.success, line, bg)
    Screen.text(x + 1, y + 1, fg2, "× " .. it.qty .. "   ·   " .. tostring(it.color) .. "   ·   " .. fmtPrice(p.price) .. " / шт.", bg)
  end
  list:focus()

  local rx = lw + 3
  local total, delivery = cartTotals()
  L(body, rx, 2, "Итого по заказу", "dim")
  L(body, rx, 4, "Товаров: " .. cartCount(), "text")
  L(body, rx, 5, "Сумма: " .. fmtPrice(total), "text")
  L(body, rx, 6, "Доставка: " .. (delivery == 0 and "бесплатно" or fmtPrice(delivery)), delivery == 0 and "success" or "text")
  L(body, rx, 8, fmtPrice(total + delivery), "accent")
  local function selected() return S.cart[list.selected] end
  B(body, rx, 10, 7, " + ", function()
    local it = selected()
    if it then it.qty = min(99, it.qty + 1) S.cartSel = list.selected buildHeader() rerender() end
  end)
  B(body, rx + 8, 10, 7, " − ", function()
    local it = selected()
    if it then it.qty = max(1, it.qty - 1) S.cartSel = list.selected buildHeader() rerender() end
  end)
  B(body, rx + 16, 10, 14, "Удалить", function()
    if selected() then
      table.remove(S.cart, list.selected)
      buildHeader()
      rerender()
    end
  end, "danger")
  B(body, rx, 12, 30, "Очистить корзину", function()
    if GUI.confirm("Очистка", "Удалить все товары из корзины?", "Очистить", "Отмена", true) then
      S.cart = {}
      buildHeader()
      rerender()
    end
  end)
  body:add(GUI.button(rx, 14, 30, 3, "Оформить заказ", checkout, "primary"))
end

-- ------------------------------------------------------------ ЗАКАЗЫ
local function loadOrders(all)
  busy("Загрузка заказов…")
  local rows, err = db.select("orders", "&order=created_at.desc")
  if not rows then
    setStatus("Не удалось загрузить заказы: " .. tostring(err), "error")
    S.orders = {}
    return false
  end
  S.orders = {}
  for _, o in ipairs(rowsData(rows)) do
    if all or o.userEmail == (S.user and S.user.email) then S.orders[#S.orders + 1] = o end
  end
  setStatus("Заказов: " .. #S.orders, "ok")
  return true
end

local function ordersView(all)
  local bw, bh = body.w, body.h
  if not S.user then
    L(body, 3, 3, "Войдите в аккаунт, чтобы увидеть заказы.", "text")
    B(body, 3, 5, 18, "Войти", function() show("auth") end, "primary")
    return
  end
  if not S.ordersLoaded or S.ordersLoaded ~= (all and "all" or "mine") then
    loadOrders(all)
    S.ordersLoaded = all and "all" or "mine"
  end
  if #S.orders == 0 then
    L(body, 3, 3, "Заказов пока нет.", "text")
    B(body, 3, 5, 22, "Обновить", function() S.ordersLoaded = nil rerender() end)
    return
  end
  local lw = floor(bw * 0.46)
  local list = body:add(GUI.list(1, 1, lw, bh - 2, S.orders))
  list.rowHeight = 3
  list.striped = true
  local detail = body:add(GUI.panel(lw + 2, 1, bw - lw - 1, bh, "win"))

  local function showDetail()
    detail:clear()
    local o = S.orders[list.selected]
    if not o then return end
    local st = STATUS[o.status] or {tostring(o.status), 0x9CA3AF}
    L(detail, 1, 1, "Заказ № " .. tostring(o.id), "accent")
    L(detail, 1, 2, fmtDate(o.createdAt) .. "   ·   " .. st[1], st[2])
    L(detail, 1, 3, "Клиент: " .. tostring(o.userName or "?") .. " <" .. tostring(o.userEmail or "?") .. ">", "dim")
    local y = 5
    for _, it in ipairs(o.items or {}) do
      if y > detail.h - 6 then L(detail, 1, y, "…", "dim") break end
      L(detail, 1, y, GUI.fit(tostring(it.name) .. " (" .. tostring(it.color or "—") .. ")", detail.w - 2), "text")
      L(detail, 3, y + 1, tostring(it.qty) .. " × " .. fmtPrice(it.price), "dim")
      y = y + 2
    end
    L(detail, 1, detail.h - 4, "Доставка: " .. ((tonumber(o.delivery) or 0) == 0 and "бесплатно" or fmtPrice(o.delivery)), "dim")
    L(detail, 1, detail.h - 3, "Итого: " .. fmtPrice(o.total), "success")
    if all then
      local x = 1
      for _, key in ipairs({"processing", "shipped", "done", "cancelled"}) do
        local label = STATUS[key][1]
        local w = unicode.len(label) + 2
        local b = GUI.button(x, detail.h - 1, w, 1, label, function()
          o.status = key
          busy("Обновляем статус…")
          local ok, err = db.upsert("orders", {id = o.id, data = o})
          if ok then setStatus("Статус изменён: " .. label, "ok") else setStatus("Ошибка: " .. tostring(err), "error") end
          local keep = list.selected
          rerender()
          list.selected = keep
        end, key == "cancelled" and "danger" or nil)
        b.active = o.status == key
        detail:add(b)
        x = x + w + 1
      end
    end
  end

  list.render = function(_, o, _, x, y, w, sel, bg)
    local st = STATUS[o.status] or {tostring(o.status), 0x9CA3AF}
    local fg1 = sel and C.accentText or C.text
    local fg2 = sel and C.accentText or C.dim
    Screen.text(x + 1, y, fg1, GUI.fit("№ " .. tostring(o.id), w - 4), bg)
    Screen.text(x + 1, y + 1, fg2, fmtDate(o.createdAt) .. "  ·  " .. fmtPrice(o.total), bg)
    Screen.text(x + 1, y + 2, sel and C.accentText or st[2], "● " .. st[1] .. (all and ("   " .. GUI.fit(tostring(o.userName or ""), 16)) or ""), bg)
  end
  list.onSelect = function() showDetail() end
  list.selected = 1
  list:focus()
  B(body, 2, bh, 14, "Обновить", function() S.ordersLoaded = nil rerender() end)
  showDetail()
end

views.orders = function() ordersView(false) end
views.admOrders = function() ordersView(true) end

-- ------------------------------------------------------------ АККАУНТ
local function login(email, pass)
  if email == "" or pass == "" then return nil, "Введите e-mail и пароль" end
  if CFG.admin_email and CFG.admin_pass and email == CFG.admin_email and pass == CFG.admin_pass then
    return {name = "Администратор", email = CFG.admin_email, role = "admin", password = pass}
  end
  local rows, err = db.select("users", "&id=eq." .. urlenc(email))
  if not rows then return nil, "Ошибка сети: " .. tostring(err) end
  local u = rows[1] and rows[1].data
  if not u then return nil, "Пользователь не найден" end
  if u.password ~= pass then return nil, "Неверный пароль" end
  return u
end

local function register(name, email, pass)
  if unicode.len(name) < 2 then return nil, "Введите имя" end
  if not email:match("^[^@%s]+@[^@%s]+%.[^@%s]+$") then return nil, "Некорректный e-mail" end
  if unicode.len(pass) < 6 then return nil, "Пароль должен быть не короче 6 символов" end
  if email == CFG.admin_email then return nil, "Этот e-mail зарезервирован" end
  local existing, err = db.select("users", "&id=eq." .. urlenc(email))
  if not existing then return nil, "Ошибка сети: " .. tostring(err) end
  if existing[1] then return nil, "Пользователь с таким e-mail уже существует" end
  local all = db.select("users") or {}
  local u = {name = name, email = email, password = pass, role = (#all == 0) and "admin" or "user"}
  local ok, e2 = db.upsert("users", {id = email, data = u})
  if not ok then return nil, "Не удалось создать аккаунт: " .. tostring(e2) end
  return u
end

views.auth = function(mode)
  mode = mode or S.authMode or "login"
  S.authMode = mode
  if S.user then
    L(body, 3, 2, "Вы вошли как", "dim")
    L(body, 3, 3, tostring(S.user.name), "accent")
    L(body, 3, 4, tostring(S.user.email), "text")
    L(body, 3, 5, S.user.role == "admin" and "Роль: администратор" or "Роль: покупатель", S.user.role == "admin" and "warning" or "dim")
    B(body, 3, 7, 18, "Выйти", function()
      S.user, S.ordersLoaded = nil, nil
      setStatus("Вы вышли из аккаунта.", "info")
      show("auth", "login")
    end, "danger")
    return
  end
  local isLogin = mode == "login"
  local t1 = B(body, 3, 1, 12, "Вход", function() show("auth", "login") end)
  local t2 = B(body, 17, 1, 16, "Регистрация", function() show("auth", "register") end)
  t1.active, t2.active = isLogin, not isLogin
  L(body, 3, 3, isLogin and "Рады видеть вас снова в RYKEA" or "Создайте аккаунт и получайте скидки", "dim")
  local y = 5
  local nameInput
  if not isLogin then
    L(body, 3, y, "Имя", "dim")
    nameInput = body:add(GUI.input(3, y + 1, 36, "", "Как к вам обращаться"))
    y = y + 3
  end
  L(body, 3, y, "E-mail", "dim")
  local emailInput = body:add(GUI.input(3, y + 1, 36, "", "name@example.com"))
  L(body, 3, y + 3, "Пароль", "dim")
  local passInput = body:add(GUI.input(3, y + 4, 36, "", isLogin and "Ваш пароль" or "Минимум 6 символов", {mask = true}))
  local msg = L(body, 3, y + 8, "", "danger", nil, 60)
  local function submit()
    msg:setText("")
    busy(isLogin and "Проверяем данные…" or "Регистрация…")
    local user, err
    if isLogin then user, err = login(emailInput.text, passInput.text)
    else user, err = register(nameInput.text, emailInput.text, passInput.text) end
    if not user then
      msg:setText(tostring(err))
      setStatus(tostring(err), "error")
      return
    end
    S.user, S.ordersLoaded = user, nil
    Desktop.notify("Добро пожаловать, " .. tostring(user.name) .. "!")
    setStatus("Добро пожаловать, " .. tostring(user.name) .. "!", "ok")
    show("catalog")
  end
  emailInput.onSubmit = function() passInput:focus() end
  passInput.onSubmit = submit
  if nameInput then nameInput.onSubmit = function() emailInput:focus() end end
  B(body, 3, y + 6, 36, isLogin and "Войти" or "Создать аккаунт", submit, "primary")
  body:focus()
  ;(nameInput or emailInput):focus()
  L(body, 44, 5, "База RYKEA: Supabase", "dim")
  L(body, 44, 6, "Используйте свой аккаунт RYKEA.", "text")
  L(body, 44, 7, "Изменения сохраняются в базе.", "text")
end

-- ------------------------------------------------------------ АДМИНКА: ТОВАРЫ
local function addProductDialog()
  local dlg = GUI.modalWindow("Добавить товар", 66, 24)
  local d = dlg.content
  local catIdx
  local fields = {}
  local rows = {
    {"name", "Название", ""},
    {"catLabel", "Подпись категории (например, «Диван 3-местный»)", ""},
    {"price", "Цена, руб.", ""},
    {"oldPrice", "Старая цена (необязательно)", ""},
    {"colors", "Цвета через запятую (Белый, Серый)", ""},
    {"badge", "Бейдж (Хит, Скидка…) — необязательно", ""},
    {"desc", "Описание", ""},
  }
  local y = 2
  for _, r in ipairs(rows) do
    L(d, 3, y, r[2], "dim")
    fields[r[1]] = d:add(GUI.input(3, y + 1, 60, r[3]))
    y = y + 2
  end
  local catBtn = B(d, 3, y, 40, "Категория: выбрать…", function()
    local labels = {}
    for i, cat in ipairs(S.categories) do labels[i] = tostring(cat.label or cat.id) end
    local idx = GUI.select("Категория товара", labels)
    if idx then
      catIdx = idx
      d.children[#d.children].text = "Категория: " .. labels[idx]
    end
  end)
  local function create()
    local name = fields.name.text
    if name == "" then GUI.alert("Ошибка", "Название не может быть пустым!") return end
    local colors = {}
    for col in fields.colors.text:gmatch("[^,]+") do
      local t = col:match("^%s*(.-)%s*$")
      if t ~= "" then colors[#colors + 1] = t end
    end
    local cat = catIdx and S.categories[catIdx]
    local id = "p" .. System.time() .. math.random(10, 99)
    local p = {
      id = id, name = name, category = cat and cat.id or "", categoryLabel = fields.catLabel.text,
      price = tonumber(fields.price.text) or 0, oldPrice = tonumber(fields.oldPrice.text),
      color = colors[1] or "", colors = colors, description = fields.desc.text,
      rating = 5, reviews = 0, image = "", badge = fields.badge.text ~= "" and fields.badge.text or nil,
    }
    dlg.result = p
    dlg.closed = true
  end
  B(d, 3, y + 2, 16, "Создать", create, "primary")
  B(d, 21, y + 2, 14, "Отмена", function() dlg.closed = true end)
  d.focused = fields.name
  catBtn.text = "Категория: выбрать…"
  local p = GUI.runModal(dlg)
  if p then
    busy("Сохраняем товар…")
    local ok, err = db.upsert("products", {id = p.id, data = p})
    if ok then
      loadCatalog()
      setStatus("Товар добавлен: " .. p.name, "ok")
      rerender()
    else
      setStatus("Не удалось сохранить товар: " .. tostring(err), "error")
    end
  end
end

views.admProducts = function()
  local bw, bh = body.w, body.h
  local list = body:add(GUI.list(1, 1, bw, bh - 2, S.products))
  list.striped = true
  list.render = function(_, p, idx, x, y, w, sel, bg)
    local fg = sel and C.accentText or C.text
    Screen.text(x + 1, y, sel and C.accentText or C.dim, string.format("%2d", idx), bg)
    Screen.text(x + 5, y, fg, GUI.fit(tostring(p.name), 26), bg)
    Screen.text(x + 33, y, sel and C.accentText or C.dim, GUI.fit(tostring(p.categoryLabel or ""), max(8, w - 60)), bg)
    local price = fmtPrice(p.price)
    Screen.text(x + w - unicode.len(price) - 1, y, sel and C.accentText or C.success, price, bg)
  end
  list.selected = min(1, #S.products)
  list:focus()
  B(body, 2, bh, 18, "+ Добавить товар", addProductDialog, "primary")
  B(body, 22, bh, 12, "Удалить", function()
    local p = list.items[list.selected]
    if not p then return end
    if GUI.confirm("Удаление товара", "Удалить товар «" .. tostring(p.name) .. "»?", "Удалить", "Отмена", true) then
      busy("Удаляем…")
      local ok, err = db.delete("products", tostring(p.id))
      if ok then
        loadCatalog()
        setStatus("Товар удалён.", "ok")
        rerender()
      else
        setStatus("Не удалось удалить: " .. tostring(err), "error")
      end
    end
  end, "danger")
  B(body, 36, bh, 12, "Обновить", function() if loadCatalog() then rerender() end end)
end

-- ------------------------------------------------------------ АДМИНКА: ПОЛЬЗОВАТЕЛИ
views.admUsers = function()
  local bw, bh = body.w, body.h
  busy("Загружаем пользователей…")
  local rows, err = db.select("users")
  if not rows then
    setStatus("Не удалось загрузить пользователей: " .. tostring(err), "error")
    L(body, 3, 3, "Ошибка загрузки: " .. tostring(err), "danger")
    return
  end
  local users = rowsData(rows)
  setStatus("Пользователей: " .. #users, "ok")
  L(body, 3, 2, CFG.admin_email and ("Локальный администратор " .. tostring(CFG.admin_email) .. " в базе не хранится.") or "Учётные записи загружены из базы RYKEA.", "dim")
  local list = body:add(GUI.list(1, 4, bw, bh - 5, users))
  list.striped = true
  list.render = function(_, u, idx, x, y, w, sel, bg)
    local fg = sel and C.accentText or C.text
    Screen.text(x + 1, y, fg, GUI.fit(tostring(u.name), 24), bg)
    Screen.text(x + 27, y, sel and C.accentText or C.dim, GUI.fit(tostring(u.email), max(10, w - 50)), bg)
    local role = u.role == "admin" and "администратор" or "покупатель"
    Screen.text(x + w - unicode.len(role) - 1, y, sel and C.accentText or (u.role == "admin" and C.warning or C.dim), role, bg)
  end
  list.selected = min(1, #users)
  list:focus()
  B(body, 2, bh, 24, "Сделать / снять админа", function()
    local u = users[list.selected]
    if not u then return end
    u.role = (u.role == "admin") and "user" or "admin"
    local ok, e = db.upsert("users", {id = u.email, data = u})
    setStatus(ok and ("Роль изменена: " .. tostring(u.name) .. " → " .. u.role) or ("Ошибка: " .. tostring(e)), ok and "ok" or "error")
    local keep = list.selected
    rerender()
    list.selected = keep
  end)
  B(body, 28, bh, 12, "Удалить", function()
    local u = users[list.selected]
    if u and GUI.confirm("Удаление", "Удалить пользователя " .. tostring(u.name) .. "?", "Удалить", "Отмена", true) then
      local ok, e = db.delete("users", tostring(u.email))
      setStatus(ok and "Пользователь удалён." or ("Ошибка: " .. tostring(e)), ok and "ok" or "error")
      rerender()
    end
  end, "danger")
end

-- ------------------------------------------------------------ окно: размеры и запуск
win.onResize = function(_, w, h)
  header.w = w
  body.w, body.h = w, h - 3
  statusBar.y, statusBar.w = h, w
  rerender()
end
win:resize(win.w, win.h)

win.tickInterval = Policy.pollSeconds
win.onTick = function()
  -- Закрываем только при явной блокировке; сбой сети (nil) не должен прерывать работу
  if Policy.get("rykea") == false then
    win:close()
    GUI.alert("Региональный доступ", Policy.message("rykea"))
  end
  return false
end

if not HTTP.available() then
  setStatus("ОШИБКА: нужна Internet Card!", "error")
  show("catalog")
  GUI.alert("Нужна Internet Card", "Приложение RYKEA работает с базой данных через интернет.\nУстановите в компьютер Internet Card и перезапустите приложение.")
else
  show("catalog")
  loadCatalog()
  rerender()
end
]=]},
  {"/System/Desktop.lua", [[
-- ============================================================
--  CubeOS :: Desktop
--  Рабочий стол: обои, меню-бар, док, менеджер окон,
--  цикл событий, модальные окна и запуск приложений.
-- ============================================================
local component, computer, unicode = component, computer, unicode
local Screen = require("Screen")
local GUI = require("GUI")
local System = require("System")
local Locale = require("Locale")
local C = GUI.color
local floor, max, min = math.floor, math.max, math.min

local Desktop = {}
GUI.desktop = Desktop

Desktop.windows, Desktop.modals, Desktop.toasts, Desktop.apps = {}, {}, {}, {}
Desktop.dirty, Desktop.cascade, Desktop.running = true, 0, true
Desktop.mods = {ctrl = false, shift = false, alt = false}

local W, H = 80, 25
local DOCK_H = 5
local gpu
local hits = {}
local dockLayout
local dragState, resizeState

Desktop.wallpapers = {
  {name = "Полночь", c1 = 0x0B1020, c2 = 0x5B21B6},
  {name = "Океан", c1 = 0x082F49, c2 = 0x0E9AB8},
  {name = "Закат", c1 = 0x2E1065, c2 = 0xF97316},
  {name = "Лес", c1 = 0x052E16, c2 = 0x22A35A},
  {name = "Графит", c1 = 0x0F1115, c2 = 0x4B5563},
}

local function tb(e)
  if debug and debug.traceback then return debug.traceback(tostring(e), 2) end
  return tostring(e)
end

function Desktop.screenSize() return W, H end
function Desktop.dockHeight() return DOCK_H end

function Desktop.applyTheme()
  local s = System.settings
  GUI.setTheme(s.theme, s.accent)
  Desktop.dirty = true
end

-- ------------------------------------------------------------ окна
function Desktop.top()
  for i = #Desktop.windows, 1, -1 do
    if not Desktop.windows[i].minimized then return Desktop.windows[i] end
  end
end

function Desktop.focus(win)
  for i, w in ipairs(Desktop.windows) do
    if w == win then table.remove(Desktop.windows, i) break end
  end
  win.minimized = false
  table.insert(Desktop.windows, win)
  Desktop.dirty = true
end

function Desktop.isFocused(win)
  return Desktop.top() == win and #Desktop.modals == 0
end

local function removeWindow(win)
  for i, w in ipairs(Desktop.windows) do
    if w == win then table.remove(Desktop.windows, i) break end
  end
  Desktop.dirty = true
end

function Desktop.closeWindow(win)
  if win.onClose and win.onClose(win) == false then return end
  removeWindow(win)
end

function Desktop.closeAll()
  for i = #Desktop.windows, 1, -1 do
    local w = Desktop.windows[i]
    if w then Desktop.closeWindow(w) end
  end
end

function Desktop.newWindow(ctx, w, h, title, opts)
  w, h = min(w, W), min(h, H - 1)
  local n = Desktop.cascade
  Desktop.cascade = (n + 1) % 6
  local x = max(1, floor((W - w) / 2) + 1 + (n - 2) * 3)
  local y = max(2, 2 + floor((H - DOCK_H - 1 - h) / 2) + (n - 2))
  local win = GUI.window(x, y, w, h, title)
  win.app = ctx
  if opts then for k, v in pairs(opts) do win[k] = v end end
  table.insert(Desktop.windows, win)
  Desktop.dirty = true
  return win
end

function Desktop.toggleMaximize(win)
  if not win.resizable then return end
  if win.maximized then
    local r = win.restore
    win.maximized = false
    win.x, win.y = r.x, r.y
    win:resize(r.w, r.h)
  else
    win.restore = {x = win.x, y = win.y, w = win.w, h = win.h}
    win.maximized = true
    win.x, win.y = 1, 2
    win:resize(W, H - 1 - DOCK_H)
  end
  Desktop.dirty = true
end

-- ------------------------------------------------------------ приложения
local function adler32(data)
  local a, b = 1, 0
  for i = 1, #data do
    a = (a + data:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return a, b
end

function Desktop.launch(path, args)
  local code = System.readFile(path .. "/Main.lua")
  if not code then
    GUI.alert("Ошибка запуска", "Не найден файл " .. path .. "/Main.lua")
    return
  end
  -- Existing virtual disks can still contain the unmodified RYKEA shipped by
  -- an older release. Use the updated bundled code without overwriting any
  -- installed files or the user's Config.lua. Never replace customized code.
  if path == "/Applications/RYKEA.app" and (#code == 37998 or #code == 37313) then
    local a, b = adler32(code)
    if (#code == 37998 and a == 34488 and b == 38689) or
      (#code == 37313 and a == 17911 and b == 42030) then
      local updated = System.readFile("/StorePackages/RYKEA.app/Main.lua")
      if updated then code = updated end
    end
  end
  local fn, err = load(code, "=" .. path .. "/Main.lua", "t")
  if not fn then
    GUI.alert("Синтаксическая ошибка", tostring(err))
    return
  end
  local info = System.loadData(path .. "/Info.lua") or {}
  local ctx = {path = path, info = info, title = info.title or System.basename(path), args = args or {}, Desktop = Desktop}
  ctx.window = function(w, h, title, opts) return Desktop.newWindow(ctx, w, h, title, opts) end
  local ok, e = xpcall(fn, tb, ctx)
  if not ok then Desktop.reportError(e) end
  Desktop.dirty = true
  return ctx
end

--- Перечитать список приложений (вызывать после установки из магазина)
function Desktop.refreshApps()
  Desktop.apps = System.apps()
  Desktop.dirty = true
end

function Desktop.launchById(id, args)
  for _, app in ipairs(Desktop.apps) do
    if app.id == id then
      -- single = true в Info.lua: повторный запуск активирует уже открытое окно
      if app.single then
        for i = #Desktop.windows, 1, -1 do
          local w = Desktop.windows[i]
          if w.app and w.app.path == app.path then
            w.minimized = false
            Desktop.focus(w)
            if w.onArgs then w:onArgs(args or {}) end
            return w.app
          end
        end
      end
      return Desktop.launch(app.path, args)
    end
  end
  if id == "Store" then return nil end
  -- Не установлено: если это товар магазина — открываем магазин на нём
  local store
  for _, app in ipairs(Desktop.apps) do if app.id == "Store" then store = app end end
  if store then
    Desktop.notify("«" .. tostring(id) .. "» не установлено — открываю магазин")
    return Desktop.launch(store.path, {focus = id})
  end
end

local function appWindows(app)
  local list = {}
  for _, w in ipairs(Desktop.windows) do
    if w.app and w.app.path == app.path then list[#list + 1] = w end
  end
  return list
end

function Desktop.launchOrFocus(app)
  local ws = appWindows(app)
  if #ws > 0 then
    for _, w in ipairs(ws) do w.minimized = false end
    Desktop.focus(ws[#ws])
  else
    Desktop.launch(app.path)
  end
end

--- Открыть файл подходящим приложением
function Desktop.openFile(path)
  if path:match("%.app/?$") then
    Desktop.launch((path:gsub("/$", "")))
  elseif path:match("%.cpic$") then
    Desktop.launchById("Paint", {file = path})
  else
    Desktop.launchById("Editor", {file = path})
  end
end

function Desktop.reportError(err)
  if Desktop.inError then return end
  Desktop.inError = true
  pcall(GUI.alert, "Ошибка в приложении", tostring(err))
  Desktop.inError = false
end

function Desktop.notify(text)
  Desktop.toasts[#Desktop.toasts + 1] = {text = tostring(text), expires = computer.uptime() + 4}
  Desktop.dirty = true
end

function Desktop.showText(title, text)
  local w, h = min(W - 4, 76), min(H - 6, 24)
  local win = GUI.modalWindow(title, w, h)
  local c = win.content
  c:add(GUI.textView(2, 2, w - 3, h - 5, text))
  c:add(GUI.button(floor((w - 14) / 2) + 1, h - 2, 14, 1, "Закрыть", function() win.closed = true end, "primary"))
  win.onEnter = function() win.closed = true end
  GUI.runModal(win)
end

--- Выполнить Lua-файл и показать вывод
function Desktop.runScript(path)
  local code, err = System.readFile(path)
  if not code then GUI.alert("Ошибка", tostring(err)) return end
  local ok, out = System.runLua(code, path, {Desktop = Desktop, GUI = GUI, System = System})
  Desktop.showText((ok and "Готово: " or "Ошибка: ") .. System.basename(path), out ~= "" and out or "(скрипт ничего не вывел)")
end

function Desktop.maxResolution()
  return gpu.maxResolution()
end

function Desktop.setResolution(w, h)
  local ok = pcall(gpu.setResolution, w, h)
  if not ok then return false end
  W, H = gpu.getResolution()
  Screen.init(gpu, W, H)
  for _, win in ipairs(Desktop.windows) do
    if win.maximized then
      win.x, win.y = 1, 2
      win:resize(W, H - 1 - DOCK_H)
    end
    win.x = max(1, min(win.x, W - 10))
    win.y = max(2, min(win.y, H - 3))
  end
  Desktop.dirty = true
  return true
end

-- ------------------------------------------------------------ системные окна
function Desktop.about()
  local used, total = System.memory()
  local fs = System.fs
  local arch = (computer.getArchitecture and computer.getArchitecture()) or "Lua 5.3"
  GUI.alert("О системе", string.format(
    "CubeOS %s  (сборка %s)\n%s\nMinecraft: %s  ·  %s\n\nОЗУ: %s из %s\nЭкран: %d×%d (монитор Tier %d)\nДиск: занято %s из %s\nВремя работы: %s",
    System.version, System.build,
    System.platform or "OpenComputers",
    System.minecraft or "1.20.1",
    arch,
    System.formatSize(used), System.formatSize(total), W, H, System.screenTier or 3,
    System.formatSize(fs.spaceUsed()), System.formatSize(fs.spaceTotal()), System.uptimeText()))
end

function Desktop.welcome()
  local ctx = {path = "/System/Welcome", title = Locale.t("welcome")}
  local win = Desktop.newWindow(ctx, 58, 21, Locale.t("welcome"))
  local c = win.content
  c:add(GUI.label(3, 2, "CubeOS " .. System.version .. "  ·  " .. (System.platformShort or "OCCE"), "accent"))
  c:add(GUI.textView(3, 4, 53, 11, Locale.t("intro") .. "\n\n" ..
    (System.platform or "OpenComputers") .. "\n" ..
    Locale.t("region") .. ": " .. System.regionName(System.settings.region) .. "  ·  " ..
    Locale.t("language") .. ": " .. System.languageName(System.settings.language)))
  c:add(GUI.button(3, 17, 22, 1, Locale.t("openStore"), function()
    win:close()
    Desktop.launchById("Store")
  end, "primary"))
  c:add(GUI.button(28, 17, 14, 1, Locale.t("understood"), function() win:close() end))
  win.onClose = function()
    System.settings.welcomed = true
    System.saveSettings()
  end
end

-- ------------------------------------------------------------ рисование
local function lerpWallpaper()
  local wp = Desktop.wallpapers[System.settings.wallpaper] or Desktop.wallpapers[1]
  GUI.gradient(1, 1, W, H, wp.c1, wp.c2)
end

local function trayText()
  local used, total = System.memory()
  local t = "RAM " .. floor(used / total * 100) .. "%"
  local e, me = computer.energy(), computer.maxEnergy()
  if me and me > 0 and me < math.huge then t = t .. "   BAT " .. floor(e / me * 100) .. "%" end
  return t .. "   " .. System.clock() .. " "
end

local function systemMenu()
  return {
    {text = "О системе CubeOS", action = Desktop.about},
    {text = "Настройки…", action = function() Desktop.launchById("Settings") end},
    {text = "Системный монитор", action = function() Desktop.launchById("Monitor") end},
    {separator = true},
    {text = "Закрыть все окна", action = Desktop.closeAll},
    {separator = true},
    {text = "Перезагрузить", action = function()
      if GUI.confirm("Перезагрузка", "Перезагрузить компьютер?") then computer.shutdown(true) end
    end},
    {text = "Выключить", action = function()
      if GUI.confirm("Выключение", "Выключить компьютер?") then computer.shutdown() end
    end},
  }
end

local function drawMenubar()
  Screen.rect(1, 1, W, 1, C.menubar, nil, " ")
  hits = {}
  local x = 1
  local function item(text, fg, menu)
    local len = unicode.len(text)
    Screen.text(x, 1, fg, text, C.menubar)
    hits[#hits + 1] = {x1 = x, x2 = x + len - 1, menu = menu}
    x = x + len
  end
  item(" ◆ CubeOS ", C.accent, systemMenu)
  local top = Desktop.top()
  if top then
    local name = top.app and top.app.title or top.title or ""
    item(" " .. GUI.fit(name, 24) .. " ", C.menubarText, nil)
    if top.menu then
      for _, m in ipairs(top.menu) do item(" " .. m.title .. " ", C.dim, m.items) end
    end
  end
  local tray = trayText()
  Screen.text(W - unicode.len(tray), 1, C.menubarText, tray, C.menubar)
end

local function dockGeometry()
  local n = max(1, #Desktop.apps)
  local spacing = 10
  if n * spacing + 2 > W - 2 then spacing = max(9, floor((W - 4) / n)) end
  local w = n * spacing + 2
  return {x = floor((W - w) / 2) + 1, y = H - DOCK_H + 1, w = w, spacing = spacing}
end

local function drawDock()
  local g = dockGeometry()
  dockLayout = g
  Screen.rect(g.x, g.y, g.w, DOCK_H, 0x000000, nil, nil, 0.55)
  for i, app in ipairs(Desktop.apps) do
    local cell = g.x + 1 + (i - 1) * g.spacing
    if app.icon then GUI.drawIcon(cell + floor((g.spacing - 8) / 2), g.y, app.icon) end
    local running = #appWindows(app) > 0
    local label = GUI.fit(app.short or app.title or app.id, g.spacing - 1)
    local lx = cell + floor((g.spacing - unicode.len(label)) / 2)
    Screen.text(lx, g.y + 4, running and 0xFFFFFF or 0xA6ADBB, label)
    if running then Screen.text(lx - 1, g.y + 4, 0x3DDC84, "●") end
  end
end

local function drawToasts()
  for i, t in ipairs(Desktop.toasts) do
    local w = unicode.len(t.text) + 4
    local x, y = W - w - 1, 1 + (i - 1) * 3 + 1
    Screen.rect(x + 1, y + 1, w, 3, 0x000000, nil, nil, 0.5)
    Screen.rect(x, y, w, 3, C.title, nil, " ")
    Screen.rect(x, y, 1, 3, C.accent, nil, " ")
    Screen.text(x + 2, y + 1, C.titleText, t.text, C.title)
  end
end

function Desktop.render()
  Screen.resetClip()
  lerpWallpaper()
  local top = Desktop.top()
  local bad
  for _, w in ipairs(Desktop.windows) do
    if not w.minimized then
      Screen.resetClip()
      local ok, err = xpcall(w.draw, tb, w, w == top and #Desktop.modals == 0)
      if not ok then bad = bad or {} bad[#bad + 1] = {w, err} end
    end
  end
  Screen.resetClip()
  drawDock()
  drawMenubar()
  drawToasts()
  for _, m in ipairs(Desktop.modals) do
    Screen.resetClip()
    if not m.noDim then Screen.rect(1, 1, W, H, 0x000000, nil, nil, 0.45) end
    local ok, err = xpcall(m.draw, tb, m, true)
    if not ok then
      m.closed = true
      bad = bad or {}
      bad[#bad + 1] = {nil, err}
    end
  end
  Screen.resetClip()
  Screen.update()
  if bad then
    for _, b in ipairs(bad) do
      if b[1] then removeWindow(b[1]) end
      Desktop.reportError(b[2])
    end
  end
end

-- ------------------------------------------------------------ события
local function menubarTouch(e)
  for _, h in ipairs(hits) do
    if h.menu and e.x >= h.x1 and e.x <= h.x2 then
      local items = type(h.menu) == "function" and h.menu() or h.menu
      GUI.menu(h.x1, 2, items)
      return
    end
  end
end

local function dockTouch(e)
  local g = dockLayout
  if not g or e.x < g.x + 1 or e.x > g.x + g.w - 2 then return end
  local app = Desktop.apps[floor((e.x - g.x - 1) / g.spacing) + 1]
  if not app then return end
  if e.button == 1 then
    GUI.menu(e.x, e.y - 4, {
      {text = "Открыть", action = function() Desktop.launchOrFocus(app) end},
      {text = "Новое окно", action = function() Desktop.launch(app.path) end},
      {separator = true},
      {text = "Закрыть окна", action = function()
        for _, w in ipairs(appWindows(app)) do Desktop.closeWindow(w) end
      end},
    })
  else
    Desktop.launchOrFocus(app)
  end
end

local function windowAt(x, y)
  for i = #Desktop.windows, 1, -1 do
    local w = Desktop.windows[i]
    if not w.minimized and w:hit(x, y) then return w end
  end
end

local function onTouch(e)
  if e.y == 1 then return menubarTouch(e) end
  if dockLayout and e.y >= dockLayout.y and e.x >= dockLayout.x and e.x < dockLayout.x + dockLayout.w then
    return dockTouch(e)
  end
  local win = windowAt(e.x, e.y)
  if not win then
    if e.button == 1 then
      GUI.menu(e.x, e.y, {
        {text = "Настройки…", action = function() Desktop.launchById("Settings") end},
        {text = "Файлы", action = function() Desktop.launchById("Finder") end},
        {separator = true},
        {text = "О системе", action = Desktop.about},
      })
    end
    return
  end
  if win ~= Desktop.top() then Desktop.focus(win) end
  if e.y == win.y then
    local rx = e.x - win.x
    if rx == 1 then
      Desktop.closeWindow(win)
    elseif rx == 3 then
      win.minimized = true
    elseif rx == 5 then
      Desktop.toggleMaximize(win)
    elseif not win.maximized then
      dragState = {win = win, dx = e.x - win.x, dy = e.y - win.y}
    end
    return
  end
  if win.resizable and not win.maximized and e.y == win.y + win.h - 1 and e.x >= win.x + win.w - 2 then
    resizeState = {win = win}
    return
  end
  win:dispatch(e)
end

local function onDrag(e)
  if dragState then
    local win = dragState.win
    win.x = max(2 - win.w + 8, min(W - 8, e.x - dragState.dx))
    win.y = max(2, min(H - 2, e.y - dragState.dy))
  elseif resizeState then
    local win = resizeState.win
    win:resize(max(win.minW, min(W - win.x + 1, e.x - win.x + 1)), max(win.minH, min(H - win.y + 1, e.y - win.y + 1)))
  else
    local win = Desktop.top()
    if win then win:dispatch(e) end
  end
end

local function onDrop(e)
  if dragState or resizeState then
    dragState, resizeState = nil, nil
    return
  end
  local win = Desktop.top()
  if win then win:dispatch(e) end
end

local function dispatch(e)
  Desktop.dirty = true
  local modal = Desktop.modals[#Desktop.modals]
  if modal then
    modal:event(e)
    return
  end
  local t = e.type
  if t == "touch" then onTouch(e)
  elseif t == "drag" then onDrag(e)
  elseif t == "drop" then onDrop(e)
  elseif t == "scroll" then
    local win = windowAt(e.x, e.y)
    if win then win:dispatch(e) end
  else
    local win = Desktop.top()
    if win then win:keyEvent(e) end
  end
end

local function handleSignal(sig)
  local name = sig[1]
  if name == "key_down" or name == "key_up" then
    local code, down = sig[4], name == "key_down"
    local m = Desktop.mods
    if code == 29 or code == 157 then m.ctrl = down
    elseif code == 42 or code == 54 then m.shift = down
    elseif code == 56 or code == 184 then m.alt = down end
    if down then
      dispatch({type = "key", char = sig[3], code = code, ctrl = m.ctrl, shift = m.shift, alt = m.alt})
    else
      -- MineOS compatibility modules need key_up to track Keyboard.isKeyDown.
      -- Keep native widgets on the existing key-down path to avoid duplicate input.
      local win = Desktop.top()
      if win and win.onKeyUp then
        win:onKeyUp({type = "key_up", char = sig[3], code = code, ctrl = m.ctrl, shift = m.shift, alt = m.alt})
      end
    end
  elseif name == "touch" or name == "drag" or name == "drop" then
    dispatch({type = name, x = sig[3], y = sig[4], button = sig[5], player = sig[6]})
  elseif name == "scroll" then
    dispatch({type = "scroll", x = sig[3], y = sig[4], dir = sig[5]})
  elseif name == "clipboard" then
    dispatch({type = "paste", text = sig[3]})
  elseif name == "cubeos_launch" then
    -- внешний сигнал: computer.pushSignal("cubeos_launch", id, "focus", "товар")
    local args
    if sig[3] ~= nil then args = {[tostring(sig[3])] = sig[4]} end
    Desktop.launchById(tostring(sig[2]), args)
    Desktop.dirty = true
  elseif name == "cubeos_install_app" then
    -- мост с сайта: установить приложение из JSON и (по умолчанию) запустить
    local spec = require("JSON").decode(tostring(sig[2] or ""))
    if type(spec) ~= "table" then
      Desktop.notify("Установка с сайта: не удалось разобрать данные")
    else
      local path, e = System.installApp(spec)
      if not path then
        Desktop.reportError("Не удалось установить приложение: " .. tostring(e))
      else
        Desktop.refreshApps()
        Desktop.notify("Установлено с сайта: " .. tostring(spec.title or spec.id))
        if spec.run ~= false then Desktop.launchById(System.safeAppId(spec.id)) end
      end
    end
    Desktop.dirty = true
  end
end

function Desktop.runModal(modal)
  modal.closed = false
  Desktop.modals[#Desktop.modals + 1] = modal
  Desktop.dirty = true
  while not modal.closed do
    Desktop.step(0.5)
  end
  for i, m in ipairs(Desktop.modals) do
    if m == modal then table.remove(Desktop.modals, i) break end
  end
  Desktop.dirty = true
  return modal.result
end

function Desktop.step(maxWait)
  local timeout = maxWait or 1
  for _, w in ipairs(Desktop.windows) do
    if w.onTick and w.tickInterval then timeout = min(timeout, w.tickInterval) end
  end
  if #Desktop.toasts > 0 then timeout = min(timeout, 0.5) end
  if Desktop.dirty then timeout = 0 end

  local sig = table.pack(computer.pullSignal(timeout))
  local n = 0
  while sig.n > 0 do
    local ok, err = xpcall(handleSignal, tb, sig)
    if not ok then Desktop.reportError(err) end
    n = n + 1
    if n >= 40 then break end
    sig = table.pack(computer.pullSignal(0))
  end

  local now = computer.uptime()
  local snapshot = {}
  for i, w in ipairs(Desktop.windows) do snapshot[i] = w end
  for _, w in ipairs(snapshot) do
    if w.onTick and now - (w.lastTick or 0) >= (w.tickInterval or 1) then
      w.lastTick = now
      local ok, res = xpcall(w.onTick, tb, w)
      if not ok then
        w.onTick = nil
        Desktop.reportError(res)
      elseif res then
        Desktop.dirty = true
      end
    end
  end

  for i = #Desktop.toasts, 1, -1 do
    if Desktop.toasts[i].expires < now then
      table.remove(Desktop.toasts, i)
      Desktop.dirty = true
    end
  end

  local tray = trayText()
  if tray ~= Desktop.lastTray then
    Desktop.lastTray = tray
    Desktop.dirty = true
  end

  if Desktop.dirty then
    Desktop.dirty = false
    Desktop.render()
  end
end

function Desktop.run()
  gpu = component.proxy(component.list("gpu")())
  W, H = gpu.getResolution()
  Screen.init(gpu, W, H)
  Desktop.applyTheme()
  for _, p in ipairs({"/Users", "/Users/Documents", "/Users/Desktop"}) do System.mkdirs(p) end
  Desktop.apps = System.apps()
  if not System.settings.region then
    local regions, languages = {}, {}
    for _, r in ipairs(System.regions) do regions[#regions + 1] = r.name end
    for _, l in ipairs(System.languages) do languages[#languages + 1] = l.name end
    local region
    repeat region = GUI.select("Первый запуск: выберите регион", regions) until region
    local language
    repeat language = GUI.select("Выберите язык / Select language / 选择语言", languages) until language
    System.settings.region = System.regions[region].id
    System.settings.language = System.languages[language].id
    System.saveSettings()
  end
  Desktop.notify("Добро пожаловать, " .. tostring(System.settings.username) .. "!")
  if not System.settings.welcomed then Desktop.welcome() end
  Desktop.render()
  while Desktop.running do
    Desktop.step(1)
  end
end

return Desktop
]]},
  {"/Users/Desktop/Заметка.txt", [[
Добро пожаловать в CubeOS!

Правый клик по рабочему столу, по иконке в доке и по файлам
открывает контекстное меню.
]]},
  {"/Users/Documents/hello.lua", [[
-- Пример скрипта CubeOS. Откройте в Редакторе и нажмите F5.
-- Внутри доступны глобальные Desktop, GUI и System.

print("Привет из CubeOS " .. System.version .. "!")
print("Сейчас: " .. System.date("%d.%m.%Y %H:%M:%S"))

local used, total = System.memory()
print(string.format("ОЗУ занято: %s из %s", System.formatSize(used), System.formatSize(total)))

for i = 1, 5 do
  print(i .. "² = " .. i * i)
end

Desktop.notify("Скрипт hello.lua выполнен")
]]},
  {"/Users/Documents/README.txt", [[
CubeOS — графическая оболочка для OpenComputers
================================================

Это ваша папка «Документы». Здесь лежат примеры:

  hello.lua   — простой скрипт (откройте в Редакторе и нажмите F5)
  window.lua  — скрипт, который создаёт собственное окно

CubeOS 1.2 — магазин
  Магазин — игры и приложения на Supabase: вход в аккаунт (первый
  зарегистрированный становится разработчиком), шаблоны MineOS и CubeOS,
  установка в /Applications одним кликом.

При установке выберите регион (Россия, Беларусь, Китай и др.) и язык
(русский, английский или китайский). При ручной установке это сделает
мастер первого запуска. Регион хранится в /Users/Settings.cfg.
Разработчик может включать и отключать Магазин и RYKEA по регионам
в магазине, вкладка «Регионы» (только для разработчика), или на сайте.
Правила хранятся в облаке (Supabase) и действуют на всех компьютерах:
при запуске и в уже открытых окнах (проверка раз в 10 секунд).
Для них не нужна отдельная таблица: правило — служебная строка
store_games (категория system); строка есть — сервис отключён.
]]},
  {"/Users/Documents/window.lua", [[
-- Пример: своё окно на GUI-библиотеке CubeOS.
-- Выполните через Редактор (F5) или Терминал: run /Users/Documents/window.lua

local win = Desktop.newWindow({title = "Мой скрипт"}, 40, 10, "Привет, мир!")
local c = win.content
local clicks = 0

local label = c:add(GUI.label(3, 3, "Нажатий: 0", "text"))
c:add(GUI.button(3, 5, 20, 3, "Нажми меня", function()
  clicks = clicks + 1
  label:setText("Нажатий: " .. clicks)
end, "primary"))
]]},
}

local function ask(prompt)
  io.write(prompt)
  return io.read()
end

print("=== Установка CubeOS ===")
print()

local disks = {}
for address in component.list("filesystem") do
  local proxy = component.proxy(address)
  if address ~= computer.tmpAddress() and not proxy.isReadOnly() and proxy.spaceTotal() >= 300 * 1024 then
    disks[#disks + 1] = {address = address, proxy = proxy, label = proxy.getLabel() or "(без имени)"}
  end
end

if #disks == 0 then
  print("Не найдено подходящих дисков (нужен записываемый диск от 300 КБ).")
  return
end

for i, d in ipairs(disks) do
  print(string.format("  %d) %s  %-16s  %d КБ", i, d.address:sub(1, 8), d.label, math.floor(d.proxy.spaceTotal() / 1024)))
end
print()

local choice = tonumber(ask("Номер диска для установки: "))
local disk = disks[choice or 0]
if not disk then
  print("Отменено.")
  return
end

local editions = {
  {"occe_1_20_1", "OpenComputers Community Edition (Minecraft 1.20.1, монитор Tier 4 190x60)"},
  {"classic", "OpenComputers Classic (Minecraft 1.7.10 / 1.12.2, монитор Tier 3 160x50)"},
}
local regions = {
  {"ru", "Россия"}, {"by", "Беларусь"}, {"cn", "Китай"},
  {"kz", "Казахстан"}, {"ua", "Украина"}, {"us", "США"},
  {"eu", "Европа"}, {"other", "Другие страны"},
}
local languages = {{"ru", "Русский"}, {"en", "English"}, {"zh", "中文 (Chinese)"}}

local defEdNum = ("occe_1_20_1" == "classic") and 2 or 1
print("Выберите версию OpenComputers:")
for i, item in ipairs(editions) do
  print("  " .. i .. ") " .. item[2] .. (i == defEdNum and " [по умолчанию]" or ""))
end
local edChoice = tonumber(ask("Номер версии [Enter = " .. defEdNum .. "]: "))
local edition = editions[edChoice or defEdNum] or editions[1]

print()
local defRegNum = 1
for i, item in ipairs(regions) do if item[1] == "ru" then defRegNum = i break end end
print("Выберите регион:")
for i, item in ipairs(regions) do
  print("  " .. i .. ") " .. item[2] .. (i == defRegNum and " [по умолчанию]" or ""))
end
local regChoice = tonumber(ask("Номер региона [Enter = " .. defRegNum .. "]: "))
local region = regions[regChoice or defRegNum] or regions[1]

print()
local defLangNum = 1
for i, item in ipairs(languages) do if item[1] == "ru" then defLangNum = i break end end
print("Выберите язык / Select language / 选择语言:")
for i, item in ipairs(languages) do
  print("  " .. i .. ") " .. item[2] .. (i == defLangNum and " [по умолчанию]" or ""))
end
local langChoice = tonumber(ask("Номер языка [Enter = " .. defLangNum .. "]: "))
local language = languages[langChoice or defLangNum] or languages[1]

local answer = ask("Файлы CubeOS будут записаны на диск " .. disk.address:sub(1, 8) .. ". Продолжить? [y/N] ")
if (answer or ""):lower() ~= "y" then
  print("Отменено.")
  return
end

local proxy = disk.proxy
for i, file in ipairs(FILES) do
  local path, data = file[1], file[2]
  local dir = path:match("^(.*)/[^/]*$")
  if dir and dir ~= "" then proxy.makeDirectory(dir) end
  local handle, reason = proxy.open(path, "w")
  if not handle then error("Не удалось создать " .. path .. ": " .. tostring(reason)) end
  proxy.write(handle, data)
  proxy.close(handle)
  io.write(string.format("\r[%d/%d] %-60s", i, #FILES, path))
end

print()
print()
-- Сохраняем выбор при установке, не стирая остальные настройки существующего диска.
local settings = {}
local existing = proxy.open("/Users/Settings.cfg", "r")
if existing then
  local chunks = {}
  while true do
    local chunk = proxy.read(existing, math.huge)
    if not chunk then break end
    chunks[#chunks + 1] = chunk
  end
  proxy.close(existing)
  local fn = load("return " .. table.concat(chunks), "=settings", "t", {})
  if fn then
    local ok, saved = pcall(fn)
    if ok and type(saved) == "table" then settings = saved end
  end
end
settings.region, settings.language, settings.edition = region[1], language[1], edition[1]
local function serialize(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
  return "nil"
end
local parts = {}
for k, v in pairs(settings) do
  if type(k) == "string" and k:match("^[%a_][%w_]*$") then
    parts[#parts + 1] = k .. "=" .. serialize(v)
  end
end
proxy.makeDirectory("/Users")
local settingsFile = assert(proxy.open("/Users/Settings.cfg", "w"))
assert(proxy.write(settingsFile, "{" .. table.concat(parts, ",") .. "}"))
proxy.close(settingsFile)
computer.setBootAddress(disk.address)
print("Готово! CubeOS установлена. Компьютер перезагрузится...")
os.sleep(2)
computer.shutdown(true)
