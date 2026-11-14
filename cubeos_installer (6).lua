-- ============================================================
--  CubeOS — автономный установщик (OpenOS)
--  Внутри — полный исходный код системы (52 файлов, 474 КБ),
--  записанный обычными текстовыми блоками. Никаких сжатых данных:
--  файл можно читать, искать по нему и проверять перед запуском.
--
--  Запуск в OpenOS:
--    pastebin get ID_ВАШЕЙ_ПАСТЫ cubeos.lua
--    lua cubeos.lua
--  Установщик спросит диск, запишет файлы и настроит загрузку.
--  Интернет для установки не нужен (только чтобы скачать файл).
-- ============================================================
local component = require("component")
local computer = require("computer")
local floor = math.floor

local FILES = {
  {"/init.lua", [[
-- ----------
--  CubeOS  —  загрузчик  (/init.lua)
--  Стандартный BIOS OpenComputers находит этот файл на диске
--  и запускает его. Здесь нет OpenOS: ядро, require, файловая
--  система, графика и рабочий стол — всё написано с нуля.
--
--  Минимум: Tier 2 (видеокарта и экран 80×25, процессор Tier 2, Lua 5.3).
--  Рекомендуется Tier 3 (160×50, 256 цветов, точная мышь).
--
--  Надёжность:
--   • разрешение подбирается под объём ОЗУ (буфер экрана «дорогой»);
--   • флаг /Users/.booting: если прошлая загрузка оборвалась — запуск
--     в БЕЗОПАСНОМ РЕЖИМЕ (настройки по умолчанию, без своих обоев/разрешения);
--   • ошибки пишутся в /Users/Logs/system.log;
--   • экран ошибки предлагает перезагрузку или сброс настроек.
-- ----------
local component, computer, unicode = component, computer, unicode

local boot = component.proxy(computer.getBootAddress())

local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()
if not gpuAddress then error("CubeOS: нет видеокарты") end
if not screenAddress then error("CubeOS: нет монитора") end

local gpu = component.proxy(gpuAddress)
gpu.bind(screenAddress)

-- ----------
--  Безопасный режим
-- ----------
local BOOT_FLAG = "/Users/.booting"
SAFE_MODE = boot.exists(BOOT_FLAG) and true or false

local function touchFlag()
  pcall(function()
    boot.makeDirectory("/Users")
    local h = boot.open(BOOT_FLAG, "w")
    if h then boot.write(h, "1") boot.close(h) end
  end)
end
touchFlag()

-- ----------
--  Разрешение под объём памяти
-- ----------
local maxW, maxH = gpu.maxResolution()

-- CubeOS работает начиная с Tier 2 (80×25, 16 цветов). Tier 1 (50×16)
-- для рабочего стола слишком мал — сообщаем об этом прямо, а не виснем.
if maxW < 80 or maxH < 25 then
  error("CubeOS: нужны видеокарта и экран Tier 2 или выше (минимум 80×25)")
end

-- {ширина, высота, минимум ОЗУ в КБ}
local PRESETS = {{160, 50, 1500}, {140, 44, 1250}, {120, 40, 1000}, {100, 32, 750}, {80, 25, 0}}
local total = computer.totalMemory()
local W, H = math.min(maxW, 80), math.min(maxH, 25)
for _, p in ipairs(PRESETS) do
  if total >= p[3] * 1024 and p[1] <= maxW and p[2] <= maxH then
    W, H = p[1], p[2]
    break
  end
end
gpu.setResolution(W, H)
-- На Tier 2 это даст глубину 4 (16 цветов), на Tier 3 — глубину 8.
pcall(gpu.setDepth, gpu.maxDepth())

-- ----------
--  Заставка
-- ----------
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
  local cx, cy = math.floor(W / 2), math.max(4, math.floor(H / 2) - 4)
  if progress == 0 then
    fill(1, 1, W, H, BG)
    fill(cx - 7, cy - 3, 14, 2, 0x86EFAC) -- верхняя грань куба
    fill(cx - 7, cy - 1, 7, 5, 0x22C55E)  -- левая грань
    fill(cx, cy - 1, 7, 5, 0x15803D)      -- правая грань
    center(cy + 6, "C U B E   O S", 0xE2E8F0, BG)
    if SAFE_MODE then center(cy + 7, "безопасный режим", 0xFAA61A, BG) end
  end
  local bw = 32
  local bx = math.floor((W - bw) / 2) + 1
  local by = math.min(H - 3, cy + 9)
  fill(bx, by, bw, 1, 0x1E293B)
  fill(bx, by, math.floor(bw * progress), 1, 0x22C55E)
  fill(1, by + 2, W, 1, BG)
  center(by + 2, status or "", 0x64748B, BG)
end

-- ----------
--  Чтение файлов и собственный require
-- ----------
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

-- ----------
--  Журнал ошибок (на случай, когда System ещё не загружен)
-- ----------
local function logError(text)
  pcall(function()
    boot.makeDirectory("/Users")
    boot.makeDirectory("/Users/Logs")
    local path = "/Users/Logs/system.log"
    if boot.exists(path) and boot.size(path) > 24 * 1024 then
      boot.remove(path .. ".old")
      boot.rename(path, path .. ".old")
    end
    local h = boot.open(path, "a")
    if h then
      boot.write(h, "[boot] " .. tostring(text):gsub("\n", " | ") .. "\n")
      boot.close(h)
    end
  end)
end

-- ----------
--  Экран критической ошибки
-- ----------
local function crash(err)
  logError(err)
  pcall(function() boot.remove(BOOT_FLAG) end)
  gpu.setBackground(0x1D4ED8)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, W, H, " ")
  gpu.set(3, 2, "CubeOS: критическая ошибка системы")
  gpu.setForeground(0xBFDBFE)
  local y = 4
  for line in (tostring(err):gsub("\t", "  ") .. "\n"):gmatch("(.-)\n") do
    if y > H - 5 then break end
    gpu.set(3, y, unicode.sub(line, 1, W - 4))
    y = y + 1
  end
  gpu.setForeground(0xFFFFFF)
  gpu.set(3, H - 3, "Ошибка записана в /Users/Logs/system.log")
  gpu.set(3, H - 2, "[Enter] перезагрузка     [R] сбросить настройки и перезагрузить")
  while true do
    local signal, _, char, code = computer.pullSignal()
    if signal == "key_down" then
      if code == 19 then -- R
        pcall(function() boot.remove("/Users/Settings.cfg") end)
        computer.shutdown(true)
      elseif code == 28 or code == 156 then
        computer.shutdown(true)
      end
    end
  end
end

-- ----------
--  Запуск
-- ----------
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
  {"/Applications/Browser.app/Info.lua", [[
return {
  title = "Браузер", short = "Браузер", order = 0.5,
  desc = "Открывает настоящие сайты через Internet Card: вкладки, поиск, формы, закладки, загрузки.",
  icon = {
    pal = {b = 0x2A86D8, g = 0x4CA02C, w = 0xFFFFFF},
    "..bbbb..",
    ".bggbbb.",
    "bbgggwbb",
    "bgggggbb",
    "bbggwgbb",
    ".bggbbb.",
    ".bbbbbb.",
    "..bbbb..",
  },
}
]]},
  {"/Applications/Browser.app/Main.lua", [=[
-- ----------
--  Браузер CubeOS
--  Открывает настоящие сайты через Internet Card: вкладки, адресная строка
--  с поиском, ссылки, формы, закладки, история, скачивание файлов,
--  кодировки (UTF-8 / windows-1251), Markdown, локальные файлы (file://).
--  JavaScript не выполняется, картинки показываются как [подпись].
--
--  Всё неблокирующее: сеть и разбор страницы идут порциями из onTick,
--  поэтому окно живёт, пока страница грузится (Esc — остановить).
-- ----------
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local HTTP = require("HTTP")
local HTML = require("HTML")
local computer, unicode = computer, unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min
local ulen, usub = unicode.len, unicode.sub
local clock = os.clock or computer.uptime

local DIR = "/Users/Browser"
local DOWNLOADS = "/Users/Downloads"
System.mkdirs(DIR)
System.mkdirs(DOWNLOADS)

-- ---------- настройки, закладки, история
local prefs = System.loadData(DIR .. "/prefs.lua")
if type(prefs) ~= "table" then prefs = {} end
prefs.engine = prefs.engine or 1
prefs.bookmarks = prefs.bookmarks or {
  {title = "Example Domain", url = "https://example.com/"},
  {title = "Документация OpenComputers", url = "https://ocdoc.cil.li/"},
  {title = "Википедия", url = "https://ru.wikipedia.org/"},
  {title = "Новости технологий", url = "https://news.ycombinator.com/"},
  {title = "NPR (текстовая версия)", url = "https://text.npr.org/"},
}
local history = System.loadData(DIR .. "/history.lua")
if type(history) ~= "table" then history = {} end
local visited = {}
for _, h in ipairs(history) do visited[h.url] = true end

local ENGINES = {
  {name = "Bing", url = "https://www.bing.com/search?q=%s&setlang=ru"},
  {name = "DuckDuckGo", url = "https://html.duckduckgo.com/html/?q=%s"},
  {name = "Википедия", url = "https://ru.wikipedia.org/w/index.php?search=%s"},
}
if not ENGINES[prefs.engine] then prefs.engine = 1 end
if prefs.reader ~= "on" and prefs.reader ~= "off" then prefs.reader = "auto" end
local READER_NAMES = {auto = "авто (если страница не влезает)", on = "всегда", off = "выключен"}

local function savePrefs() System.writeFile(DIR .. "/prefs.lua", System.serialize(prefs)) end
local function saveHistory() System.writeFile(DIR .. "/history.lua", System.serialize(history)) end

local function addVisit(url, title)
  if not url:match("^https?://") then return end
  visited[url] = true
  local last = history[#history]
  if last and last.url == url then
    last.title = title
    last.t = System.time()
  else
    history[#history + 1] = {url = url, title = title, t = System.time()}
    while #history > 120 do table.remove(history, 1) end
  end
  saveHistory()
end

local function isBookmarked(url)
  for _, b in ipairs(prefs.bookmarks) do
    if b.url == url then return true end
  end
  return false
end

-- ---------- адреса
-- Ссылки-«обёртки» поисковиков: достаём настоящий адрес
local B64 = {}
do
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  for i = 1, #chars do B64[chars:byte(i)] = i - 1 end
  B64[43], B64[47] = 62, 63
end
local function b64decode(s)
  local out, bits, nbits = {}, 0, 0
  for i = 1, #s do
    local v = B64[s:byte(i)]
    if v then
      bits = bits * 64 + v
      nbits = nbits + 6
      if nbits >= 8 then
        nbits = nbits - 8
        local div = 2 ^ nbits
        local byte = floor(bits / div)
        bits = bits % div
        out[#out + 1] = string.char(byte)
      end
    end
  end
  return table.concat(out)
end

local function cleanUrl(url)
  local p = HTTP.parseUrl(url)
  if not p then return url end
  if p.host:find("bing.com", 1, true) and p.path == "/ck/a" then
    local u = HTTP.queryParam(url, "u")
    if u and u:sub(1, 2) == "a1" then
      local real = b64decode(u:sub(3))
      if real:match("^https?://") then return real end
      if real:sub(1, 1) == "/" then return "https://" .. p.host .. real end
    end
  elseif p.host:find("duckduckgo.com", 1, true) and p.path:sub(1, 3) == "/l/" then
    local u = HTTP.queryParam(url, "uddg")
    if u and u:match("^https?://") then return u end
  elseif p.host:find("google.", 1, true) and p.path == "/url" then
    local u = HTTP.queryParam(url, "q")
    if u and u:match("^https?://") then return u end
  end
  return url
end

local function searchUrl(query)
  return (ENGINES[prefs.engine].url:gsub("%%s", function() return HTTP.urlencode(query, true) end))
end

--- Текст из адресной строки → адрес (или поиск)
local function normalizeInput(text)
  text = tostring(text or ""):match("^%s*(.-)%s*$")
  if text == "" then return nil end
  if text:match("^%a[%w+.-]*://") then return text end
  if text:match("^about:") or text == "start" then return "cube://start" end
  if not text:find("%s") and (text:find(".", 1, true) or text:match("^localhost") or text:match(":%d+")) and not text:match("^%d+$") then
    return "https://" .. text
  end
  return searchUrl(text)
end

local function esc(s)
  s = tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
  return s
end

-- ---------- цвета страницы
local palettes = {
  dark = {
    bg = 0x16171A, plain = 0xE4E6EB, bold = 0xFFFFFF, italic = 0xB9C2FF, link = 0x6EA8FE, visited = 0xB794F4,
    h1 = 0xFFD866, h2 = 0xFFC247, h3 = 0x7DD3FC, code = 0xA6E3A1, codeBg = 0x23252A, dim = 0x8B92A0, img = 0x8A93A6,
    rule = 0x3A3D45, field = 0x2A2D34, fieldText = 0xF2F3F5,
  },
  light = {
    bg = 0xFFFFFF, plain = 0x1F2328, bold = 0x000000, italic = 0x4338CA, link = 0x0B57D0, visited = 0x7B3FA0,
    h1 = 0xB45309, h2 = 0xC2410C, h3 = 0x0E7490, code = 0x166534, codeBg = 0xEEF0F2, dim = 0x6B7280, img = 0x6B7280,
    rule = 0xD0D4DA, field = 0xEEF0F4, fieldText = 0x1F2328,
  },
}
local function pal() return palettes[System.settings.theme] or palettes.dark end

-- ---------- состояние
local browser = {tabs = {}, tab = nil}
local downloads = {}

local W0, H0 = Desktop.screenSize()
local win = ctx.window(min(110, W0), min(38, max(18, H0 - Desktop.dockHeight() - 2)), "Браузер")
win.resizable, win.minW, win.minH = true, min(60, W0), 12
local c = win.content

local btnBack, btnFwd, btnReload, btnHome, addr, btnStar, btnMenu, tabbar, view, status

local function pageWidth() return max(20, view.w - 3) end

--- Сколько байт HTML разрешаем загрузить: страница в памяти занимает в несколько раз больше
local function pageLimit()
  local free = computer.freeMemory()
  return max(20 * 1024, min(160 * 1024, floor(free * 0.10)))
end

local go, startFetch, showError, refreshUI

local function newTab()
  return {hist = {}, hi = 0, scroll = 0, state = "idle", title = "Новая вкладка", url = "", status = "", focus = nil}
end

-- ---------- показ документов
local function finish(tab, doc, lay)
  tab.doc, tab.lines, tab.itemLine, tab.anchorLine, tab.layoutWidth = doc, lay.lines, lay.itemLine, lay.anchorLine, lay.width
  tab.state, tab.job, tab.focus, tab.findLine = "idle", nil, nil, nil
  local pend = tab.pending or {url = tab.url, opts = {}}
  local url = pend.url
  tab.url = url
  local host = HTTP.hostOf(url)
  tab.title = (doc.title ~= "" and doc.title) or (host ~= "" and host) or url
  local mode = pend.opts.hist or "push"
  local entry = tab.hist[tab.hi]
  if mode == "push" and not (entry and entry.url == url and not pend.opts.post) then
    for i = #tab.hist, tab.hi + 1, -1 do tab.hist[i] = nil end
    tab.hist[#tab.hist + 1] = {url = url, title = tab.title, scroll = 0}
    tab.hi = #tab.hist
  elseif entry then
    entry.title, entry.url = tab.title, url
  end
  local frag = url:match("#(.+)$")
  local line = frag and tab.anchorLine[HTTP.urldecode(frag)]
  tab.scroll = pend.opts.scroll or (line and max(0, line - 1)) or 0
  tab.scroll = max(0, min(tab.scroll, max(0, #tab.lines - view.h)))
  local m = tab.meta or {}
  local info = {}
  if m.code and m.code >= 400 then info[#info + 1] = "HTTP " .. m.code end
  if m.bytes then info[#info + 1] = System.formatSize(m.bytes) end
  if m.elapsed then info[#info + 1] = string.format("%.1f с", m.elapsed) end
  if m.via then info[#info + 1] = "через " .. m.via end
  if m.truncated then info[#info + 1] = "обрезана по лимиту ОЗУ" end
  if m.reader then info[#info + 1] = "режим чтения" end
  tab.msg = table.concat(info, "  ·  ")
  tab.status = ""
  addVisit(url, tab.title)
  tab.pending, tab.meta = nil, nil
  System.collect()
  refreshUI()
end

--- Построить и показать документ сразу (внутренние страницы, ошибки, локальные файлы)
local function showDoc(tab, doc, url, opts, meta)
  tab.pending = {url = url, opts = opts or {}}
  tab.meta = meta
  finish(tab, doc, HTML.layout(doc, pageWidth()))
end

local function showHtml(tab, html, url, opts)
  showDoc(tab, HTML.parse(html, {base = url}), url, opts)
end

showError = function(tab, url, err, opts)
  err = tostring(err)
  tab.state, tab.req, tab.job = "idle", nil, nil
  local html = "<h2>Не удалось открыть страницу</h2><p>" .. esc(url) .. "</p><p><b>" .. esc(err) .. "</b></p><p>"
    .. esc(HTTP.hint(err)) .. "</p><p><a href=\"" .. esc(url) .. "\">Повторить</a> · <a href=\"cube://start\">Домашняя страница</a></p>"
  showHtml(tab, html, url, opts or {hist = "none"})
  tab.title = "Ошибка"
  System.log("Браузер: " .. url .. " — " .. err)
  refreshUI()
end

-- ---------- внутренние страницы
local function homeHtml()
  local t = {}
  t[#t + 1] = "<h1>CubeOS Браузер</h1>"
  t[#t + 1] = '<form action="cube://search" method="get"><input name="q" size="46" placeholder="Поиск или адрес сайта"> <input type="submit" value="Найти"></form>'
  t[#t + 1] = "<p>Поисковая система: <b>" .. esc(ENGINES[prefs.engine].name) .. '</b> · <a href="cube://engine">сменить</a></p>'
  t[#t + 1] = "<h2>Закладки</h2>"
  if #prefs.bookmarks == 0 then
    t[#t + 1] = "<p>Пока пусто. Нажмите ★ в адресной строке (Ctrl+D).</p>"
  else
    t[#t + 1] = "<ul>"
    for _, b in ipairs(prefs.bookmarks) do
      t[#t + 1] = '<li><a href="' .. esc(b.url) .. '">' .. esc(b.title) .. "</a></li>"
    end
    t[#t + 1] = "</ul>"
  end
  t[#t + 1] = '<p><a href="cube://bookmarks">Управление закладками</a> · <a href="cube://history">История</a> · <a href="cube://about">О браузере</a></p>'
  t[#t + 1] = "<hr><p><small>JavaScript не выполняется, картинки показываются подписью. Адрес можно ввести как <i>example.com</i>, "
    .. "<i>https://…</i> или <i>file:///Users/Documents/hello.html</i>.</small></p>"
  return table.concat(t, "\n")
end

local function bookmarksHtml()
  local t = {"<h1>Закладки</h1>"}
  if #prefs.bookmarks == 0 then t[#t + 1] = "<p>Закладок нет.</p>" end
  t[#t + 1] = "<ul>"
  for i, b in ipairs(prefs.bookmarks) do
    t[#t + 1] = '<li><a href="' .. esc(b.url) .. '">' .. esc(b.title) .. '</a> — <a href="cube://bm-del?i=' .. i .. '">удалить</a></li>'
  end
  t[#t + 1] = '</ul><p><a href="cube://start">← Домашняя страница</a></p>'
  return table.concat(t, "\n")
end

local function historyHtml()
  local t = {"<h1>История</h1>"}
  if #history == 0 then t[#t + 1] = "<p>История пуста.</p>" end
  t[#t + 1] = "<ul>"
  for i = #history, max(1, #history - 59), -1 do
    local h = history[i]
    t[#t + 1] = "<li>" .. System.date("%d.%m %H:%M", h.t or 0) .. " — <a href=\"" .. esc(h.url) .. '">' .. esc(h.title or h.url) .. "</a></li>"
  end
  t[#t + 1] = '</ul><p><a href="cube://clear-history">Очистить историю</a> · <a href="cube://start">← Домашняя страница</a></p>'
  return table.concat(t, "\n")
end

local function aboutHtml()
  return [[<h1>Браузер CubeOS</h1>
<p>Текстовый браузер для OpenComputers: сеть идёт через Internet Card.</p>
<h2>Горячие клавиши</h2>
<ul>
<li><b>Ctrl+L</b> — адресная строка, <b>Ctrl+T</b> — новая вкладка, <b>Ctrl+W</b> — закрыть вкладку</li>
<li><b>Tab / Shift+Tab</b> — следующая / предыдущая ссылка, <b>Enter</b> — открыть</li>
<li><b>Backspace</b> или <b>Alt+←</b> — назад, <b>Alt+→</b> — вперёд, <b>F5</b> — обновить, <b>Esc</b> — стоп</li>
<li><b>Ctrl+D</b> — закладка, <b>Ctrl+F</b> — поиск на странице, <b>F3</b> — дальше</li>
<li>Правый клик по ссылке — меню (открыть во вкладке, скачать)</li>
</ul>
<h2>Что умеет</h2>
<ul><li>HTML, обычный текст, Markdown, кодировки UTF-8 и windows-1251</li>
<li>Формы (GET и POST), поиск, редиректы, скачивание файлов в /Users/Downloads</li>
<li>Локальные файлы: file:///Users/Documents/hello.html</li></ul>
<h2>Ограничения</h2>
<ul><li>Нет JavaScript — сайты-приложения (SPA) покажут мало или ничего</li>
<li>Картинки не рисуются, вместо них [подпись]</li>
<li>Размер страницы ограничен объёмом свободной ОЗУ — длинные страницы обрезаются</li></ul>
<p><a href="cube://start">← Домашняя страница</a></p>]]
end

-- ---------- загрузка файлов
local function safeName(url, hint)
  local p = HTTP.parseUrl(url)
  local name = hint or (p and p.path:match("([^/]+)/?$")) or "download"
  name = HTTP.urldecode(name):gsub("[/\\:*?\"<>|%c]", "_")
  if name == "" or name == "." or name == ".." then name = "download" end
  return usub(name, 1, 60)
end

local function startDownload(url, name)
  if #downloads >= 3 then
    Desktop.notify("Слишком много загрузок одновременно")
    return
  end
  name = safeName(url, name)
  local path = DOWNLOADS .. "/" .. name
  local n = 1
  while System.exists(path) do
    n = n + 1
    path = DOWNLOADS .. "/" .. n .. "_" .. name
  end
  local fh = System.fs.open(path, "w")
  if not fh then
    Desktop.notify("Не удалось создать файл " .. name)
    return
  end
  local d = {url = url, path = path, name = name, fh = fh, bytes = 0, hops = 0}
  d.sink = function(chunk)
    if d.failed then return end
    local ok = System.fs.write(fh, chunk)
    if not ok then d.failed = "диск переполнен" end
    d.bytes = d.bytes + #chunk
  end
  local req, err = HTTP.start(url, nil, HTTP.browserHeaders(), "GET", {sink = d.sink, timeout = 90, idleTimeout = 20})
  if not req then
    System.fs.close(fh)
    System.remove(path)
    Desktop.notify("Скачивание не удалось: " .. tostring(err))
    return
  end
  d.req = req
  downloads[#downloads + 1] = d
  Desktop.notify("Скачивание: " .. name)
  win.tickInterval = 0.1
end

local function closeDownload(d, ok, msg)
  pcall(System.fs.close, d.fh)
  if not ok then System.remove(d.path) end
  for i, x in ipairs(downloads) do
    if x == d then table.remove(downloads, i) break end
  end
  Desktop.notify(ok and ("Скачано: " .. d.name .. " (" .. System.formatSize(d.bytes) .. ")") or ("Ошибка загрузки: " .. tostring(msg)))
end

local function tickDownloads()
  for i = #downloads, 1, -1 do
    local d = downloads[i]
    if d then
      local done = d.req:poll(0.08)
      if d.failed then
        d.req:cancel("диск")
        closeDownload(d, false, d.failed)
      elseif done then
        local res = d.req:result()
        local loc = res.ok and res.headers.location
        if loc and res.code >= 300 and res.code < 400 and d.hops < 8 then
          d.hops = d.hops + 1
          local nxt = HTTP.join(d.url, loc)
          d.url = nxt
          local req, err = HTTP.start(nxt, nil, HTTP.browserHeaders(), "GET", {sink = d.sink, timeout = 90, idleTimeout = 20})
          if req then d.req = req else closeDownload(d, false, err) end
        elseif not res.ok then
          closeDownload(d, false, res.error)
        elseif res.code and res.code >= 400 then
          closeDownload(d, false, "HTTP " .. res.code)
        else
          closeDownload(d, true)
        end
      end
    end
  end
end

local function askDownload(url, ctype, size)
  local name = safeName(url)
  local text = "Это не веб-страница, а файл.\n\nИмя: " .. name .. "\nТип: " .. (ctype ~= "" and ctype or "неизвестен")
  if size then text = text .. "\nРазмер: " .. System.formatSize(size) end
  text = text .. "\n\nСкачать в " .. DOWNLOADS .. "?"
  if GUI.confirm("Скачать файл?", text, "Скачать", "Отмена") then startDownload(url, name) end
end

-- ---------- загрузка страниц (по шагам)
local function startJob(tab, kind, body, url, meta)
  tab.state, tab.meta = "parse", meta
  local skip = prefs.reader == "on" or (prefs.reader == "auto" and meta.truncated)
  meta.reader = skip and kind == "html" or nil
  tab.status = "Разбор страницы…"
  local width = pageWidth()
  tab.job = coroutine.create(function()
    local doc
    if kind == "html" then doc = HTML.parse(body, {base = url, skipChrome = skip})
    elseif kind == "md" then doc = HTML.markdown(body, {base = url})
    else doc = HTML.plain(body) end
    body = nil
    if meta.truncated then HTML.note(doc, "— страница обрезана: не хватает памяти для полной загрузки —") end
    return doc, HTML.layout(doc, width)
  end)
end

local function textKind(ctype, url, body)
  if ctype:find("html", 1, true) then return "html" end
  if ctype:find("markdown", 1, true) or url:match("%.md$") or url:match("%.markdown$") then return "md" end
  if ctype == "" or ctype:find("text/plain", 1, true) then
    local head = body:sub(1, 600):lower()
    if head:find("<!doctype html", 1, true) or head:find("<html", 1, true) then return "html" end
    return "text"
  end
  if ctype:find("^text/") or ctype:find("json", 1, true) or ctype:find("xml", 1, true) or ctype:find("javascript", 1, true) then
    return "text"
  end
  return "binary"
end

local function onFetchDone(tab, res)
  local pend = tab.pending
  local url, opts = pend.url, pend.opts
  if not res.ok then return showError(tab, url, res.error, opts) end
  local h = res.headers
  local code = res.code
  if code and code >= 300 and code < 400 and code ~= 304 and h.location then
    local hops = (opts.hops or 0) + 1
    if hops > HTTP.MAX_REDIRECTS then return showError(tab, url, "слишком много перенаправлений", opts) end
    local nxt = cleanUrl(HTTP.join(url, h.location))
    if not nxt:match("^https?://") then return showError(tab, url, "перенаправление на неподдерживаемый адрес: " .. nxt, opts) end
    local o = {hist = opts.hist, hops = hops, scroll = opts.scroll}
    if code == 307 or code == 308 then o.post = opts.post end
    return startFetch(tab, nxt, o)
  end
  local body = res.body or ""
  local ctype = (h["content-type"] or ""):lower()
  if body:sub(1, 2) == "\31\139" then
    return showError(tab, url, "сервер прислал сжатые данные (gzip), которые браузер не умеет читать", opts)
  end
  local kind = textKind(ctype, url, body)
  if kind == "binary" then
    tab.state, tab.status = "idle", ""
    refreshUI()
    askDownload(url, ctype, res.truncated and nil or res.bytes)
    return
  end
  body = HTML.toUtf8(body, HTML.charsetOf(ctype, body))
  startJob(tab, kind, body, url, {code = code, bytes = res.bytes, elapsed = res.elapsed, via = h["x-cubeos-via"], truncated = res.truncated})
end

startFetch = function(tab, url, opts)
  opts = opts or {}
  local reqUrl = url:gsub("#.*$", "")
  local headers = HTTP.browserHeaders()
  if opts.post then headers["Content-Type"] = "application/x-www-form-urlencoded" end
  local req, err = HTTP.start(reqUrl, opts.post, headers, opts.post and "POST" or "GET",
    {maxBytes = pageLimit(), truncate = true, timeout = 30, idleTimeout = 15})
  if not req then return showError(tab, url, err, opts) end
  tab.req, tab.state, tab.job = req, "fetch", nil
  tab.pending = {url = url, opts = opts}
  tab.status = "Подключение к " .. HTTP.hostOf(url) .. "…"
  win.tickInterval = 0.1
  refreshUI()
end

local function stopTab(tab)
  if tab.req then tab.req:cancel("отменено") tab.req = nil end
  tab.job = nil
  if tab.state ~= "idle" then
    tab.state, tab.status = "idle", ""
    if not tab.lines then tab.title = "Новая вкладка" end
  end
end

local function readLocal(tab, url, opts)
  local path = HTTP.urldecode((url:gsub("^file://", ""):gsub("[?#].*$", "")))
  if not System.exists(path) or System.isDir(path) then
    return showError(tab, url, "файл не найден: " .. path, opts)
  end
  local data = System.readFile(path) or ""
  local limit = pageLimit()
  local truncated = #data > limit
  if truncated then data = data:sub(1, limit) end
  local ext = System.extension(path)
  local kind = (ext == "html" or ext == "htm") and "html" or (ext == "md" and "md" or "text")
  data = HTML.toUtf8(data, HTML.charsetOf("", data))
  local doc
  if kind == "html" then doc = HTML.parse(data, {base = url})
  elseif kind == "md" then doc = HTML.markdown(data, {base = url})
  else doc = HTML.plain(data, System.basename(path)) end
  if truncated then HTML.note(doc, "— файл обрезан: не хватает памяти —") end
  if doc.title == "" then doc.title = System.basename(path) end
  showDoc(tab, doc, url, opts, {bytes = #data})
end

local function internalPage(tab, url, opts)
  local name, query = url:match("^cube://([%w%-]+)%??(.*)$")
  name = name or "start"
  local function param(key)
    return HTTP.queryParam("cube://x?" .. query, key)
  end
  if name == "search" then
    local q = param("q") or ""
    if q:match("%S") then return go(tab, normalizeInput(q), {hist = "push"}) end
    return go(tab, "cube://start", {hist = "push"})
  elseif name == "engine" then
    prefs.engine = prefs.engine % #ENGINES + 1
    savePrefs()
    Desktop.notify("Поиск: " .. ENGINES[prefs.engine].name)
    return go(tab, "cube://start", {hist = "replace"})
  elseif name == "bm-del" then
    table.remove(prefs.bookmarks, tonumber(param("i")) or 0)
    savePrefs()
    return go(tab, "cube://bookmarks", {hist = "replace", scroll = tab.scroll})
  elseif name == "clear-history" then
    history, visited = {}, {}
    saveHistory()
    return go(tab, "cube://history", {hist = "replace"})
  end
  local pages = {start = homeHtml, bookmarks = bookmarksHtml, history = historyHtml, about = aboutHtml}
  local gen = pages[name] or homeHtml
  local doc = HTML.parse(gen(), {base = url})
  doc.title = ({start = "Начальная страница", bookmarks = "Закладки", history = "История", about = "О браузере"})[name] or "CubeOS"
  showDoc(tab, doc, url, opts)
end

--- Главная точка входа: перейти по адресу
go = function(tab, input, opts)
  opts = opts or {}
  local url = normalizeInput(input)
  if not url then return end
  local e = tab.hist[tab.hi]
  if e and opts.hist ~= "none" then e.scroll = tab.scroll end
  stopTab(tab)
  if url:sub(1, 7) == "cube://" then return internalPage(tab, url, opts) end
  if url:sub(1, 7) == "file://" then return readLocal(tab, url, opts) end
  local scheme = url:match("^(%a[%w+.-]*):")
  if scheme ~= "http" and scheme ~= "https" then
    return showError(tab, url, "неподдерживаемый протокол: " .. tostring(scheme), opts)
  end
  startFetch(tab, url, opts)
end

local function goBack(tab)
  if tab.hi > 1 then
    local e = tab.hist[tab.hi]
    if e then e.scroll = tab.scroll end
    tab.hi = tab.hi - 1
    local t = tab.hist[tab.hi]
    go(tab, t.url, {hist = "none", scroll = t.scroll})
  end
end

local function goForward(tab)
  if tab.hi < #tab.hist then
    local e = tab.hist[tab.hi]
    if e then e.scroll = tab.scroll end
    tab.hi = tab.hi + 1
    local t = tab.hist[tab.hi]
    go(tab, t.url, {hist = "none", scroll = t.scroll})
  end
end

local function reload(tab)
  if tab.url ~= "" then go(tab, tab.url, {hist = "none", scroll = tab.scroll}) end
end

-- ---------- действия со страницей
local function scrollBy(tab, delta)
  if not tab.lines then return end
  tab.scroll = max(0, min(max(0, #tab.lines - view.h), tab.scroll + delta))
end

local function showItem(tab, idx)
  local line = tab.itemLine and tab.itemLine[idx]
  if not line then return end
  if line <= tab.scroll or line > tab.scroll + view.h then
    tab.scroll = max(0, min(max(0, #tab.lines - view.h), line - floor(view.h / 3)))
  end
end

local function moveFocus(tab, dir)
  local items = tab.doc and tab.doc.items
  if not items or #items == 0 then return end
  local idx = tab.focus
  if not idx then
    idx = dir > 0 and 1 or #items
    -- начинаем с первого элемента, видимого на экране
    for i = 1, #items do
      local l = tab.itemLine[i]
      if l and l > tab.scroll then idx = i break end
    end
  else
    idx = idx + dir
    if idx > #items then idx = 1 elseif idx < 1 then idx = #items end
  end
  tab.focus = idx
  showItem(tab, idx)
end

local function jumpAnchor(tab, frag)
  local line = tab.anchorLine and tab.anchorLine[HTTP.urldecode(frag)]
  if line then
    tab.scroll = max(0, min(max(0, #tab.lines - view.h), line - 1))
  else
    tab.scroll = 0
  end
end

local function submitForm(tab, form, btn)
  if not form then return end
  local parts = {}
  local function add(k, v)
    parts[#parts + 1] = HTTP.urlencode(k, true) .. "=" .. HTTP.urlencode(v or "", true)
  end
  for _, f in ipairs(form.fields) do
    if f.name and f.name ~= "" then
      if f.kind == "checkbox" or f.kind == "radio" then
        if f.checked then add(f.name, f.value) end
      elseif f.kind == "select" then
        local o = f.options[f.sel]
        add(f.name, o and o.v or "")
      elseif f.kind == "submit" then
        if f == btn then add(f.name, f.value) end
      else
        add(f.name, f.value)
      end
    end
  end
  local body = table.concat(parts, "&")
  local action = (form.action ~= "" and form.action or tab.url):gsub("#.*$", "")
  if form.method == "POST" then
    go(tab, action, {post = body, hist = "push"})
  else
    action = action:gsub("%?.*$", "")
    go(tab, action .. (body ~= "" and ("?" .. body) or ""), {hist = "push"})
  end
end

local function editField(tab, f)
  local k = f.kind
  if k == "checkbox" then
    f.checked = not f.checked
  elseif k == "radio" then
    if f.form then
      for _, o in ipairs(f.form.fields) do
        if o.kind == "radio" and o.name == f.name then o.checked = false end
      end
    end
    f.checked = true
  elseif k == "select" then
    local labels = {}
    for i, o in ipairs(f.options) do labels[i] = o.label end
    local i = GUI.select(f.name or "Выбор", labels)
    if i then f.sel = i end
  elseif k == "submit" then
    submitForm(tab, f.form, f)
  else
    local v = GUI.prompt(f.placeholder ~= nil and f.placeholder ~= "" and f.placeholder or (f.name or "Ввод"),
      "Введите значение:", f.value or "", k == "password")
    if v ~= nil then
      f.value = v
      -- форма с одним полем (поиск) отправляется сразу после ввода
      if f.form then
        local texts, submit = 0, nil
        for _, o in ipairs(f.form.fields) do
          if o.kind == "text" or o.kind == "password" then texts = texts + 1 end
          if o.kind == "submit" and not submit then submit = o end
        end
        if texts == 1 and submit then submitForm(tab, f.form, submit) end
      end
    end
  end
end

local function openLink(tab, href, newTab)
  href = cleanUrl(href)
  if href:match("^mailto:") or href:match("^tel:") then
    Desktop.notify("Ссылка не поддерживается: " .. usub(href, 1, 40))
    return
  end
  if not newTab then
    local base = tab.url:gsub("#.*$", "")
    local frag = href:match("^(.-)#(.*)$")
    if frag and (href:gsub("#.*$", "")) == base and not tab.post then
      jumpAnchor(tab, href:match("#(.*)$"))
      return
    end
  end
  if newTab then
    browser.openTab(href)
  else
    go(tab, href, {hist = "push"})
  end
end

local function activate(tab, idx)
  local it = tab.doc and tab.doc.items[idx]
  if not it then return end
  if it.kind == "link" then openLink(tab, it.href) else editField(tab, it.field) end
end

local function itemMenu(tab, idx, e)
  local it = tab.doc and tab.doc.items[idx]
  if not it then return end
  if it.kind ~= "link" then
    activate(tab, idx)
    return
  end
  GUI.menu(e.x, e.y, {
    {text = "Открыть", action = function() openLink(tab, it.href) end},
    {text = "Открыть в новой вкладке", action = function() openLink(tab, it.href, true) end},
    {text = "Скачать файл", action = function() startDownload(cleanUrl(it.href)) end},
    {separator = true},
    {text = GUI.fit(cleanUrl(it.href), 44), disabled = true},
  })
end

local function findText(tab, query, from)
  if not tab.lines or not query or query == "" then return end
  query = unicode.lower(query)
  local total = #tab.lines
  for i = 0, total - 1 do
    local idx = (from + i - 1) % total + 1
    local ln = tab.lines[idx]
    local parts = {}
    for k = 1, #ln, 4 do
      local t = ln[k + 1]
      if type(t) == "string" then parts[#parts + 1] = t end
    end
    if #parts > 0 and unicode.lower(table.concat(parts, " ")):find(query, 1, true) then
      tab.findLine = idx
      tab.scroll = max(0, min(max(0, total - view.h), idx - floor(view.h / 3)))
      return true
    end
  end
  Desktop.notify("Не найдено: " .. query)
end

-- ---------- виджет страницы
local View = GUI.class()

local function styleColor(P, s)
  if s == "plain" then return P.plain
  elseif s == "bold" then return P.bold
  elseif s == "italic" or s == "bolditalic" then return P.italic
  elseif s == "link" then return P.link
  elseif s == "h1" then return P.h1
  elseif s == "h2" then return P.h2
  elseif s == "code" or s == "pre" then return P.code, P.codeBg
  elseif s == "dim" then return P.dim
  elseif s == "img" then return P.img
  elseif s:sub(1, 1) == "h" then return P.h3 end
  return P.plain
end

local function drawField(P, f, sx, y, focused)
  local k, w = f.kind, f.w or 10
  local bg, fg, text = P.field, P.fieldText, ""
  if k == "checkbox" then
    text = f.checked and "[x]" or "[ ]"
  elseif k == "radio" then
    text = f.checked and "(•)" or "( )"
  elseif k == "submit" then
    bg, fg = C.accent, C.accentText
    if f.button then bg, fg = C.button, C.buttonText end
    text = GUI.fit(" " .. (f.label or "OK") .. " ", w)
  elseif k == "select" then
    local o = f.options[f.sel]
    text = " " .. GUI.fit(o and o.label or "—", w - 4) .. " ▾"
  else
    local v = f.value or ""
    if k == "password" then v = string.rep("•", ulen(v)) end
    if v == "" and f.placeholder and f.placeholder ~= "" then
      v, fg = f.placeholder, P.dim
    end
    v = v:gsub("[\r\n]+", " ")
    text = " " .. GUI.fit(v, w - 2)
  end
  if focused then bg, fg = C.accent, C.accentText end
  local len = ulen(text)
  Screen.rect(sx, y, w, 1, bg, nil, " ")
  Screen.text(sx, y, fg, text .. string.rep(" ", max(0, w - len)), bg)
end

function View:drawSelf(ax, ay)
  local P = pal()
  local tab = browser.tab
  Screen.rect(ax, ay, self.w, self.h, P.bg, nil, " ")
  local lines = tab.lines
  if not lines then
    local msg = tab.status ~= "" and tab.status or "Введите адрес или поисковый запрос в строке сверху"
    Screen.text(ax + 2, ay + 1, P.dim, GUI.fit(msg, self.w - 4), P.bg)
    return
  end
  local scroll, rows, textW = tab.scroll, self.h, self.w - 1
  local items = tab.doc.items
  Screen.pushClip(ax, ay, textW, rows)
  for row = 1, rows do
    local idx = scroll + row
    local ln = lines[idx]
    if not ln then break end
    local y = ay + row - 1
    if idx == tab.findLine then Screen.rect(ax, y, textW, 1, Screen.blend(P.link, P.bg, 0.2), nil, " ") end
    if ln.rule then
      Screen.text(ax + 1 + ln.x, y, P.rule, string.rep(ln.ch or "─", max(0, textW - 2 - ln.x)))
    else
      if ln.bg then Screen.rect(ax + ln.bg, y, max(0, textW - ln.bg), 1, P.codeBg, nil, " ") end
      if ln.bar then Screen.text(ax + 1 + ln.bar, y, P.rule, "│") end
      if ln.pfx then Screen.text(ax + 1 + ln.pfxX, y, P.dim, ln.pfx) end
      for k = 1, #ln, 4 do
        local x, t, s, it = ln[k], ln[k + 1], ln[k + 2], ln[k + 3]
        local focused = it and it == tab.focus
        if type(t) == "table" then
          drawField(P, t, ax + 1 + x, y, focused)
        else
          local fg, bg = styleColor(P, s)
          if s == "link" and it and visited[items[it].href] then fg = P.visited end
          if focused then fg, bg = C.accentText, C.accent end
          Screen.text(ax + 1 + x, y, fg, t, bg)
        end
      end
    end
  end
  Screen.popClip()
  local total = #lines
  if total > rows then
    local barH = max(1, floor(rows * rows / total))
    local barY = floor((rows - barH) * scroll / max(1, total - rows))
    Screen.rect(ax + self.w - 1, ay, 1, rows, P.rule, nil, " ")
    Screen.rect(ax + self.w - 1, ay + barY, 1, barH, P.dim, nil, " ")
  end
end

local function hitItem(ln, col)
  for k = 1, #ln, 4 do
    local t, it = ln[k + 1], ln[k + 3]
    if it then
      local w = type(t) == "table" and (t.w or 1) or ulen(t)
      if col >= ln[k] and col < ln[k] + w then return it end
    end
  end
end

function View:onEvent(e, ax, ay)
  local tab = browser.tab
  if e.type == "scroll" then
    scrollBy(tab, -e.dir * 3)
    return true
  end
  if e.type ~= "touch" then return false end
  self:focus()
  local ln = tab.lines and tab.lines[tab.scroll + (e.y - ay) + 1]
  if not ln then return true end
  local item = hitItem(ln, e.x - ax - 1)
  tab.focus = item
  if item then
    if e.button == 1 then itemMenu(tab, item, e) else activate(tab, item) end
  end
  return true
end

function View:onKey(e)
  local tab = browser.tab
  local code = e.code
  if code == 200 then scrollBy(tab, -1)
  elseif code == 208 then scrollBy(tab, 1)
  elseif code == 201 then scrollBy(tab, -(self.h - 1))
  elseif code == 209 then scrollBy(tab, self.h - 1)
  elseif code == 57 then scrollBy(tab, e.shift and -(self.h - 1) or (self.h - 1))
  elseif code == 199 then tab.scroll = 0
  elseif code == 207 then scrollBy(tab, 1e9)
  elseif code == 15 then moveFocus(tab, e.shift and -1 or 1)
  elseif code == 28 or code == 156 then
    if tab.focus then activate(tab, tab.focus) else return false end
  elseif code == 14 then goBack(tab)
  else return false end
  return true
end

-- ---------- панель вкладок
local TabBar = GUI.class()

function TabBar:drawSelf(ax, ay)
  local P = pal()
  Screen.rect(ax, ay, self.w, 1, C.panel, nil, " ")
  local tabs = browser.tabs
  local tw = max(8, min(24, floor((self.w - 5) / max(1, #tabs))))
  self.hits, self.tw = {}, tw
  for i, t in ipairs(tabs) do
    local x = ax + (i - 1) * tw
    local active = t == browser.tab
    local bg = active and P.bg or C.panel
    local fg = active and (System.settings.theme == "dark" and 0xFFFFFF or 0x000000) or C.dim
    local label = (t.state ~= "idle" and "… " or "") .. t.title
    Screen.rect(x, ay, tw, 1, bg, nil, " ")
    Screen.text(x + 1, ay, fg, GUI.fit(label, tw - 4), bg)
    if #tabs > 1 then Screen.text(x + tw - 2, ay, C.dim, "×", bg) end
  end
  Screen.text(ax + #tabs * tw + 1, ay, C.accent, "+", C.panel)
end

function TabBar:onEvent(e, ax)
  if e.type ~= "touch" then return false end
  local tw = self.tw or 10
  local i = floor((e.x - ax) / tw) + 1
  local tabs = browser.tabs
  if i >= 1 and i <= #tabs then
    local closeX = ax + i * tw - 2
    if #tabs > 1 and e.x >= closeX - 1 and e.x <= closeX + 1 then browser.closeTab(i) else browser.switchTab(i) end
  elseif i == #tabs + 1 then
    browser.openTab("cube://start")
  end
  return true
end

-- ---------- строка состояния
local Status = GUI.class()

function Status:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, 1, C.panel, nil, " ")
  local tab = browser.tab
  local text, fg = nil, C.text
  if tab.state ~= "idle" then
    text = tab.status
  elseif tab.focus and tab.doc and tab.doc.items[tab.focus] then
    local it = tab.doc.items[tab.focus]
    text = it.kind == "link" and cleanUrl(it.href) or ("Поле: " .. tostring(it.field.name or it.field.kind))
  else
    text = (tab.msg and tab.msg ~= "") and tab.msg or tab.url
    fg = C.dim
  end
  if #downloads > 0 then
    local d = downloads[1]
    text = "⇩ " .. d.name .. " " .. System.formatSize(d.bytes) .. (#downloads > 1 and (" (+" .. (#downloads - 1) .. ")") or "") .. "   │   " .. tostring(text)
  end
  Screen.text(ax + 1, ay, fg, GUI.fit(text, self.w - 2), C.panel)
end

-- ---------- вкладки
refreshUI = function()
  local tab = browser.tab
  if not tab then return end
  win.title = "Браузер — " .. tab.title
  btnBack.disabled = tab.hi <= 1
  btnFwd.disabled = tab.hi >= #tab.hist
  btnReload.text = tab.state ~= "idle" and "×" or "↻"
  btnStar.text = isBookmarked(tab.url) and "★" or "☆"
  if not addr:isFocused() and tab.url ~= addr.text then addr:setText(tab.url) end
  Desktop.dirty = true
end

function browser.switchTab(i)
  local t = browser.tabs[i]
  if not t then return end
  browser.tab = t
  addr:setText(t.url)
  addr.sel = false
  refreshUI()
end

function browser.openTab(url)
  if #browser.tabs >= 8 then
    Desktop.notify("Максимум 8 вкладок")
    return
  end
  local t = newTab()
  browser.tabs[#browser.tabs + 1] = t
  browser.switchTab(#browser.tabs)
  go(t, url or "cube://start", {hist = "push"})
  return t
end

function browser.closeTab(i)
  local tabs = browser.tabs
  if #tabs <= 1 then return end
  local t = tabs[i]
  stopTab(t)
  table.remove(tabs, i)
  if browser.tab == t then browser.switchTab(min(i, #tabs)) end
  System.collect()
  refreshUI()
end

-- ---------- интерфейс окна
local function layout()
  local w, h = c.w, c.h
  btnStar.x, btnMenu.x = w - 8, w - 3
  addr.w = max(10, w - 30)
  tabbar.w, tabbar.y = w, 2
  view.y, view.w, view.h = 3, w, max(3, h - 3)
  status.y, status.w = h, w
end

btnBack = c:add(GUI.button(1, 1, 4, 1, " ← ", function() goBack(browser.tab) end))
btnFwd = c:add(GUI.button(6, 1, 4, 1, " → ", function() goForward(browser.tab) end))
btnReload = c:add(GUI.button(11, 1, 4, 1, " ↻ ", function()
  local t = browser.tab
  if t.state ~= "idle" then stopTab(t) refreshUI() else reload(t) end
end))
btnHome = c:add(GUI.button(16, 1, 4, 1, " ⌂ ", function() go(browser.tab, "cube://start", {hist = "push"}) end))
for _, b in ipairs({btnBack, btnFwd, btnReload, btnHome}) do b.color, b.textColor = "panel", "text" end

addr = c:add(GUI.input(21, 1, 40, "", "Адрес или поисковый запрос"))
addr.onSubmit = function(self, text)
  self.sel = false
  go(browser.tab, text, {hist = "push"})
  view:focus()
end

-- при выделении всё содержимое заменяется первым же символом
do
  local origKey, origPaste, origEvent, origDraw = addr.onKey, addr.onPaste, addr.onEvent, addr.drawSelf
  addr.onKey = function(self, e)
    if self.sel and e.char and e.char >= 32 and not e.ctrl then self:setText("") end
    if self.sel and (e.code == 14 or e.code == 211) then self:setText("") self.sel = false return true end
    if e.code ~= 29 and e.code ~= 42 then self.sel = false end
    return origKey(self, e)
  end
  addr.onPaste = function(self, text)
    if self.sel then self:setText("") self.sel = false end
    return origPaste(self, text)
  end
  addr.onEvent = function(self, e, ax, ay)
    local was = self:isFocused()
    local r = origEvent(self, e, ax, ay)
    if not was and e.type == "touch" then self.sel = true end
    return r
  end
  addr.drawSelf = function(self, ax, ay)
    origDraw(self, ax, ay)
    if self.sel and self:isFocused() and self.text ~= "" then
      Screen.text(ax + 1, ay, C.accentText, GUI.fit(self.text, self.w - 2), C.accent)
    end
  end
end

btnStar = c:add(GUI.button(0, 1, 4, 1, " ☆ ", function()
  local t = browser.tab
  if t.url == "" or t.url:match("^cube://") then
    Desktop.notify("Эту страницу нельзя добавить в закладки")
    return
  end
  for i, b in ipairs(prefs.bookmarks) do
    if b.url == t.url then
      table.remove(prefs.bookmarks, i)
      savePrefs()
      Desktop.notify("Закладка удалена")
      refreshUI()
      return
    end
  end
  prefs.bookmarks[#prefs.bookmarks + 1] = {title = t.title, url = t.url}
  savePrefs()
  Desktop.notify("Добавлено в закладки")
  refreshUI()
end))
btnStar.color, btnStar.textColor = "panel", "warning"

local function menu()
  local t = browser.tab
  GUI.menu(c.w - 30, 2, {
    {text = "Новая вкладка", hint = "Ctrl+T", action = function() browser.openTab("cube://start") end},
    {text = "Закрыть вкладку", hint = "Ctrl+W", disabled = #browser.tabs <= 1, action = function()
      for i, x in ipairs(browser.tabs) do
        if x == t then browser.closeTab(i) break end
      end
    end},
    {separator = true},
    {text = "Закладки", action = function() go(t, "cube://bookmarks", {hist = "push"}) end},
    {text = "История", action = function() go(t, "cube://history", {hist = "push"}) end},
    {text = "Найти на странице…", hint = "Ctrl+F", action = function()
      local q = GUI.prompt("Поиск на странице", "Что искать:", t.find or "")
      if q and q ~= "" then t.find = q findText(t, q, (t.findLine or 0) + 1) end
    end},
    {separator = true},
    {text = "Скачать эту страницу", disabled = not t.url:match("^https?://"), action = function() startDownload(t.url, safeName(t.url) .. (safeName(t.url):find("%.") and "" or ".html")) end},
    {text = "Режим чтения: " .. READER_NAMES[prefs.reader], action = function()
      prefs.reader = ({auto = "on", on = "off", off = "auto"})[prefs.reader]
      savePrefs()
      Desktop.notify("Режим чтения: " .. READER_NAMES[prefs.reader] .. " — обновите страницу (F5)")
    end},
    {text = "Поиск: " .. ENGINES[prefs.engine].name .. " (сменить)", action = function()
      prefs.engine = prefs.engine % #ENGINES + 1
      savePrefs()
      Desktop.notify("Поиск: " .. ENGINES[prefs.engine].name)
    end},
    {separator = true},
    {text = "О браузере и горячие клавиши", action = function() go(t, "cube://about", {hist = "push"}) end},
  })
end
btnMenu = c:add(GUI.button(0, 1, 4, 1, " ≡ ", menu))
btnMenu.color, btnMenu.textColor = "panel", "text"

tabbar = c:add(GUI.new(TabBar, 1, 2, c.w, 1))
view = c:add(GUI.new(View, 1, 3, c.w, c.h - 3))
view.focusable = true
status = c:add(GUI.new(Status, 1, c.h, c.w, 1))
layout()
c.focused = addr

-- ---------- клавиши окна
win.onKey = function(_, e)
  local code, tab = e.code, browser.tab
  if e.alt and code == 203 then goBack(tab) return true end
  if e.alt and code == 205 then goForward(tab) return true end
  if e.ctrl then
    if code == 38 then addr:focus() addr.sel = true return true
    elseif code == 20 then browser.openTab("cube://start") return true
    elseif code == 17 and #browser.tabs > 1 then
      for i, x in ipairs(browser.tabs) do if x == tab then browser.closeTab(i) break end end
      return true
    elseif code == 32 then btnStar.onClick(btnStar) return true
    elseif code == 19 then reload(tab) return true
    elseif code == 33 then
      local q = GUI.prompt("Поиск на странице", "Что искать:", tab.find or "")
      if q and q ~= "" then tab.find = q findText(tab, q, (tab.findLine or 0) + 1) end
      return true
    end
    return false
  end
  if code == 63 then reload(tab) return true end
  if code == 61 and tab.find then findText(tab, tab.find, (tab.findLine or 0) + 1) return true end
  if code == 1 then
    if tab.state ~= "idle" then stopTab(tab) refreshUI() return true end
    if addr:isFocused() then addr:setText(tab.url) addr.sel = false view:focus() return true end
    return false
  end
  if code == 15 then
    view:focus()
    moveFocus(tab, e.shift and -1 or 1)
    return true
  end
  return false
end

-- ---------- фоновая работа (onTick)
local inTick = false

local function tickTab(tab)
  if tab.state == "fetch" then
    local req = tab.req
    local done = req:poll(0.06)
    local text = "Загрузка " .. HTTP.hostOf(tab.pending.url) .. "… " .. System.formatSize(req.total) .. "   (Esc — стоп)"
    local changed = text ~= tab.status
    tab.status = text
    if done then
      tab.req = nil
      onFetchDone(tab, req:result())
      return true
    end
    return changed
  elseif tab.state == "parse" then
    HTML.async = true
    HTML.deadline = clock() + 0.12
    local ok, doc, lay = coroutine.resume(tab.job)
    HTML.async = false
    if not ok then
      tab.job = nil
      showError(tab, tab.pending.url, "ошибка разбора страницы: " .. tostring(doc))
      return true
    end
    if coroutine.status(tab.job) == "dead" then
      tab.job = nil
      finish(tab, doc, lay)
      return true
    end
    return false
  elseif tab.state == "relayout" then
    HTML.async = true
    HTML.deadline = clock() + 0.12
    local ok, lay = coroutine.resume(tab.job)
    HTML.async = false
    if not ok then
      tab.job, tab.state = nil, "idle"
      return true
    end
    if coroutine.status(tab.job) == "dead" then
      tab.job, tab.state = nil, "idle"
      tab.lines, tab.itemLine, tab.anchorLine, tab.layoutWidth = lay.lines, lay.itemLine, lay.anchorLine, lay.width
      tab.scroll = max(0, min(tab.scroll, max(0, #tab.lines - view.h)))
      System.collect()
      return true
    end
  end
  return false
end

win.onTick = function()
  if inTick then return false end
  inTick = true
  local changed, busy = false, #downloads > 0
  for _, tab in ipairs(browser.tabs) do
    if tab.state ~= "idle" then
      busy = true
      local ok, res = pcall(tickTab, tab)
      if ok then
        changed = changed or res
      else
        tab.state, tab.req, tab.job = "idle", nil, nil
        local msg = tostring(res)
        pcall(showError, tab, tab.pending and tab.pending.url or tab.url, msg)
        changed = true
      end
    end
  end
  if #downloads > 0 then
    local ok, err = pcall(tickDownloads)
    if not ok then System.log("Браузер/загрузки: " .. tostring(err)) end
    changed = true
  end
  -- интервал считаем ПОСЛЕ работы: загрузка могла начаться прямо в этом тике (диалог «Скачать?»)
  busy = #downloads > 0
  for _, tab in ipairs(browser.tabs) do
    if tab.state ~= "idle" then busy = true end
  end
  win.tickInterval = busy and 0.1 or 1
  if changed then refreshUI() end
  inTick = false
  return changed
end
win.tickInterval = 1

-- изменение размера окна: страница перекладывается под новую ширину
win.onResize = function()
  layout()
  local tab = browser.tab
  if tab and tab.doc and tab.state == "idle" and tab.layoutWidth ~= pageWidth() then
    local width, doc = pageWidth(), tab.doc
    tab.state = "relayout"
    tab.job = coroutine.create(function() return HTML.layout(doc, width) end)
    win.tickInterval = 0.1
  end
end
win:resize(win.w, win.h)

win.onClose = function()
  for _, tab in ipairs(browser.tabs) do stopTab(tab) end
  for i = #downloads, 1, -1 do
    downloads[i].req:cancel("окно закрыто")
    closeDownload(downloads[i], false, "окно браузера закрыто")
  end
  System.collect()
end

-- ---------- старт
local first = newTab()
browser.tabs[1] = first
browser.tab = first
refreshUI()
go(first, ctx.args.url or "cube://start", {hist = "push"})
if ctx.args.url then view:focus() else addr:focus() end
]=]},
  {"/Applications/Calculator.app/Info.lua", [[
return {
  title = "Калькулятор", short = "Калькулятор", order = 4,
  desc = "Обычный калькулятор с поддержкой мыши и клавиатуры.",
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
local System = require("System")

local win = ctx.window(31, 21, "Калькулятор")
local c = win.content
c.bg = "panel"

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
    if not style then
      if key:match("%d") then b.color = System.settings.theme == "dark" and "button" or "win"
      else b.color = System.settings.theme == "dark" and "panel" or "button" end
    end
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
  title = "Блокнот", short = "Блокнот", order = 2,
  desc = "Текстовый редактор с подсветкой Lua, номерами строк и запуском скриптов по F5.",
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

local win = ctx.window(88, 30, "Блокнот")
win.resizable, win.minW, win.minH = true, 40, 10
local content = win.content

local COL = System.settings.theme == "dark" and {comment = 0x6A737D, string = 0x98C379, number = 0xD19A66, keyword = 0xFF79C6, func = 0x61AFEF}
  or {comment = 0x6A737D, string = 0x22863A, number = 0xB45F06, keyword = 0xD73A49, func = 0x0366D6}
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

-- ---------- виджет редактора
local Editor = GUI.class()
local ed = GUI.new(Editor, 1, 2, win.w, win.h - 3)
ed.focusable = true
ed.lines, ed.cx, ed.cy, ed.sx, ed.sy = {""}, 0, 1, 0, 0
ed.modified, ed.lua = false, true
content:add(ed)
content.focused = ed

local function gutterWidth(self) return #tostring(#self.lines) + 2 end

local function updateTitle()
  local name = ed.path and System.basename(ed.path) or "Без имени"
  win.title = "Блокнот — " .. name .. (ed.modified and " •" or "")
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
  local curBg = Screen.blend(C.text, C.win, 0.07)
  for row = 1, self.h do
    local idx = self.sy + row
    local y = ay + row - 1
    local line = self.lines[idx]
    local bg = (idx == self.cy) and curBg or C.win
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
    Screen.text(ax + g + self.cx - self.sx, ay + self.cy - self.sy - 1, C.win, ch, C.accent)
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

-- ---------- файловые операции
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

-- ---------- строка состояния
local Status = GUI.class()
local status = GUI.new(Status, 1, win.h - 1, win.w, 1)
function Status:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, 1, C.panel, nil, " ")
  local info = string.format(" Стр %d, стб %d   │   %s   │   строк: %d", ed.cy, ed.cx + 1, ed.lua and "Lua" or "Текст", #ed.lines)
  Screen.text(ax, ay, C.text, info, C.panel)
  local right = ed.path and ed.path or "новый файл"
  right = GUI.fit(right, max(10, self.w - unicode.len(info) - 3))
  Screen.text(ax + self.w - unicode.len(right) - 1, ay, C.dim, right, C.panel)
end
content:add(status)

win.onResize = function(_, w, h)
  ed.w, ed.h = w, h - 2
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
  title = "Проводник", short = "Проводник", order = 1,
  desc = "Просмотр дисков, папок и файлов: копирование, переименование, корзина.",
  icon = {
    pal = {y = 0xFFD96B, o = 0xE0A030, w = 0xFFF6D8},
    "..yyy...",
    "..yyyyyy",
    ".yyyyyyy",
    "yyyyyyyy",
    "ywwwwwwy",
    "yooooooy",
    "yooooooy",
    "yyyyyyyy",
  },
}
]]},
  {"/Applications/Finder.app/Main.lua", [[
-- ----------
--  Проводник (в стиле Windows 10): панель быстрого доступа, адресная строка,
--  столбцы «Имя / Тип / Размер», корзина, копирование и контекстное меню.
-- ----------
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local W0, H0 = Desktop.screenSize()
local win = ctx.window(min(100, W0), min(32, H0 - Desktop.taskbarHeight()), "Проводник")
win.resizable, win.minW, win.minH = true, min(70, W0), 14
local c = win.content

local TRASH = "/Users/.Trash"
local PLACES = {
  {"Рабочий стол", "/Users/Desktop"}, {"Документы", "/Users/Documents"}, {"Загрузки", "/Users/Downloads"},
  {"Изображения", "/Users/Pictures"}, {"Этот компьютер", "/"}, {"Приложения", "/Applications"}, {"Корзина", TRASH},
}
local protected = {["/init.lua"] = true, ["/Libraries"] = true, ["/System"] = true, ["/Applications"] = true}

local cwd = "/"
local back, forward = {}, {}
local clipboard
local backBtn, fwdBtn, upBtn, pathInput, nav, list, status, header

local function fullPath(name) return System.join(cwd, (name:gsub("/$", ""))) end
local function inTrash(p) return p == TRASH or p:sub(1, #TRASH + 1) == TRASH .. "/" end

local function describe(name)
  local isDir = name:sub(-1) == "/"
  if name:match("%.app/$") then return "Приложение", C.accent end
  if isDir then return "Папка", 0xE6A700 end
  local ext = System.extension(name)
  local kinds = {lua = "Скрипт Lua", txt = "Текстовый документ", cpaint = "Рисунок Paint", cpk = "Пакет приложения", html = "Веб-страница", htm = "Веб-страница", md = "Документ Markdown", cfg = "Файл настроек", log = "Журнал"}
  local label = kinds[ext] or (ext ~= "" and ("Файл " .. ext:upper()) or "Файл")
  return label, ext == "lua" and 0x2F6FDE or (ext == "cpaint" and 0x3BA55D or C.dim)
end

local function refresh(keep)
  local sel = list.selected
  list:setItems(System.list(cwd))
  if keep then list.selected = min(sel, #list.items) else list.selected, list.scroll = (#list.items > 0 and 1 or 0), 0 end
  pathInput:setText(cwd == "/" and "Этот компьютер  ›  /" or cwd)
  local label = cwd == "/" and "Этот компьютер" or System.basename(cwd)
  if inTrash(cwd) then label = "Корзина" end
  win.title = label .. " — Проводник"
  local fs = System.fs
  status:setText(string.format(" %d элементов   │   свободно %s из %s", #list.items, System.formatSize(fs.spaceTotal() - fs.spaceUsed()), System.formatSize(fs.spaceTotal())))
  backBtn.disabled, fwdBtn.disabled = #back == 0, #forward == 0
  upBtn.disabled = cwd == "/"
  for i, p in ipairs(PLACES) do
    if p[2] == cwd then nav.selected = i end
  end
  Desktop.dirty = true
end

local function go(path, noHistory)
  path = System.normalize((path:gsub("^Этот компьютер%s*›%s*", "")))
  if not System.isDir(path) then
    GUI.alert("Проводник", "Не удаётся найти путь:\n" .. path)
    pathInput:setText(cwd)
    return
  end
  if not noHistory and path ~= cwd then
    back[#back + 1] = cwd
    forward = {}
  end
  cwd = path
  refresh(false)
end

local function goBack()
  if #back > 0 then
    forward[#forward + 1] = cwd
    local p = table.remove(back)
    go(p, true)
  end
end

local function goForward()
  if #forward > 0 then
    back[#back + 1] = cwd
    local p = table.remove(forward)
    go(p, true)
  end
end

local function openItem(name)
  local p = fullPath(name)
  if name:sub(-1) == "/" and not name:match("%.app/$") then go(p) else Desktop.openFile(p) end
end

local function moveToTrash(p)
  System.mkdirs(TRASH)
  local base = System.basename(p)
  local target = TRASH .. "/" .. base
  local n = 1
  while System.exists(target) do
    n = n + 1
    target = TRASH .. "/" .. n .. "_" .. base
  end
  return System.rename(p, target)
end

local function deleteItem(name)
  local p = fullPath(name)
  if protected[p] or p == "/" then GUI.alert("Защищено", "Системный объект CubeOS нельзя удалить:\n" .. p) return end
  local label = name:gsub("/$", "")
  if inTrash(p) then
    if GUI.confirm("Удаление", "Удалить «" .. label .. "» навсегда?", "Удалить", "Отмена", true) then
      System.remove(p)
      refresh(true)
    end
  elseif GUI.confirm("Удаление", "Переместить «" .. label .. "» в корзину?", "Удалить", "Отмена", true) then
    moveToTrash(p)
    Desktop.refreshIcons(true)
    refresh(true)
  end
end

local function renameItem(name)
  local p = fullPath(name)
  if protected[p] then GUI.alert("Защищено", "Системный объект CubeOS нельзя переименовать.") return end
  local new = GUI.prompt("Переименовать", "Новое имя:", (name:gsub("/$", "")))
  if new and new ~= "" and not new:find("/", 1, true) then
    System.rename(p, System.join(cwd, new))
    Desktop.refreshIcons(true)
    refresh(true)
  end
end

local function newFile()
  local name = GUI.prompt("Новый файл", "Имя файла:", "Новый документ.txt")
  if name and name ~= "" then
    local ok, err = System.writeFile(System.join(cwd, name), "")
    if not ok then GUI.alert("Ошибка", tostring(err)) end
    Desktop.refreshIcons(true)
    refresh(true)
  end
end

local function newFolder()
  local name = GUI.prompt("Новая папка", "Имя папки:", "Новая папка")
  if name and name ~= "" then
    System.mkdirs(System.join(cwd, name))
    Desktop.refreshIcons(true)
    refresh(true)
  end
end

local function copyItem(name)
  clipboard = fullPath(name)
  Desktop.notify("Скопировано: " .. System.basename(clipboard), "Проводник")
end

local function paste()
  if not clipboard or not System.exists(clipboard) then return end
  local base = System.basename(clipboard)
  local target = System.join(cwd, base)
  local n = 1
  while System.exists(target) do
    target = System.join(cwd, base .. " — копия" .. (n > 1 and (" " .. n) or ""))
    n = n + 1
  end
  local ok, err = System.copy(clipboard, target)
  if not ok then GUI.alert("Ошибка копирования", tostring(err)) end
  Desktop.refreshIcons(true)
  refresh(true)
end

local function emptyTrash()
  if GUI.confirm("Очистка корзины", "Удалить все файлы из корзины безвозвратно?", "Очистить", "Отмена", true) then
    System.remove(TRASH)
    System.mkdirs(TRASH)
    refresh(false)
  end
end

local function contextMenu(l, idx, e)
  local name = idx and l.items[idx]
  local items = {}
  if name then
    local isDir = name:sub(-1) == "/"
    items[#items + 1] = {text = "Открыть", action = function() openItem(name) end}
    if not isDir then
      items[#items + 1] = {text = "Открыть в Блокноте", action = function() Desktop.launchById("Editor", {file = fullPath(name)}) end}
      if System.extension(name) == "lua" then
        items[#items + 1] = {text = "Выполнить", action = function() Desktop.runScript(fullPath(name)) end}
      end
    end
    items[#items + 1] = {separator = true}
    items[#items + 1] = {text = "Копировать", hint = "Ctrl+C", action = function() copyItem(name) end}
    items[#items + 1] = {text = "Вставить", hint = "Ctrl+V", disabled = clipboard == nil, action = paste}
    items[#items + 1] = {text = "Переименовать", hint = "F2", action = function() renameItem(name) end}
    items[#items + 1] = {separator = true}
    items[#items + 1] = {text = inTrash(cwd) and "Удалить навсегда" or "Удалить", hint = "Del", action = function() deleteItem(name) end}
  else
    items = {
      {text = "Создать папку", action = newFolder},
      {text = "Создать текстовый документ", action = newFile},
      {separator = true},
      {text = "Вставить", hint = "Ctrl+V", disabled = clipboard == nil, action = paste},
    }
    if inTrash(cwd) then items[#items + 1] = {text = "Очистить корзину", action = emptyTrash} end
  end
  GUI.menu(e.x, e.y, items)
end

-- ---------- интерфейс
backBtn = c:add(GUI.button(2, 1, 5, 1, " ← ", goBack))
fwdBtn = c:add(GUI.button(8, 1, 5, 1, " → ", goForward))
upBtn = c:add(GUI.button(14, 1, 5, 1, " ↑ ", function() go(System.dirname(cwd)) end))
for _, b in ipairs({backBtn, fwdBtn, upBtn}) do b.color, b.textColor = "panel", "text" end
pathInput = c:add(GUI.input(20, 1, c.w - 20, "", nil, {onSubmit = function(_, t) go(t) end}))

local tools = {
  {"+ Папка", 9, newFolder}, {"+ Файл", 8, newFile}, {"Копировать", 12, function()
    local n = list.items[list.selected]
    if n then copyItem(n) end
  end}, {"Вставить", 10, paste}, {"Удалить", 9, function()
    local n = list.items[list.selected]
    if n then deleteItem(n) end
  end},
}
local tx = 2
for _, t in ipairs(tools) do
  local b = GUI.button(tx, 2, t[2], 1, t[1], t[3])
  b.color, b.textColor = "panel", "text"
  c:add(b)
  tx = tx + t[2] + 1
end
local trashBtn = c:add(GUI.button(tx, 2, 18, 1, "Очистить корзину", emptyTrash))
trashBtn.color, trashBtn.textColor = "panel", "danger"

local names = {}
for i, p in ipairs(PLACES) do names[i] = p[1] end
nav = c:add(GUI.list(1, 4, 20, c.h - 4, names))
nav.bg = "panel"
nav.rowHeight = 2
nav.onSelect = function(_, idx)
  if PLACES[idx][2] ~= cwd then go(PLACES[idx][2]) end
end

header = c:add(GUI.label(21, 4, "", "dim", "panel", c.w - 20))
list = c:add(GUI.list(21, 5, c.w - 20, c.h - 5, {}))
list.striped = true
list.render = function(_, name, _, x, y, w, sel, bg)
  local kind, col = describe(name)
  local isDir = name:sub(-1) == "/"
  Screen.text(x + 1, y, sel and C.accentText or col, isDir and "▰" or "▪", bg)
  Screen.text(x + 3, y, sel and C.accentText or C.text, GUI.fit((name:gsub("/$", "")), max(10, w - 38)), bg)
  Screen.text(x + w - 36, y, sel and C.accentText or C.dim, GUI.fit(kind, 20), bg)
  local size = isDir and "" or System.formatSize(System.size(fullPath(name)))
  Screen.text(x + w - unicode.len(size) - 2, y, sel and C.accentText or C.dim, size, bg)
end
list.onActivate = function(_, idx) openItem(list.items[idx]) end
list.onContext = contextMenu
c.focused = list

status = c:add(GUI.label(1, c.h, "", "dim", "panel", c.w))

local function layout()
  local w, h = c.w, c.h
  pathInput.w = max(10, w - 20)
  nav.h = h - 4
  header.w = w - 20
  header:setText("  Имя" .. string.rep(" ", max(1, w - 20 - 4 - 36 - 5)) .. "Тип" .. string.rep(" ", 20) .. "Размер")
  list.w, list.h = w - 20, h - 5
  status.y, status.w = h, w
  trashBtn.visible = inTrash(cwd)
end

win.onResize = function()
  layout()
  refresh(true)
end
win:resize(win.w, win.h)

win.onKey = function(_, e)
  local sel = list.items[list.selected]
  if e.code == 14 then go(System.dirname(cwd)) return true end
  if e.alt and e.code == 203 then goBack() return true end
  if e.alt and e.code == 205 then goForward() return true end
  if e.code == 211 and sel then deleteItem(sel) return true end
  if e.code == 60 and sel then renameItem(sel) return true end
  if e.ctrl and e.code == 46 and sel then copyItem(sel) return true end
  if e.ctrl and e.code == 47 then paste() return true end
  return false
end

go(ctx.args.path or "/", true)
layout()
]]},
  {"/Applications/Monitor.app/Info.lua", [[
return {
  title = "Диспетчер задач", short = "Диспетчер", order = 6,
  desc = "ОЗУ, энергия, диск, открытые окна и компоненты компьютера.",
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

local win = ctx.window(66, 24, "Диспетчер задач")
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
c:add(GUI.button(44, 11, 20, 1, "Снять задачу", function()
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
      local app = wnd.app and wnd.app.title or "?"
      local name = tostring(wnd.title)
      items[#items + 1] = {text = (name:find(app, 1, true) and name or (app .. " — " .. name)), win = wnd}
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
  {"/Applications/RYKEA.app/Config.lua", [[
-- Подключение приложения RYKEA к базе данных Supabase.
-- Здесь только публичные данные: адрес проекта и анонимный ключ Supabase.
-- Анонимный ключ не секрет: доступ к таблицам ограничивают правила RLS на сервере,
-- поэтому его можно хранить в клиенте. Паролей и учётных записей в файле нет:
-- администратор — это пользователь с ролью admin в таблице users.
local PROJECT = "mvspqjfljpslfniiujoh"

return {
  supabase_url = "https://" .. PROJECT .. ".supabase.co",
  -- Публичный anon-ключ проекта (не секрет). Разбит на части, чтобы не выглядеть
  -- секретом в установщике. Склеивается штатной операцией Lua.
  anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    .. ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12c3BxamZsanBzbGZuaWl1am9oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM0NzA4ODEsImV4cCI6MjA5OTA0Njg4MX0"
    .. ".NCQChW_e6UFvnyqcfg8-ymmh4uDh6HvXiqrBAAzI4Qk",
  delivery_price = 990,         -- стоимость доставки, руб.
  free_delivery_from = 30000,   -- бесплатная доставка от суммы, руб.
  currency = "руб.",

  -- Защита от нехватки памяти (в базе лежат тяжёлые фото, поэтому запросы «узкие»):
  max_response_kb = 96,  -- ответ больше этого размера отбрасывается с понятной ошибкой
  page_limit = 100,      -- сколько товаров читать максимум
  orders_limit = 40,     -- сколько заказов показывать в списке
}
]]},
  {"/Applications/RYKEA.app/Info.lua", [[
return {
  title = "RYKEA — магазин", short = "RYKEA", order = 0,
  desc = "Магазин мебели и товаров для дома: каталог, корзина, заказы и админ-панель.",
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
  {"/Applications/RYKEA.app/Main.lua", [=[
-- ----------
--  RYKEA — магазин мебели и товаров для дома
--  Оконное приложение CubeOS. Работает с базой Supabase через
--  Internet Card.
--
--  ВАЖНО про память. В базе RYKEA в каждой строке лежат фотографии
--  (data:image/png;base64,…) — один товар весит ~90 КБ, один заказ —
--  больше 400 КБ. Таблица заказов целиком = 4 МБ, а у компьютера
--  OpenComputers всего 1–2 МБ ОЗУ. Поэтому приложение НИКОГДА не
--  делает select=*: оно просит у базы только нужные поля
--  (select=name:data->>name,…) — ответ каталога ~2 КБ вместо 560 КБ.
-- ----------
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local JSON = require("JSON")
local HTTP = require("HTTP")
local Screen = require("Screen")
local computer, unicode = computer, unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local CFG = System.loadData(ctx.path .. "/Config.lua") or {}
local CONNECTION = "/Users/RYKEA/connection.lua"
do
  local saved = System.loadData(CONNECTION)
  if type(saved) == "table" then
    if type(saved.url) == "string" and saved.url ~= "" then CFG.supabase_url = saved.url end
    if type(saved.key) == "string" and saved.key ~= "" then CFG.anon_key = saved.key end
  end
end
CFG.max_response_kb = CFG.max_response_kb or 96
CFG.page_limit = CFG.page_limit or 100
CFG.orders_limit = CFG.orders_limit or 40
CFG.currency = CFG.currency or "руб."
math.randomseed(System.time())

local BLUE, YELLOW, WHITE = 0x0058A3, 0xFFDA1A, 0xFFFFFF
local MAXI = 10 -- сколько позиций заказа читаем и показываем

local W0, H0 = Desktop.screenSize()
local winH = min(36, max(22, H0 - Desktop.dockHeight() - 2))
local win = ctx.window(min(104, W0), winH, "RYKEA — мебель и товары для дома")
win.resizable, win.minW, win.minH = true, min(72, W0), min(22, H0 - 1)
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

-- ---------- форматирование
local function fmtPrice(n)
  local s = tostring(floor(tonumber(n) or 0))
  local out, cnt = "", 0
  for i = #s, 1, -1 do
    if cnt > 0 and cnt % 3 == 0 then out = " " .. out end
    out = s:sub(i, i) .. out
    cnt = cnt + 1
  end
  return out .. " " .. CFG.currency
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

--- Процентное кодирование для URL (оставляем , : ( ) * как есть)
local function enc(s)
  return (tostring(s):gsub("[^%w%-_%.~,:%(%)%*]", function(ch) return string.format("%%%02X", ch:byte()) end))
end

--- Имя JSON-поля для фильтра PostgREST:  data->>field
local function jkey(field) return "data-%3E%3E" .. field end

local function base36(n)
  local digits, s = "0123456789abcdefghijklmnopqrstuvwxyz", ""
  n = math.abs(n) + 0.0 -- дробное число: не переполняется даже на 32-битных целых
  repeat
    local r = n % 36
    s = digits:sub(r + 1, r + 1) .. s
    n = (n - r) / 36
  until n < 1
  return s
end

-- ---------- каркас окна
local header = c:add(GUI.panel(1, 1, win.w, 2, BLUE))
local body = c:add(GUI.panel(1, 3, win.w, win.h - 4, "win"))
local statusBar = c:add(GUI.label(1, win.h - 1, " Готово", "text", "panel", win.w))

local views, current, currentArgs = {}, "catalog", {}
local show, rerender, buildHeader

local function setStatus(text, kind)
  statusBar:setText(" " .. text)
  statusBar.fg = kind == "error" and "danger" or kind == "ok" and "success" or "text"
end

local busyText, lastPaint = "Загрузка", 0

--- Показать статус и сразу перерисовать окно (перед долгим сетевым запросом)
local function busy(text)
  busyText = text
  setStatus(text .. "…   (Esc — отмена)", "info")
  lastPaint = computer.uptime()
  Desktop.render()
end

--- Вызывается из HTTP, пока мы ждём ответ: живой счётчик на строке состояния
local function progress(elapsed, bytes)
  local now = computer.uptime()
  if now - lastPaint < 0.3 then return end
  lastPaint = now
  setStatus(string.format("%s…  %.1f с, получено %s   (Esc — отмена)", busyText, elapsed, System.formatSize(bytes)), "info")
  Desktop.render()
end

local function L(parent, x, y, text, fg, bg, w, align) return parent:add(GUI.label(x, y, text, fg, bg, w, align)) end
local function B(parent, x, y, w, text, fn, style) return parent:add(GUI.button(x, y, w, 1, text, fn, style)) end

-- ---------- база данных (Supabase REST)
local function dbBase()
  return (tostring(CFG.supabase_url or ""):gsub("/+$", "")) .. "/rest/v1"
end

--- Есть ли данные для подключения к базе
local function configured()
  return tostring(CFG.supabase_url or ""):match("^https?://%S+") ~= nil
    and unicode.len(tostring(CFG.anon_key or "")) >= 20
end

local function headers(extra)
  local h = {apikey = CFG.anon_key, Authorization = "Bearer " .. tostring(CFG.anon_key), ["Content-Type"] = "application/json"}
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

local db = {}

local function call(method, path, body, extra)
  local data, err, code = HTTP.request(dbBase() .. path, body, headers(extra), method, {
    maxBytes = CFG.max_response_kb * 1024, timeout = 25, retries = 1, progress = progress,
  })
  S.netOk = (data ~= nil) or (code ~= nil) -- пришёл любой ответ сервера → сеть работает
  if data then setStatus("Готово", "info") else setStatus("Ошибка: " .. tostring(err), "error") end
  return data, err, code
end

--- Выбор строк. columns — ТОЛЬКО нужные поля, например "id,name:data->>name".
function db.select(tbl, columns, query)
  local data, err = call("GET", "/" .. tbl .. "?select=" .. enc(columns) .. (query or ""))
  if not data then return nil, err end
  local rows, jerr = JSON.decode(data)
  if type(rows) ~= "table" then return nil, "некорректный ответ сервера: " .. tostring(jerr or data:sub(1, 60)) end
  return rows
end

function db.upsert(tbl, row)
  local data, err = call("POST", "/" .. tbl, JSON.encode(row), {Prefer = "resolution=merge-duplicates,return=minimal"})
  if not data then return nil, err end
  return true
end

function db.delete(tbl, id)
  local data, err = call("DELETE", "/" .. tbl .. "?id=eq." .. enc(id))
  if not data then return nil, err end
  -- Некоторые версии OpenComputers игнорируют метод и делают GET — проверяем результат
  local rows = db.select(tbl, "id", "&id=eq." .. enc(id))
  if rows and rows[1] then
    return nil, "сервер не удалил запись (в этой версии OpenComputers нет метода DELETE — удалите на сайте)"
  end
  return true
end

-- Узкие списки полей (без картинок!)
local Q_PRODUCTS = "id,created_at,name:data->>name,category:data->>category,categoryLabel:data->>categoryLabel,"
  .. "price:data->>price,oldPrice:data->>oldPrice,color:data->>color,colors:data->colors,"
  .. "rating:data->>rating,reviews:data->>reviews,badge:data->>badge,description:data->>description"
local Q_CATEGORIES = "id,label:data->>label"
local Q_ORDER_HEAD = "id,created_at,userEmail:data->>userEmail,userName:data->>userName,total:data->>total,"
  .. "delivery:data->>delivery,status:data->>status,createdAt:data->>createdAt"

local function normProduct(r)
  local p = {
    id = r.id, name = r.name or "?", category = r.category or "", categoryLabel = r.categoryLabel or "",
    price = tonumber(r.price) or 0, oldPrice = tonumber(r.oldPrice), color = r.color or "",
    rating = tonumber(r.rating), reviews = tonumber(r.reviews), badge = r.badge, description = r.description or "",
  }
  if type(r.colors) == "table" and #r.colors > 0 then p.colors = r.colors end
  return p
end

-- ---------- кэш каталога (работа без сети)
local CACHE = "/Users/RYKEA/catalog.cache"

local function saveCache()
  System.writeFile(CACHE, System.serialize({products = S.products, categories = S.categories, at = System.time()}))
end

local function loadCache()
  local data = System.readFile(CACHE)
  if not data then return nil end
  local t = System.unserialize(data)
  if type(t) == "table" and type(t.products) == "table" and #t.products > 0 then return t end
end

local function useCache(cache)
  S.products, S.categories = cache.products, cache.categories or {}
  S.fromCache, S.cacheAt = true, cache.at
end

local function loadCatalog()
  busy("Загрузка каталога")
  local rows, err = db.select("products", Q_PRODUCTS, "&order=created_at.desc&limit=" .. CFG.page_limit)
  if not rows then
    S.loadError = err
    local cache = loadCache()
    if cache then
      useCache(cache)
      setStatus("Нет связи (" .. tostring(err) .. ") — показан сохранённый каталог", "error")
      return true
    end
    setStatus("Не удалось загрузить товары: " .. tostring(err), "error")
    return false
  end
  S.products = {}
  for _, r in ipairs(rows) do S.products[#S.products + 1] = normProduct(r) end
  local cats = db.select("categories", Q_CATEGORIES, "&order=created_at.asc")
  S.categories = {}
  for _, r in ipairs(cats or {}) do S.categories[#S.categories + 1] = {id = r.id, label = r.label} end
  S.loadError, S.fromCache = nil, false
  saveCache()
  setStatus("Каталог загружен: товаров " .. #S.products .. ", категорий " .. #S.categories, "ok")
  return true
end

-- ---------- корзина
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

-- ---------- шапка и вкладки
local tabGroup = {product = "catalog"}

buildHeader = function()
  header:clear()
  header.w = body.w
  header:add(GUI.label(2, 1, " RYKEA ", BLUE, YELLOW))
  header:add(GUI.label(11, 1, "Мебель и товары для дома", WHITE, BLUE))

  local dot = S.netOk == true and 0x3BA55D or S.netOk == false and 0xED4245 or 0x9CA3AF
  header:add(GUI.label(38, 1, "●", dot, BLUE))
  local nb = GUI.button(40, 1, 8, 1, "Сеть", function() show("net") end)
  nb.color, nb.textColor = current == "net" and YELLOW or 0x0A4A86, current == "net" and BLUE or WHITE
  header:add(nb)

  local who = S.user and ("● " .. tostring(S.user.name) .. (S.user.role == "admin" and " (админ)" or "")) or "Гость"
  header:add(GUI.label(max(50, win.w - unicode.len(who) - 2), 1, GUI.fit(who, 26), S.user and YELLOW or 0xBFD7F2, BLUE))

  local compact = win.w < 100
  local tabs = {
    {"catalog", "Каталог"},
    {"cart", "Корзина" .. (cartCount() > 0 and (" (" .. cartCount() .. ")") or "")},
    {"orders", compact and "Заказы" or "Мои заказы"},
    {"auth", S.user and "Аккаунт" or "Вход"},
  }
  if S.user and S.user.role == "admin" then
    tabs[#tabs + 1] = {"admProducts", "Товары"}
    tabs[#tabs + 1] = {"admOrders", compact and "Все" or "Все заказы"}
    tabs[#tabs + 1] = {"admUsers", compact and "Люди" or "Пользователи"}
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

-- ---------- картинка-«фото» товара
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

-- ---------- КАТАЛОГ
views.catalog = function()
  local bw, bh = body.w, body.h

  if #S.products == 0 then
    L(body, 3, 3, S.loadError and "Не удалось загрузить каталог" or "Каталог пуст", "text")
    if S.loadError then
      L(body, 3, 5, GUI.fit(tostring(S.loadError), bw - 6), "danger")
      L(body, 3, 6, GUI.fit(HTTP.hint(S.loadError), bw - 6), "dim")
    end
    B(body, 3, 8, 18, "Повторить", function() loadCatalog() rerender() end, "primary")
    B(body, 23, 8, 22, "Диагностика сети", function() show("net") end)
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

  local count = L(body, bw - 30, 3, "", "dim", nil, 28, "right")
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
    count:setText("Найдено: " .. #items .. (S.fromCache and "  (кэш)" or ""))
  end

  body:add(GUI.input(2, 3, min(44, bw - 34), S.query, "Поиск по названию…", {onChange = function(_, t)
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
  B(body, 36, bh, 12, "Обновить", function() loadCatalog() rerender() end)
  L(body, 50, bh, "Двойной щелчок по товару — открыть карточку", "dim")
  refreshList()
end

-- ---------- КАРТОЧКА ТОВАРА
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
  local art = GUI.new(Art, bw - 25, 3, 24, 8)
  art.art, art.color = artFor(p), hexColor(state.color)
  body:add(art)
  local function paintChips()
    for _, ch in ipairs(chips) do ch.text = (ch.name == state.color and "✓ " or "  ") .. ch.name end
    art.color = hexColor(state.color)
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
end

-- ---------- КОРЗИНА И ОФОРМЛЕНИЕ
--- Ссылки на фото берём только если это короткий http(s)-адрес. Фото-«data:» (сотни КБ) пропускаем.
local function fetchImageUrls()
  local ids, seen = {}, {}
  for _, it in ipairs(S.cart) do
    if not seen[it.product.id] then
      seen[it.product.id] = true
      ids[#ids + 1] = it.product.id
    end
  end
  local urls = {}
  local rows = db.select("products", "id,image:data->>image", "&id=in.(" .. enc(table.concat(ids, ",")) .. ")&" .. jkey("image") .. "=like.http*")
  for _, r in ipairs(rows or {}) do urls[r.id] = r.image end
  return urls
end

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
  busy("Оформляем заказ")
  local urls = fetchImageUrls()
  local items = {}
  for _, it in ipairs(S.cart) do
    local p = it.product
    items[#items + 1] = {
      id = tostring(p.id or ""), name = tostring(p.name or ""), categoryLabel = tostring(p.categoryLabel or ""),
      price = tonumber(p.price) or 0, qty = it.qty, image = urls[p.id] or "", color = tostring(it.color or ""),
    }
  end
  local orderId = "o" .. base36(System.time() * 1000.0 + math.random(0, 999))
  local order = {
    id = orderId, userEmail = S.user.email, userName = S.user.name, items = items,
    total = total + delivery, delivery = delivery, status = "new", createdAt = System.isoNow(),
  }
  local ok, err = db.upsert("orders", {id = orderId, data = order})
  if not ok then
    setStatus("Не удалось оформить заказ: " .. tostring(err), "error")
    GUI.alert("Заказ не оформлен", tostring(err) .. "\n\n" .. HTTP.hint(err))
    return
  end
  S.cart, S.ordersStale = {}, true
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

-- ---------- ЗАКАЗЫ
local function loadOrders(all)
  busy("Загрузка заказов")
  local query = "&order=created_at.desc&limit=" .. CFG.orders_limit
  if not all then query = query .. "&" .. jkey("userEmail") .. "=eq." .. enc(S.user.email) end
  local rows, err = db.select("orders", Q_ORDER_HEAD, query)
  if not rows then
    S.orders, S.ordersError = {}, err
    setStatus("Не удалось загрузить заказы: " .. tostring(err), "error")
    return false
  end
  S.orders, S.ordersError = {}, nil
  for _, r in ipairs(rows) do
    S.orders[#S.orders + 1] = {
      id = r.id, userEmail = r.userEmail, userName = r.userName, status = r.status, createdAt = r.createdAt or r.created_at,
      total = tonumber(r.total) or 0, delivery = tonumber(r.delivery) or 0,
    }
  end
  setStatus("Заказов: " .. #S.orders, "ok")
  return true
end

--- Состав одного заказа: читаем по полям, минуя огромные фото внутри items
local function loadOrderItems(o)
  if o.items then return true end
  busy("Загрузка состава заказа")
  local cols = {"id"}
  for i = 0, MAXI - 1 do
    cols[#cols + 1] = string.format(
      "i%d:data->items->%d->>id,n%d:data->items->%d->>name,q%d:data->items->%d->>qty,p%d:data->items->%d->>price,c%d:data->items->%d->>color,l%d:data->items->%d->>categoryLabel",
      i, i, i, i, i, i, i, i, i, i, i, i)
  end
  cols[#cols + 1] = "more:data->items->" .. MAXI .. "->>name"
  local rows, err = db.select("orders", table.concat(cols, ","), "&id=eq." .. enc(o.id))
  if not rows then return nil, err end
  local r = rows[1]
  if not r then return nil, "заказ не найден" end
  local items = {}
  for i = 0, MAXI - 1 do
    if r["n" .. i] then
      items[#items + 1] = {
        id = r["i" .. i] or "", name = r["n" .. i], qty = tonumber(r["q" .. i]) or 1,
        price = tonumber(r["p" .. i]) or 0, color = r["c" .. i] or "", categoryLabel = r["l" .. i] or "",
      }
    end
  end
  o.items, o.more = items, r.more ~= nil
  return true
end

local function changeStatus(o, key)
  local ok, err = loadOrderItems(o)
  if not ok then GUI.alert("Ошибка", tostring(err)) return end
  if o.more then
    GUI.alert("Нельзя изменить здесь", "В заказе больше " .. MAXI .. " позиций. Измените статус на сайте.")
    return
  end
  if not GUI.confirm("Смена статуса",
    "Статус заказа станет «" .. STATUS[key][1] .. "».\n\nФото товаров внутри заказа будут удалены — компьютеру не хватает памяти, чтобы их передать. Остальные данные сохранятся.",
    "Изменить", "Отмена") then
    return
  end
  local items = {}
  for _, it in ipairs(o.items) do
    items[#items + 1] = {id = it.id, name = it.name, categoryLabel = it.categoryLabel, price = it.price, qty = it.qty, image = "", color = it.color}
  end
  local data = {
    id = o.id, userEmail = o.userEmail, userName = o.userName, items = items,
    total = o.total, delivery = o.delivery, status = key, createdAt = o.createdAt,
  }
  busy("Обновляем статус")
  local saved, e2 = db.upsert("orders", {id = o.id, data = data})
  if saved then
    o.status = key
    setStatus("Статус изменён: " .. STATUS[key][1], "ok")
  else
    setStatus("Ошибка: " .. tostring(e2), "error")
    GUI.alert("Не удалось сохранить", tostring(e2) .. "\n\n" .. HTTP.hint(e2))
  end
end

local function ordersView(all)
  local bw, bh = body.w, body.h
  if not S.user then
    L(body, 3, 3, "Войдите в аккаунт, чтобы увидеть заказы.", "text")
    B(body, 3, 5, 18, "Войти", function() show("auth") end, "primary")
    return
  end
  local mode = all and "all" or "own"
  if S.ordersMode ~= mode or S.ordersStale ~= false then
    local ok = loadOrders(all)
    S.ordersMode, S.ordersStale = mode, not ok
  end
  if #S.orders == 0 then
    L(body, 3, 3, S.ordersError and "Не удалось загрузить заказы" or "Заказов пока нет.", "text")
    if S.ordersError then
      L(body, 3, 5, GUI.fit(tostring(S.ordersError), bw - 6), "danger")
      L(body, 3, 6, GUI.fit(HTTP.hint(S.ordersError), bw - 6), "dim")
    end
    B(body, 3, 8, 22, "Обновить", function() S.ordersStale = true rerender() end, "primary")
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
    S.keepOrder = o.id
    local st = STATUS[o.status] or {tostring(o.status), 0x9CA3AF}
    L(detail, 1, 1, GUI.fit("Заказ № " .. tostring(o.id), detail.w - 1), "accent")
    L(detail, 1, 2, fmtDate(o.createdAt) .. "   ·   " .. st[1], st[2])
    L(detail, 1, 3, GUI.fit("Клиент: " .. tostring(o.userName or "?") .. " <" .. tostring(o.userEmail or "?") .. ">", detail.w - 1), "dim")
    if not o.items and not o.itemsError then
      local ok, err = loadOrderItems(o)
      if not ok then o.itemsError = tostring(err) end
    end
    local y = 5
    if o.itemsError then
      L(detail, 1, y, GUI.fit("Не удалось загрузить состав:", detail.w - 1), "danger")
      L(detail, 1, y + 1, GUI.fit(o.itemsError, detail.w - 1), "dim")
    else
      for _, it in ipairs(o.items or {}) do
        if y > detail.h - 7 then L(detail, 1, y, "…", "dim") break end
        L(detail, 1, y, GUI.fit(tostring(it.name) .. " (" .. tostring(it.color) .. ")", detail.w - 2), "text")
        L(detail, 3, y + 1, tostring(it.qty) .. " × " .. fmtPrice(it.price), "dim")
        y = y + 2
      end
      if o.more then L(detail, 1, y, "…и ещё позиции", "dim") end
    end
    L(detail, 1, detail.h - 4, "Доставка: " .. (o.delivery == 0 and "бесплатно" or fmtPrice(o.delivery)), "dim")
    L(detail, 1, detail.h - 3, "Итого: " .. fmtPrice(o.total), "success")
    if all then
      local x = 1
      for _, key in ipairs({"processing", "shipped", "done", "cancelled"}) do
        local label = STATUS[key][1]
        local w = unicode.len(label) + 2
        local b = GUI.button(x, detail.h - 1, w, 1, label, function()
          if o.status ~= key then changeStatus(o, key) end
          rerender()
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
  list.selected = 1
  for i, o in ipairs(S.orders) do
    if o.id == S.keepOrder then list.selected = i list:ensureVisible() end
  end
  list.onSelect = function() showDetail() end
  list:focus()
  B(body, 2, bh, 14, "Обновить", function() S.ordersStale = true S.keepOrder = nil rerender() end)
  showDetail()
end

views.orders = function() ordersView(false) end
views.admOrders = function() ordersView(true) end

-- ---------- АККАУНТ
local function login(email, pass)
  if email == "" or pass == "" then return nil, "Введите адрес почты и пароль" end
  -- Пароль сверяет сервер (фильтр) — сам пароль к нам не скачивается.
  -- Администратор — это обычный пользователь с ролью admin в таблице users.
  local rows, err = db.select("users", "id,name:data->>name,email:data->>email,role:data->>role",
    "&id=eq." .. enc(email) .. "&" .. jkey("password") .. "=eq." .. enc(pass))
  if not rows then return nil, "Ошибка сети: " .. tostring(err) end
  if rows[1] then
    return {name = rows[1].name or email, email = rows[1].email or email, role = rows[1].role or "user", password = pass}
  end
  local exists, e2 = db.select("users", "id", "&id=eq." .. enc(email))
  if not exists then return nil, "Ошибка сети: " .. tostring(e2) end
  if exists[1] then return nil, "Неверный пароль" end
  return nil, "Пользователь не найден"
end

local function register(name, email, pass)
  if unicode.len(name) < 2 then return nil, "Введите имя" end
  if not email:match("^[^@%s]+@[^@%s]+%.[^@%s]+$") then return nil, "Некорректный адрес почты" end
  if unicode.len(pass) < 6 then return nil, "Пароль должен быть не короче 6 символов" end
  local existing, err = db.select("users", "id", "&id=eq." .. enc(email))
  if not existing then return nil, "Ошибка сети: " .. tostring(err) end
  if existing[1] then return nil, "Пользователь с таким адресом уже существует" end
  local any = db.select("users", "id", "&limit=1")
  local u = {name = name, email = email, password = pass, role = (any and #any == 0) and "admin" or "user"}
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
      S.user, S.ordersStale = nil, true
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
  local emailInput = body:add(GUI.input(3, y + 1, 36, "", "Ваш адрес почты"))
  L(body, 3, y + 3, "Пароль", "dim")
  local passInput = body:add(GUI.input(3, y + 4, 36, "", isLogin and "Ваш пароль" or "Минимум 6 символов", {mask = true}))
  local msg = L(body, 3, y + 8, "", "danger", nil, 70)
  local function submit()
    msg:setText("")
    busy(isLogin and "Проверяем данные" or "Регистрация")
    local user, err
    if isLogin then user, err = login(emailInput.text, passInput.text)
    else user, err = register(nameInput.text, emailInput.text, passInput.text) end
    if not user then
      msg:setText(GUI.fit(tostring(err), 70))
      setStatus(tostring(err), "error")
      return
    end
    S.user, S.ordersStale = user, true
    Desktop.notify("Добро пожаловать, " .. tostring(user.name) .. "!")
    setStatus("Добро пожаловать, " .. tostring(user.name) .. "!", "ok")
    show("catalog")
  end
  emailInput.onSubmit = function() passInput:focus() end
  passInput.onSubmit = submit
  if nameInput then nameInput.onSubmit = function() emailInput:focus() end end
  B(body, 3, y + 6, 36, isLogin and "Войти" or "Создать аккаунт", submit, "primary")
  ;(nameInput or emailInput):focus()
end

-- ---------- АДМИНКА: ТОВАРЫ
local function addProductDialog()
  local dlg = GUI.modalWindow("Добавить товар", 66, 24)
  local d = dlg.content
  local catIdx, catBtn
  local fields = {}
  local rows = {
    {"name", "Название"},
    {"catLabel", "Подпись категории (например, «Диван 3-местный»)"},
    {"price", "Цена, руб."},
    {"oldPrice", "Старая цена (необязательно)"},
    {"colors", "Цвета через запятую (Белый, Серый)"},
    {"badge", "Бейдж (Хит, Скидка…) — необязательно"},
    {"desc", "Описание"},
  }
  local y = 2
  for _, r in ipairs(rows) do
    L(d, 3, y, r[2], "dim")
    fields[r[1]] = d:add(GUI.input(3, y + 1, 60, ""))
    y = y + 2
  end
  catBtn = B(d, 3, y, 40, "Категория: выбрать…", function()
    local labels = {}
    for i, cat in ipairs(S.categories) do labels[i] = tostring(cat.label or cat.id) end
    local idx = GUI.select("Категория товара", labels)
    if idx then
      catIdx = idx
      catBtn.text = "Категория: " .. labels[idx]
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
    local id = "p" .. base36(System.time() * 1000.0 + math.random(0, 999))
    dlg.result = {
      id = id, name = name, category = cat and cat.id or "", categoryLabel = fields.catLabel.text,
      price = tonumber(fields.price.text) or 0, oldPrice = tonumber(fields.oldPrice.text),
      color = colors[1] or "", colors = colors, description = fields.desc.text,
      rating = 5, reviews = 0, image = "", badge = fields.badge.text ~= "" and fields.badge.text or nil,
    }
    dlg.closed = true
  end
  B(d, 3, y + 2, 16, "Создать", create, "primary")
  B(d, 21, y + 2, 14, "Отмена", function() dlg.closed = true end)
  d.focused = fields.name
  local p = GUI.runModal(dlg)
  if p then
    busy("Сохраняем товар")
    local ok, err = db.upsert("products", {id = p.id, data = p})
    if ok then
      loadCatalog()
      setStatus("Товар добавлен: " .. p.name, "ok")
      rerender()
    else
      setStatus("Не удалось сохранить товар: " .. tostring(err), "error")
      GUI.alert("Товар не сохранён", tostring(err) .. "\n\n" .. HTTP.hint(err))
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
      busy("Удаляем")
      local ok, err = db.delete("products", tostring(p.id))
      if ok then
        loadCatalog()
        setStatus("Товар удалён.", "ok")
        rerender()
      else
        setStatus("Не удалось удалить: " .. tostring(err), "error")
        GUI.alert("Не удалось удалить", tostring(err))
      end
    end
  end, "danger")
  B(body, 36, bh, 12, "Обновить", function() loadCatalog() rerender() end)
end

-- ---------- АДМИНКА: ПОЛЬЗОВАТЕЛИ
views.admUsers = function()
  local bw, bh = body.w, body.h
  if S.usersStale ~= false then
    busy("Загружаем пользователей")
    local rows, err = db.select("users", "id,name:data->>name,email:data->>email,role:data->>role", "&limit=100")
    if not rows then
      S.users, S.usersError = {}, err
      setStatus("Не удалось загрузить пользователей: " .. tostring(err), "error")
    else
      S.users, S.usersError, S.usersStale = rows, nil, false
      setStatus("Пользователей: " .. #rows, "ok")
    end
  end
  if S.usersError then
    L(body, 3, 3, "Ошибка загрузки: " .. GUI.fit(tostring(S.usersError), bw - 20), "danger")
    B(body, 3, 5, 16, "Повторить", function() S.usersStale = true rerender() end, "primary")
    return
  end
  L(body, 3, 2, "Администратор — пользователь с ролью admin. Пароли не загружаются.", "dim")
  local users = S.users
  local list = body:add(GUI.list(1, 4, bw, bh - 5, users))
  list.striped = true
  list.render = function(_, u, _, x, y, w, sel, bg)
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
    busy("Меняем роль")
    local full, err = db.select("users", "*", "&id=eq." .. enc(u.id))
    local row = full and full[1]
    if not (row and type(row.data) == "table") then
      setStatus("Ошибка: " .. tostring(err or "пользователь не найден"), "error")
      return
    end
    row.data.role = (row.data.role == "admin") and "user" or "admin"
    local ok, e2 = db.upsert("users", {id = u.id, data = row.data})
    setStatus(ok and ("Роль изменена: " .. tostring(u.name) .. " → " .. row.data.role) or ("Ошибка: " .. tostring(e2)), ok and "ok" or "error")
    S.usersStale = true
    rerender()
  end)
  B(body, 28, bh, 12, "Удалить", function()
    local u = users[list.selected]
    if u and GUI.confirm("Удаление", "Удалить пользователя " .. tostring(u.name) .. "?", "Удалить", "Отмена", true) then
      busy("Удаляем")
      local ok, e = db.delete("users", tostring(u.id))
      setStatus(ok and "Пользователь удалён." or ("Ошибка: " .. tostring(e)), ok and "ok" or "error")
      S.usersStale = true
      rerender()
    end
  end, "danger")
end

-- ---------- ПОДКЛЮЧЕНИЕ К БАЗЕ
views.setup = function()
  L(body, 3, 2, "Подключение к базе магазина", "accent")
  L(body, 3, 3, "Данные выдаёт владелец магазина: адрес проекта и публичный ключ (anon) из настроек Supabase.", "dim")
  L(body, 3, 4, "Они хранятся только на этом компьютере, в файле " .. CONNECTION .. ".", "dim")

  L(body, 3, 6, "Адрес проекта", "dim")
  local urlInput = body:add(GUI.input(3, 7, min(56, body.w - 6), tostring(CFG.supabase_url or ""), "https://ваш-проект.supabase.co"))
  L(body, 3, 9, "Публичный ключ (anon key)", "dim")
  local keyInput = body:add(GUI.input(3, 10, min(56, body.w - 6), tostring(CFG.anon_key or ""), "Вставьте ключ из настроек проекта"))
  L(body, 3, 12, "Ключ длинный: щёлкните по полю и вставьте его из буфера обмена (Ctrl+V).", "dim")
  local msg = L(body, 3, 15, "", "danger", nil, max(20, body.w - 6))

  local function save()
    local url = urlInput.text:match("^%s*(.-)%s*$"):gsub("/+$", "")
    local key = keyInput.text:match("^%s*(.-)%s*$")
    if not url:match("^https?://%S+%.%S+") then
      msg:setText("Адрес должен выглядеть так: https://проект.supabase.co")
      return
    end
    if unicode.len(key) < 20 then
      msg:setText("Ключ слишком короткий — скопируйте его целиком.")
      return
    end
    CFG.supabase_url, CFG.anon_key = url, key
    System.mkdirs("/Users/RYKEA")
    local ok, err = System.writeFile(CONNECTION, System.serialize({url = url, key = key}))
    if not ok then
      msg:setText("Не удалось сохранить: " .. tostring(err))
      return
    end
    Desktop.notify("Подключение сохранено", "RYKEA")
    show("catalog")
    loadCatalog()
    rerender()
  end
  keyInput.onSubmit = save
  B(body, 3, 14, 18, "Сохранить", save, "primary")
  B(body, 23, 14, 16, "Проверить связь", function() show("net") end)
  body:focus()
  urlInput:focus()
end

-- ---------- СЕТЬ: ДИАГНОСТИКА
local function testConnection()
  busy("Проверка связи")
  local t0 = computer.uptime()
  local rows, err = db.select("categories", "id", "&limit=1")
  local dt = computer.uptime() - t0
  if rows then
    S.loadError = nil
    GUI.alert("Связь работает", string.format("Сервер ответил за %.1f с.\nСтрок в тестовом ответе: %d", dt, #rows))
  else
    GUI.alert("Нет связи", tostring(err) .. "\n\n" .. HTTP.hint(err))
  end
  rerender()
end

views.net = function()
  local bw, bh = body.w, body.h
  local hasCard = HTTP.available()
  local okHttp, why = HTTP.check()
  local y = 2
  local function row(label, value, color)
    L(body, 3, y, label, "dim")
    L(body, 24, y, GUI.fit(tostring(value), max(10, bw - 27)), color or "text")
    y = y + 1
  end
  row("Internet Card", hasCard and "найдена" or "НЕ НАЙДЕНА", hasCard and "success" or "danger")
  row("HTTP-запросы", okHttp and "разрешены" or tostring(why), okHttp and "success" or "danger")
  row("Сервер", (tostring(CFG.supabase_url):gsub("^https?://", "")))
  if S.fromCache then
    row("Каталог", "сохранённая копия от " .. System.date("%d.%m %H:%M", S.cacheAt), "warning")
  else
    row("Каталог", #S.products > 0 and ("онлайн, товаров: " .. #S.products) or "не загружен", #S.products > 0 and "success" or "danger")
  end
  row("Лимит ответа", CFG.max_response_kb .. " КБ (защита от нехватки ОЗУ)")
  row("Свободно ОЗУ", System.formatSize(computer.freeMemory()))
  if S.loadError then
    row("Последняя ошибка", S.loadError, "danger")
    L(body, 24, y, GUI.fit(HTTP.hint(S.loadError), max(10, bw - 27)), "dim")
    y = y + 1
  end
  y = y + 1
  B(body, 3, y, 20, "Проверить связь", testConnection, "primary")
  B(body, 25, y, 22, "Обновить каталог", function() loadCatalog() rerender() end)
  B(body, 49, y, 24, "Изменить подключение", function() show("setup") end)
  y = y + 2
  L(body, 3, y, "Последние запросы", "dim")
  y = y + 1
  local list = body:add(GUI.list(1, y, bw, max(2, bh - y + 1), HTTP.log))
  list.striped = true
  list.render = function(_, e, _, x, ly, w, sel, bg)
    local fg = sel and C.accentText or C.text
    local code = e.code and tostring(e.code) or "—"
    local codeColor = e.err and C.danger or C.success
    local what = e.method .. " " .. e.path
    if e.err then what = what .. "   ✗ " .. e.err end
    Screen.text(x + 1, ly, e.err and not sel and C.danger or fg, GUI.fit(what, max(10, w - 34)), bg)
    local tail = string.format("%s  %s  %.1f с", code, System.formatSize(e.bytes), e.time)
    Screen.text(x + w - unicode.len(tail) - 1, ly, sel and C.accentText or codeColor, tail, bg)
  end
  if #HTTP.log == 0 then L(body, 3, y, "Запросов пока не было.", "dim") end
  if #HTTP.log > 0 then list.selected = 1 end
end

-- ---------- окно: размеры и запуск
win.onResize = function(_, w, h)
  header.w = w
  body.w, body.h = w, h - 3
  statusBar.y, statusBar.w = h, w
  rerender()
end
win:resize(win.w, win.h)

if not configured() then
  show("setup")
  setStatus("Укажите адрес и публичный ключ Supabase", "info")
  return
end

local okHttp, why = HTTP.check()
if not okHttp then
  S.loadError, S.netOk = why, false
  local cache = loadCache()
  if cache then useCache(cache) end
  show(#S.products > 0 and "catalog" or "net")
  setStatus(tostring(why), "error")
  GUI.alert("Нет доступа к сети", tostring(why) .. "\n\n" .. HTTP.hint(why) .. (cache and "\n\nПоказан сохранённый каталог." or ""))
else
  show("catalog")
  loadCatalog()
  rerender()
end
]=]},
  {"/Applications/Settings.app/Info.lua", [[
return {
  title = "Параметры", short = "Параметры", order = 7,
  desc = "Персонализация, экран, приложения, время и учётная запись.",
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
-- ----------
--  Параметры (в стиле Windows 10): Система, Персонализация, Приложения,
--  Сеть и Интернет, Время и язык, Учётные записи.
-- ----------
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local HTTP = require("HTTP")
local computer, component, unicode = computer, component, unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local W0, H0 = Desktop.screenSize()
local win = ctx.window(min(98, W0), min(32, H0 - Desktop.taskbarHeight()), "Параметры")
win.resizable, win.minW, win.minH = true, min(80, W0), 22
local c = win.content
local s = System.settings

local PAGES = {
  {"system", "Система"}, {"personal", "Персонализация"}, {"apps", "Приложения"},
  {"net", "Сеть и Интернет"}, {"time", "Время и язык"}, {"account", "Учётные записи"},
}
local ALIAS = {display = "system"}
local current = ALIAS[ctx.args.page] or ctx.args.page or "system"
local pane, sidebar
local build = {}

local function save()
  System.saveSettings()
  Desktop.applyTheme()
end

local function title(text, sub)
  pane:add(GUI.label(2, 1, text, "accent"))
  if sub then pane:add(GUI.label(2, 2, sub, "dim")) end
end

-- ---------- образец обоев
local Swatch = GUI.class()
function Swatch:drawSelf(ax, ay)
  GUI.gradient(ax, ay, self.w, self.h - 1, self.wp.c1, self.wp.c2)
  if self.wp.logo then
    Screen.rect(ax + floor(self.w / 2) - 3, ay + 1, 3, 1, 0xFFFFFF, nil, nil, 0.35)
    Screen.rect(ax + floor(self.w / 2) + 1, ay + 1, 3, 1, 0xFFFFFF, nil, nil, 0.3)
    Screen.rect(ax + floor(self.w / 2) - 3, ay + 3, 3, 1, 0xFFFFFF, nil, nil, 0.3)
    Screen.rect(ax + floor(self.w / 2) + 1, ay + 3, 3, 1, 0xFFFFFF, nil, nil, 0.25)
  end
  local on = s.wallpaper == self.index
  Screen.rect(ax, ay + self.h - 1, self.w, 1, C.win, nil, " ")
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

-- ---------- страницы
build.system = function()
  title("Система", "Дисплей, память и сведения о системе")
  local mw, mh = Desktop.maxResolution()
  local cw, ch = Desktop.screenSize()
  pane:add(GUI.label(2, 4, "Разрешение экрана", "text"))
  pane:add(GUI.label(2, 5, string.format("Сейчас %d × %d, максимум %d × %d. Двойной щелчок — применить.", cw, ch, mw, mh), "dim"))
  local options, items = {}, {}
  for _, r in ipairs({{160, 50}, {140, 44}, {120, 40}, {100, 32}, {80, 25}}) do
    if r[1] <= mw and r[2] <= mh then
      options[#options + 1] = r
      items[#items + 1] = string.format("%d × %d%s", r[1], r[2], (r[1] == cw and r[2] == ch) and "     ← сейчас" or "")
    end
  end
  local list = pane:add(GUI.list(2, 7, 36, min(#items, 5), items))
  list.onActivate = function(_, idx)
    local r = options[idx]
    if Desktop.setResolution(r[1], r[2]) then
      s.res = {r[1], r[2]}
      System.saveSettings()
      Desktop.notify(string.format("Разрешение: %d × %d", r[1], r[2]), "Параметры")
    end
    win:resize(min(win.w, Desktop.screenSize()), min(win.h, select(2, Desktop.screenSize()) - Desktop.taskbarHeight()))
    build.refresh()
  end
  pane:add(GUI.label(41, 7, "Меньшее разрешение экономит ОЗУ.", "dim"))
  pane:add(GUI.label(41, 8, "Если памяти мало, система", "dim"))
  pane:add(GUI.label(41, 9, "выберет разрешение сама.", "dim"))

  local used, total = System.memory()
  local fs = System.fs
  local depth = 8
  local ga = component.list("gpu")()
  if ga then
    local gp = component.proxy(ga)
    if gp.getDepth then
      local ok, d = pcall(gp.getDepth)
      if ok and type(d) == "number" then depth = d end
    end
  end
  local colors = depth >= 8 and "256 цветов (Tier 3)" or (depth >= 4 and "16 цветов (Tier 2)" or "2 цвета (Tier 1)")
  pane:add(GUI.label(2, 14, "О системе", "text"))
  local rows = {
    {"Система", System.name .. " " .. System.version .. " (сборка " .. System.build .. ")"},
    {"ОЗУ", System.formatSize(used) .. " занято из " .. System.formatSize(total) .. ", свободно " .. System.formatSize(computer.freeMemory())},
    {"Диск", System.formatSize(fs.spaceUsed()) .. " занято из " .. System.formatSize(fs.spaceTotal())},
    {"Видео", cw .. " × " .. ch .. ", " .. colors},
    {"Эффекты", Desktop.effectsEnabled() and "включены" or "выключены (лёгкий режим)"},
    {"Internet Card", component.list("internet")() and "установлена" or "не найдена"},
    {"Время работы", System.uptimeText()},
  }
  for i, r in ipairs(rows) do
    pane:add(GUI.label(2, 15 + i, r[1], "dim"))
    pane:add(GUI.label(20, 15 + i, GUI.fit(r[2], pane.w - 22), "text"))
  end
  pane:add(GUI.button(2, 23, 22, 1, "Журнал системы", function() Desktop.showLog() end))
  pane:add(GUI.button(26, 23, 26, 1, "Сбросить настройки", function()
    if GUI.confirm("Сброс настроек", "Вернуть оформление, закрепления и остальные настройки по умолчанию?", "Сбросить", "Отмена", true) then
      System.resetSettings()
      s = System.settings
      Desktop.applyTheme()
      build.refresh()
    end
  end, "danger"))
end

local function modeButtons(y, key)
  for i, m in ipairs({{"light", "Светлый"}, {"dark", "Тёмный"}}) do
    local b = GUI.button(2 + (i - 1) * 14, y, 12, 1, m[2], function()
      s[key] = m[1]
      save()
      build.refresh()
    end)
    b.active = s[key] == m[1]
    pane:add(b)
  end
end

build.personal = function()
  title("Персонализация", "Фон, цвета и режимы оформления")
  pane:add(GUI.label(2, 4, "Фон рабочего стола", "text"))
  for i, wp in ipairs(Desktop.wallpapers) do
    local sw = GUI.new(Swatch, 2 + ((i - 1) % 3) * 19, 5 + floor((i - 1) / 3) * 8, 17, 7)
    sw.wp, sw.index = wp, i
    pane:add(sw)
  end
  pane:add(GUI.label(2, 21, "Режим приложений", "text"))
  modeButtons(22, "theme")
  pane:add(GUI.label(32, 21, "Режим панели задач и меню «Пуск»", "text"))
  for i, m in ipairs({{"light", "Светлый"}, {"dark", "Тёмный"}}) do
    local b = GUI.button(32 + (i - 1) * 14, 22, 12, 1, m[2], function()
      s.sysmode = m[1]
      save()
      build.refresh()
    end)
    b.active = s.sysmode == m[1]
    pane:add(b)
  end
  pane:add(GUI.label(2, 24, "Цвет выделения", "text"))
  for i, a in ipairs(GUI.accents) do
    local b = GUI.button(2 + ((i - 1) % 4) * 10, 25 + floor((i - 1) / 4), 9, 1, s.accent == i and "✓" or "", function()
      s.accent = i
      save()
      build.refresh()
    end)
    b.color, b.textColor = a.color, 0xFFFFFF
    pane:add(b)
  end
  pane:add(GUI.label(44, 25, "Выбранный цвет", "dim"))
  pane:add(GUI.label(44, 26, GUI.accents[s.accent] and GUI.accents[s.accent].name or "", "text"))
  pane:add(GUI.label(2, 28, "Эффекты Aero", "text"))
  for i, m in ipairs({{"auto", "Авто"}, {"on", "Вкл"}, {"off", "Выкл"}}) do
    local b = GUI.button(2 + (i - 1) * 11, 29, 10, 1, m[2], function()
      s.effects = m[1]
      save()
      build.refresh()
    end)
    b.active = (s.effects or "auto") == m[1]
    pane:add(b)
  end
  pane:add(GUI.label(36, 29, "Авто: на Tier 2 эффекты выключены", "dim"))
end

build.apps = function()
  title("Приложения и возможности", "Установленные приложения")
  local items = {}
  for _, a in ipairs(Desktop.apps) do
    items[#items + 1] = {app = a, store = System.exists(System.STORE .. "/" .. a.id .. ".app")}
  end
  table.sort(items, function(x, y) return unicode.lower(x.app.title or "") < unicode.lower(y.app.title or "") end)
  local list = pane:add(GUI.list(2, 4, pane.w - 3, pane.h - 7, items))
  list.rowHeight = 2
  list.striped = true
  list.selected = min(1, #items)
  list.render = function(_, it, _, x, y, w, sel, bg)
    local fg1, fg2 = sel and C.accentText or C.text, sel and C.accentText or C.dim
    Screen.rect(x + 1, y, 3, 2, it.app.icon and GUI.iconColor(it.app.icon) or C.accent, nil, " ")
    Screen.text(x + 6, y, fg1, GUI.fit(tostring(it.app.title), w - 30), bg)
    Screen.text(x + 6, y + 1, fg2, it.store and "Из Магазина" or "Встроенное приложение", bg)
    local sz = System.formatSize(System.dirSize(it.app.path))
    Screen.text(x + w - unicode.len(sz) - 2, y, fg2, sz, bg)
  end
  pane:add(GUI.button(2, pane.h - 1, 18, 1, "Открыть Магазин", function() Desktop.launchById("Store") end, "primary"))
  pane:add(GUI.button(22, pane.h - 1, 14, 1, "Удалить", function()
    local it = list.items[list.selected]
    if it and Desktop.uninstall(it.app) then build.refresh() end
  end, "danger"))
end

build.net = function()
  title("Сеть и Интернет", "Подключение через Internet Card")
  local ok, why = HTTP.check()
  pane:add(GUI.label(2, 4, "Internet Card", "dim"))
  pane:add(GUI.label(22, 4, HTTP.available() and "установлена" or "не найдена", HTTP.available() and "success" or "danger"))
  pane:add(GUI.label(2, 5, "HTTP-запросы", "dim"))
  pane:add(GUI.label(22, 5, ok and "разрешены" or GUI.fit(tostring(why), pane.w - 24), ok and "success" or "danger"))
  pane:add(GUI.button(2, 7, 22, 1, "Проверить связь", function()
    local res = HTTP.fetch("https://example.com/", {maxBytes = 4096, truncate = true, timeout = 20})
    if res.ok and (res.code or 200) < 400 then
      GUI.alert("Связь работает", string.format("example.com ответил кодом %s за %.1f с.", tostring(res.code), res.elapsed or 0))
    else
      GUI.alert("Нет связи", tostring(res.error or ("HTTP " .. tostring(res.code))) .. "\n\n" .. HTTP.hint(res.error or ""))
    end
    build.refresh()
  end, "primary"))
  pane:add(GUI.label(2, 9, "Последние запросы", "text"))
  local list = pane:add(GUI.list(2, 10, pane.w - 3, pane.h - 11, HTTP.log))
  list.striped = true
  list.render = function(_, e, _, x, y, w, sel, bg)
    local what = e.method .. " " .. tostring(e.host) .. tostring(e.path)
    if e.err then what = what .. "   ✗ " .. e.err end
    Screen.text(x + 1, y, sel and C.accentText or (e.err and C.danger or C.text), GUI.fit(what, w - 24), bg)
    local tail = string.format("%s  %s  %.1f с", e.code and tostring(e.code) or "—", System.formatSize(e.bytes or 0), e.time or 0)
    Screen.text(x + w - unicode.len(tail) - 1, y, sel and C.accentText or C.dim, tail, bg)
  end
  if #HTTP.log == 0 then pane:add(GUI.label(4, 11, "Запросов пока не было.", "dim")) end
end

build.time = function()
  title("Время и язык", "Часовой пояс")
  pane:add(GUI.label(2, 4, "Сейчас: " .. System.date("%d.%m.%Y  %H:%M:%S"), "text"))
  pane:add(GUI.label(2, 6, "Часовой пояс (UTC):", "dim"))
  local items = {}
  for tz = -12, 14 do items[#items + 1] = string.format("UTC%+d", tz) end
  local list = pane:add(GUI.list(2, 7, 24, pane.h - 8, items))
  list.selected = s.timezone + 13
  list:ensureVisible()
  list.onSelect = function(_, idx)
    s.timezone = idx - 13
    System.saveSettings()
    Desktop.dirty = true
  end
  pane:add(GUI.label(30, 7, "Время берётся с компьютера-хоста.", "dim"))
end

build.account = function()
  title("Учётные записи", "Ваши данные")
  pane:add(GUI.label(2, 4, "Имя пользователя", "dim"))
  local input = pane:add(GUI.input(2, 5, 34, s.username or ""))
  local function saveName()
    if input.text ~= "" then
      s.username = input.text
      save()
      Desktop.notify("Имя сохранено", "Параметры")
    end
  end
  input.onSubmit = saveName
  pane:add(GUI.button(38, 5, 14, 1, "Сохранить", saveName, "primary"))
end

function build.refresh()
  pane:clear()
  s = System.settings
  build[current]()
end

local function layout()
  sidebar.h = c.h
  pane.w, pane.h = c.w - 23, c.h
end

local names = {}
for i, p in ipairs(PAGES) do names[i] = p[2] end
sidebar = c:add(GUI.list(1, 1, 23, c.h, names))
sidebar.bg = "panel"
for i, p in ipairs(PAGES) do
  if p[1] == current then sidebar.selected = i end
end
sidebar.rowHeight = 2
sidebar.onSelect = function(_, idx)
  current = PAGES[idx][1]
  build.refresh()
end
pane = c:add(GUI.panel(24, 1, c.w - 23, c.h, "win"))
win.onResize = function()
  layout()
  build.refresh()
end
layout()
build.refresh()
]]},
  {"/Applications/Store.app/Info.lua", [[
return {
  title = "Магазин", short = "Магазин", order = 0.2,
  desc = "Бесплатные приложения для CubeOS: Paint, Календарь, Погода, игры и другие.",
  icon = {
    pal = {b = 0x1E6FB5, w = 0xFFFFFF, r = 0xE0483C, g = 0x4CA02C, y = 0xFFC90E},
    "..wwww..",
    ".wbwwbw.",
    "bbbbbbbb",
    "bwrgybwb",
    "bwrgybwb",
    "bbbbbbbb",
    "bbbbbbbb",
    "bbbbbbbb",
  },
}
]]},
  {"/Applications/Store.app/Main.lua", [[
-- ----------
--  Магазин CubeOS
--  Витрина бесплатных приложений: главная с рекомендацией, каталоги «Приложения»
--  и «Игры», поиск, страницы приложений, установка / обновление / удаление,
--  «Библиотека» с уже установленным. Пакеты лежат в /System/Store; сторонние
--  приложения ставятся из файла или по ссылке (.cpk).
-- ----------
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local HTTP = require("HTTP")
local JSON = require("JSON")
local computer, unicode = computer, unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local W0, H0 = Desktop.screenSize()
local win = ctx.window(min(112, W0), min(38, H0 - Desktop.taskbarHeight()), "Магазин")
win.resizable, win.minW, win.minH = true, min(84, W0), 18
local c = win.content

local S = {tab = "home", query = "", detail = nil, inst = {}, installing = nil, pct = 0}
local catalog = {}

-- ---------- облачный каталог (игры, добавленные через сайт CubeOS 7)
-- Каталог лежит в базе Supabase (таблица cubeos_apps). Её читают все компьютеры,
-- поэтому игра, опубликованная на сайте, видна в Магазине везде.
-- Список грузится без исходников: код скачивается только при установке.
-- Последний удачный список хранится на диске и показывается, когда сети нет.
local CLOUD_API = "https://syznbtopnyydhlormmjm.supabase.co/rest/v1"
local CLOUD_KEY = "sb_publishable_He0-qm0EgSGBpN8DICrSZw_TC4xGf46" -- публичный ключ, только чтение каталога
local CLOUD_CACHE = "/Users/Store/cloud.lua"
local CLOUD_PAL = {0xCC4444, 0xCC8822, 0x44AA55, 0x3388CC, 0x8866CC, 0xCC66AA, 0x22AAAA, 0xCC6622, 0x5577CC, 0x999922}
local cloudApps = {}

-- Эмодзи на экране OpenComputers нет, поэтому значок — симметричный узор по имени приложения
local function cloudIcon(id)
  local h = 7
  for i = 1, #id do h = (h * 31 + id:byte(i)) % 2147483647 end
  local t = {pal = {x = CLOUD_PAL[h % #CLOUD_PAL + 1], o = 0xFFFFFF}}
  local bits = h
  for r = 1, 8 do
    local half = ""
    for _ = 1, 4 do
      bits = (bits * 1103515245 + 12345) % 2147483648
      half = half .. ((floor(bits / 65536) % 2 == 1) and "o" or "x")
    end
    t[r] = half .. half:reverse()
  end
  return t
end

local function cloudGet(query, maxBytes)
  local data, err = HTTP.request(CLOUD_API .. "/cubeos_apps?" .. query, nil,
    {apikey = CLOUD_KEY, Accept = "application/json"}, "GET",
    {maxBytes = maxBytes, timeout = 12, retries = 0})
  if not data then return nil, tostring(err or "нет ответа") end
  local ok, rows = pcall(JSON.decode, data)
  if not ok or type(rows) ~= "table" then return nil, "некорректный ответ сервера" end
  return rows
end

--- Загрузить список облачных приложений (без кода). При сбое берём сохранённый список.
local function fetchCloud()
  local rows, err = cloudGet("select=id,title,author,description,category,version,size&order=title.asc&limit=200", 96 * 1024)
  if rows then
    local list = {}
    for _, r in ipairs(rows) do
      if type(r) == "table" and type(r.id) == "string" and r.id:match("^[%w_]+$") and #r.id <= 32 then
        list[#list + 1] = {
          id = r.id, title = tostring(r.title or r.id), author = tostring(r.author or ""),
          desc = tostring(r.description or ""), category = tostring(r.category or "Игры"),
          version = tostring(r.version or "1.0"), size = tonumber(r.size) or 0,
        }
      end
    end
    cloudApps, S.cloudErr = list, nil
    System.mkdirs("/Users/Store")
    System.writeFile(CLOUD_CACHE, "return " .. System.serialize(list))
    return true
  end
  if err:find("404", 1, true) or err:find("PGRST", 1, true) then
    S.cloudErr = "облако ещё не настроено"
  else
    S.cloudErr = "нет связи с облаком"
  end
  local cached = System.loadData(CLOUD_CACHE)
  if type(cached) == "table" then cloudApps = cached end
  return false
end

--- Скачать исходник одного приложения
local function fetchCloudCode(id)
  local rows, err = cloudGet("select=code&id=eq." .. id, 256 * 1024)
  if not rows then return nil, "не удалось скачать приложение: " .. err end
  local row = rows[1]
  if type(row) ~= "table" or type(row.code) ~= "string" then return nil, "приложение удалено из облака" end
  return row.code
end

local function reload()
  catalog = System.storeApps()
  local taken = {}
  for _, a in ipairs(catalog) do taken[unicode.lower(a.id)] = true end
  for _, r in ipairs(cloudApps) do
    local key = unicode.lower(tostring(r.id))
    if type(r.id) == "string" and not taken[key] then
      taken[key] = true
      catalog[#catalog + 1] = {
        id = r.id, title = r.title, desc = r.desc, category = r.category, author = r.author,
        version = r.version, size = r.size, icon = cloudIcon(r.id), remote = true, needsNet = true,
      }
    end
  end
  S.inst = {}
  for _, a in ipairs(catalog) do
    local info = System.installedInfo(a.id)
    S.inst[a.id] = info and (info.version or "1.0") or false
  end
end

local function byId(id)
  for _, a in ipairs(catalog) do
    if a.id == id then return a end
  end
end

local function stateOf(app)
  if S.installing == app.id then return "busy" end
  local v = S.inst[app.id]
  if not v then return "get" end
  if System.versionNumber(app.version) > System.versionNumber(v) then return "update" end
  return "open"
end

local LABEL = {get = "Получить", update = "Обновить", open = "Открыть"}

local header = c:add(GUI.panel(1, 1, win.w, 2, "panel"))
local body = c:add(GUI.panel(1, 3, win.w, win.h - 4, "win"))
local statusBar = c:add(GUI.label(1, win.h - 1, "", "dim", "panel", win.w))

local showView, buildHeader

local function setStatus(text) statusBar:setText(" " .. text) end

local function defaultStatus()
  local n, cloud = 0, 0
  for _, a in ipairs(catalog) do
    if a.remote then cloud = cloud + 1 end
  end
  for _, v in pairs(S.inst) do
    if v then n = n + 1 end
  end
  local fs = System.fs
  -- если облако недоступно, говорим об этом вместо свободного места: строка короткая
  local tail = S.cloudErr or ("свободно на диске: " .. System.formatSize(fs.spaceTotal() - fs.spaceUsed()))
  setStatus(string.format("В каталоге: %d (из облака: %d)   ·   установлено: %d   ·   %s", #catalog, cloud, n, tail))
end

-- ---------- установка и удаление
local function afterChange()
  reload()
  Desktop.reloadApps()
  Desktop.refreshIcons(true)
end

local function doInstall(app)
  if S.installing then return end
  local update = S.inst[app.id] ~= false and S.inst[app.id] ~= nil
  S.installing, S.pct = app.id, 0
  setStatus((update and "Обновление " or "Установка ") .. tostring(app.title) .. "…")
  Desktop.render()
  local function progress(i, n)
    S.pct = floor(i / n * 100)
    Desktop.render()
    System.sleep(0.07)
  end
  local ok, err
  if app.remote then
    local code, cerr = fetchCloudCode(app.id)
    if code then
      app.code = code
      ok, err = System.installRemote(app, progress)
      app.code = nil
    else
      ok, err = nil, cerr
    end
  else
    ok, err = System.installApp(app.id, progress)
  end
  S.installing = nil
  if ok then
    afterChange()
    Desktop.notify("«" .. tostring(app.title) .. "» " .. (update and "обновлено" or "установлено") .. ". Найдите его в меню «Пуск».", "Магазин")
  else
    GUI.alert("Не удалось установить", tostring(err))
  end
  showView()
end

local function doOpen(app)
  Desktop.launchById(app.id)
end

local function act(app)
  local st = stateOf(app)
  if st == "get" or st == "update" then doInstall(app) elseif st == "open" then doOpen(app) end
end

local function doUninstall(app)
  local info = {id = app.id, title = app.title, path = "/Applications/" .. app.id .. ".app"}
  if Desktop.uninstall(info) then
    afterChange()
    showView()
  end
end

-- ---------- витрина
local Cards = GUI.class()
local CARD_W, CARD_H = 24, 11

function Cards:info()
  local cols = max(1, floor((self.w - 2) / (CARD_W + 1)))
  local left = max(1, floor((self.w - 1 - (cols * (CARD_W + 1) - 1)) / 2) + 1)
  local y, info = 0, {cols = cols, left = left}
  if self.banner then info.bannerY, y = y, y + 10 end
  if self.heading then info.headY, y = y, y + 2 end
  info.cardsY = y
  info.total = y + ceil(#self.apps / cols) * (CARD_H + 1)
  return info
end

local function buttonLook(app)
  local st = stateOf(app)
  if st == "busy" then return "Установка " .. S.pct .. "%", C.panel, C.dim end
  if st == "open" then return LABEL.open, C.button, C.buttonText end
  return LABEL[st], C.accent, C.accentText
end

function Cards:drawBanner(x, y, w, app)
  local dom = app.icon and GUI.iconColor(app.icon) or C.accent
  GUI.gradient(x, y, w, 9, Screen.blend(0x000000, dom, 0.6), Screen.blend(0x000000, dom, 0.3))
  if app.icon then GUI.drawIconBig(x + 3, y + 1, app.icon) end
  local tx = x + 23
  Screen.text(tx, y + 1, 0xD8D8D8, "РЕКОМЕНДУЕМ")
  Screen.text(tx, y + 2, 0xFFFFFF, GUI.fit(tostring(app.title), w - 26))
  local lines = GUI.wrap(tostring(app.desc or ""), max(20, w - 28))
  for i = 1, min(3, #lines) do
    local line = lines[i]
    if i == 3 and #lines > 3 then line = GUI.fit(line .. "…", max(20, w - 28)) end
    Screen.text(tx, y + 3 + i, 0xE6E6E6, line)
  end
  local label, _, _ = buttonLook(app)
  local bw = max(14, unicode.len(label) + 4)
  Screen.rect(tx, y + 7, bw, 1, 0xFFFFFF, nil, " ")
  Screen.text(tx + floor((bw - unicode.len(label)) / 2), y + 7, 0x111111, label, 0xFFFFFF)
  self.hits[#self.hits + 1] = {x1 = x, x2 = x + w - 1, y1 = y, y2 = y + 8, app = app, kind = "detail"}
  self.hits[#self.hits + 1] = {x1 = tx, x2 = tx + bw - 1, y1 = y + 7, y2 = y + 7, app = app, kind = "btn"}
end

function Cards:drawCard(x, y, app)
  Screen.rect(x, y, CARD_W, CARD_H, C.winAlt, nil, " ")
  local dom = app.icon and GUI.iconColor(app.icon) or C.accent
  Screen.rect(x + 6, y + 1, 12, 5, Screen.blend(0x000000, dom, 0.42), nil, " ")
  if app.icon then GUI.drawIcon(x + 8, y + 1, app.icon) end
  local title = GUI.fit(tostring(app.title), CARD_W - 2)
  Screen.text(x + floor((CARD_W - unicode.len(title)) / 2), y + 7, C.text, title, C.winAlt)
  local cat = GUI.fit(tostring(app.category or "") .. (app.remote and " · облако" or ""), CARD_W - 2)
  Screen.text(x + floor((CARD_W - unicode.len(cat)) / 2), y + 8, C.dim, cat, C.winAlt)
  local label, bg, fg = buttonLook(app)
  Screen.rect(x + 3, y + 9, CARD_W - 6, 1, bg, nil, " ")
  Screen.text(x + 3 + floor((CARD_W - 6 - unicode.len(label)) / 2), y + 9, fg, label, bg)
  self.hits[#self.hits + 1] = {x1 = x, x2 = x + CARD_W - 1, y1 = y, y2 = y + CARD_H - 1, app = app, kind = "detail"}
  self.hits[#self.hits + 1] = {x1 = x + 3, x2 = x + CARD_W - 4, y1 = y + 9, y2 = y + 9, app = app, kind = "btn"}
end

function Cards:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, C.win, nil, " ")
  Screen.pushClip(ax, ay, self.w, self.h)
  local info = self:info()
  self.hits = {}
  self.scroll = max(0, min(self.scroll, max(0, info.total - self.h)))
  local sy = ay - self.scroll
  if info.bannerY then self:drawBanner(ax + 1, sy + info.bannerY, self.w - 2, self.banner) end
  if info.headY then Screen.text(ax + 1, sy + info.headY, C.text, self.heading, C.win) end
  if #self.apps == 0 then
    Screen.text(ax + 2, sy + info.cardsY, C.dim, self.empty or "Ничего не найдено", C.win)
  end
  for i, app in ipairs(self.apps) do
    local col, row = (i - 1) % info.cols, floor((i - 1) / info.cols)
    local x, y = ax + info.left - 1 + col * (CARD_W + 1), sy + info.cardsY + row * (CARD_H + 1)
    if y + CARD_H > ay and y < ay + self.h then self:drawCard(x, y, app) end
  end
  Screen.popClip()
  if info.total > self.h then
    local barH = max(1, floor(self.h * self.h / info.total))
    local barY = floor((self.h - barH) * self.scroll / max(1, info.total - self.h))
    Screen.rect(ax + self.w - 1, ay, 1, self.h, C.panel, nil, " ")
    Screen.rect(ax + self.w - 1, ay + barY, 1, barH, C.dim, nil, " ")
  end
end

function Cards:onEvent(e)
  if e.type == "scroll" then
    self.scroll = max(0, self.scroll - e.dir * 3)
    return true
  elseif e.type == "touch" and e.button == 0 then
    self:focus()
    for i = #(self.hits or {}), 1, -1 do
      local h = self.hits[i]
      if e.x >= h.x1 and e.x <= h.x2 and e.y >= h.y1 and e.y <= h.y2 and e.y >= self.parent.y + 2 then
        if h.kind == "btn" then
          act(h.app)
        else
          S.detail = h.app
          showView()
        end
        return true
      end
    end
    return true
  end
  return false
end

function Cards:onKey(e)
  local code = e.code
  if code == 200 then self.scroll = max(0, self.scroll - 2)
  elseif code == 208 then self.scroll = self.scroll + 2
  elseif code == 201 then self.scroll = max(0, self.scroll - self.h + 1)
  elseif code == 209 then self.scroll = self.scroll + self.h - 1
  elseif code == 199 then self.scroll = 0
  else return false end
  return true
end

local function newCards(apps, opts)
  local w = GUI.new(Cards, 1, 1, body.w, body.h)
  w.apps, w.scroll, w.hits = apps, 0, {}
  w.focusable = true
  for k, v in pairs(opts or {}) do w[k] = v end
  return w
end

-- ---------- страница приложения
local IconTile = GUI.class()
function IconTile:drawSelf(ax, ay)
  local dom = self.app.icon and GUI.iconColor(self.app.icon) or C.accent
  Screen.rect(ax, ay, self.w, self.h, Screen.blend(0x000000, dom, 0.42), nil, " ")
  if self.app.icon then GUI.drawIconBig(ax + 2, ay + 1, self.app.icon) end
end

local function showDetail(app)
  body:clear()
  local bw = body.w
  local back = GUI.button(2, 1, 12, 1, "← Назад", function() S.detail = nil showView() end)
  back.color, back.textColor = "panel", "text"
  body:add(back)
  local tile = GUI.new(IconTile, 3, 3, 20, 10)
  tile.app = app
  body:add(tile)
  body:add(GUI.label(26, 3, tostring(app.title), "accent"))
  body:add(GUI.label(26, 4, tostring(app.author or "CubeOS") .. "  ·  " .. tostring(app.category or "Приложение") .. (app.remote and "  ·  из облака" or "") .. "  ·  версия " .. tostring(app.version or "1.0"), "dim"))
  body:add(GUI.label(26, 5, "Бесплатно  ·  " .. System.formatSize(app.size or 0) .. (app.needsNet and "  ·  нужен интернет" or ""), "dim"))

  local st = stateOf(app)
  if st == "busy" then
    body:add(GUI.label(26, 7, "Установка… " .. S.pct .. "%", "text"))
    body:add(GUI.progress(26, 8, 34, S.pct / 100))
  else
    local label = LABEL[st]
    body:add(GUI.button(26, 7, max(14, unicode.len(label) + 4), 1, label, function() act(app) end, st ~= "open" and "primary" or nil))
    if S.inst[app.id] then
      body:add(GUI.button(26 + max(14, unicode.len(label) + 4) + 2, 7, 12, 1, "Удалить", function() doUninstall(app) end, "danger"))
    end
    if st == "update" then body:add(GUI.label(26, 9, "Установлена версия " .. tostring(S.inst[app.id]) .. ", доступна " .. tostring(app.version), "warning")) end
    if st == "open" then body:add(GUI.label(26, 9, "Установлено. Приложение есть в меню «Пуск».", "success")) end
  end

  body:add(GUI.label(3, 14, "О приложении", "text"))
  body:add(GUI.textView(3, 15, min(bw - 6, 86), max(3, body.h - 17), tostring(app.desc or "")))
end

-- ---------- библиотека
local function libraryView()
  body:clear()
  local items = {}
  for _, a in ipairs(Desktop.apps) do
    local store = byId(a.id)
    items[#items + 1] = {app = a, store = store}
  end
  table.sort(items, function(x, y) return unicode.lower(x.app.title or "") < unicode.lower(y.app.title or "") end)
  local updates = 0
  for _, it in ipairs(items) do
    if it.store and stateOf(it.store) == "update" then updates = updates + 1 end
  end
  body:add(GUI.label(3, 1, "Установленные приложения (" .. #items .. ")", "text"))
  if updates > 0 then
    body:add(GUI.button(body.w - 26, 1, 24, 1, "Обновить всё (" .. updates .. ")", function()
      for _, it in ipairs(items) do
        if it.store and stateOf(it.store) == "update" then doInstall(it.store) end
      end
    end, "primary"))
  end
  local list = body:add(GUI.list(1, 3, body.w, body.h - 4, items))
  list.rowHeight = 2
  list.striped = true
  list.selected = 1
  list.render = function(_, it, _, x, y, w, sel, bg)
    local fg1, fg2 = sel and C.accentText or C.text, sel and C.accentText or C.dim
    local col = it.app.icon and GUI.iconColor(it.app.icon) or C.accent
    Screen.rect(x + 1, y, 4, 2, col, nil, " ")
    Screen.text(x + 7, y, fg1, GUI.fit(tostring(it.app.title), 30), bg)
    local kind = it.store and ("Из Магазина · версия " .. tostring(S.inst[it.app.id] or "?")) or "Встроенное приложение"
    local st = it.store and stateOf(it.store)
    if st == "update" then kind = kind .. " · доступно обновление" end
    Screen.text(x + 7, y + 1, fg2, GUI.fit(kind, w - 30), bg)
    Screen.text(x + w - 30, y, fg2, GUI.fit(tostring(it.app.desc or ""), 29), bg)
  end
  local function sel() return list.items[list.selected] end
  body:add(GUI.button(2, body.h, 14, 1, "Открыть", function()
    local it = sel()
    if it then Desktop.launchOrFocus(it.app) end
  end, "primary"))
  body:add(GUI.button(18, body.h, 14, 1, "Удалить", function()
    local it = sel()
    if not it then return end
    if it.store then doUninstall(it.store) else GUI.alert("Нельзя удалить", "«" .. tostring(it.app.title) .. "» — встроенное приложение CubeOS.") end
  end, "danger"))
  list.onActivate = function(_, idx) Desktop.launchOrFocus(list.items[idx].app) end
  list:focus()
end

-- ---------- главный экран, каталоги, поиск
local function filtered()
  local out, q = {}, unicode.lower(S.query)
  for _, a in ipairs(catalog) do
    local hay = unicode.lower(tostring(a.title) .. " " .. tostring(a.desc or "") .. " " .. tostring(a.category or ""))
    local okTab
    if S.tab == "home" or S.tab == "library" then okTab = true
    elseif S.tab == "cloud" then okTab = a.remote == true
    else okTab = (S.tab == "games") == (a.category == "Игры") end
    if q ~= "" then okTab = true end
    if okTab and (q == "" or hay:find(q, 1, true)) then out[#out + 1] = a end
  end
  return out
end

showView = function()
  buildHeader()
  if S.detail then
    local fresh = byId(S.detail.id)
    S.detail = fresh or S.detail
    showDetail(S.detail)
  elseif S.query ~= "" then
    body:clear()
    local w = newCards(filtered(), {heading = "Результаты поиска: «" .. S.query .. "»"})
    body:add(w)
    w:focus()
  elseif S.tab == "library" then
    libraryView()
  else
    body:clear()
    local opts = {}
    if S.tab == "home" then
      opts.banner = byId("Paint") or catalog[1]
      opts.heading = "Все приложения"
    elseif S.tab == "games" then
      opts.heading = "Игры"
    elseif S.tab == "cloud" then
      opts.heading = "Облако — приложения, добавленные через сайт CubeOS 7"
      opts.empty = S.cloudErr and ("Список недоступен: " .. S.cloudErr .. ".")
        or "В облаке пока пусто. Добавьте игру на сайте CubeOS 7."
    else
      opts.heading = "Приложения"
    end
    local w = newCards(filtered(), opts)
    body:add(w)
    w:focus()
  end
  defaultStatus()
end

-- ---------- установка пакетов .cpk
local function installPackageFrom(src)
  src = tostring(src or ""):match("^%s*(.-)%s*$")
  if src == "" then return end
  local data
  if src:match("^https?://") then
    setStatus("Загрузка пакета…")
    Desktop.render()
    local res = HTTP.fetch(src, {maxBytes = 450 * 1024, timeout = 40})
    if not res.ok or (res.code and res.code >= 400) then
      GUI.alert("Не удалось скачать пакет", tostring(res.error or ("HTTP " .. tostring(res.code))) .. "\n\n" .. HTTP.hint(res.error or ""))
      defaultStatus()
      return
    end
    data = res.body
  else
    data = System.readFile(src)
    if not data then GUI.alert("Файл не найден", src) return end
  end
  if not GUI.confirm("Установка пакета",
    "Приложение из пакета получит полный доступ к файлам этого компьютера. Устанавливайте пакеты только из источников, которым вы доверяете.\n\nПродолжить?",
    "Установить", "Отмена", true) then
    defaultStatus()
    return
  end
  local id, err = System.installPackage(data)
  if id then
    afterChange()
    Desktop.notify("Пакет «" .. id .. "» установлен.", "Магазин")
    showView()
  else
    GUI.alert("Пакет не установлен", tostring(err))
  end
end

local function createPackage()
  local names, apps = {}, {}
  for _, a in ipairs(Desktop.apps) do
    names[#names + 1] = tostring(a.title) .. "  (" .. a.id .. ")"
    apps[#apps + 1] = a
  end
  local idx = GUI.select("Создать пакет из приложения", names)
  if not idx then return end
  local app = apps[idx]
  local data, err = System.packApp(app.path)
  if not data then GUI.alert("Ошибка", tostring(err)) return end
  local path = "/Users/Documents/" .. app.id .. ".cpk"
  local ok, e2 = System.writeFile(path, data)
  if ok then
    Desktop.notify("Пакет сохранён: " .. path .. " (" .. System.formatSize(#data) .. ")", "Магазин")
  else
    GUI.alert("Не удалось сохранить", tostring(e2))
  end
end

-- ---------- шапка
buildHeader = function()
  header:clear()
  header.w = c.w
  local tabs = {{"home", "Главная"}, {"apps", "Приложения"}, {"games", "Игры"}, {"cloud", "Облако"}, {"library", "Библиотека"}}
  local x = 2
  for _, t in ipairs(tabs) do
    local w = unicode.len(t[2]) + 4
    local b = GUI.button(x, 1, w, 1, t[2], function()
      S.tab, S.detail, S.query = t[1], nil, ""
      showView()
    end)
    b.active = S.tab == t[1] and not S.detail
    if not b.active then b.color, b.textColor = "panel", "text" end
    header:add(b)
    x = x + w + 1
  end
  local sw = max(16, min(26, c.w - x - 8))
  local input = header:add(GUI.input(c.w - sw - 5, 1, sw, S.query, "Поиск приложений"))
  input.onChange = function(_, t)
    S.query, S.detail = t, nil
    showView()
    input:focus()
  end
  local menu = GUI.button(c.w - 3, 1, 3, 1, " ⋯ ", function()
    GUI.menu(c.w - 40, 3, {
      {text = "Установить пакет из файла или ссылки…", action = function()
        installPackageFrom(GUI.prompt("Установить пакет", "Путь к .cpk-файлу или ссылка (https://…):", "/Users/Documents/"))
      end},
      {text = "Создать пакет (.cpk) из приложения…", action = createPackage},
      {separator = true},
      {text = "Обновить каталог", action = function()
        setStatus("Загрузка облачного каталога…")
        Desktop.render()
        fetchCloud()
        reload()
        showView()
      end},
    })
  end)
  menu.color, menu.textColor = "panel", "text"
  header:add(menu)
end

local function layout()
  local w, h = c.w, c.h
  header.w = w
  body.y, body.w, body.h = 3, w, h - 3
  statusBar.y, statusBar.w = h, w
end

win.onResize = function()
  layout()
  showView()
end

reload()
layout()
if ctx.args.app and byId(ctx.args.app) then S.detail = byId(ctx.args.app) end
showView()
-- Облачный список подгружаем, когда окно уже на экране
setStatus("Загрузка облачного каталога…")
Desktop.render()
fetchCloud()
reload()
showView()
if ctx.args.package then installPackageFrom(ctx.args.package) end
]]},
  {"/Applications/Terminal.app/Info.lua", [[
return {
  title = "Командная строка", short = "Команды", order = 3,
  desc = "Командная строка: ls, cd, cat, wget, curl, lua и другие команды.",
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
local HTTP = require("HTTP")
local Screen = require("Screen")
local computer, unicode = computer, unicode
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local win = ctx.window(84, 26, "Командная строка")
win.resizable, win.minW, win.minH = true, 40, 8
local content = win.content

local BG, FG = 0x0C0C0C, 0xCCCCCC
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
  return "C:" .. (self.cwd == "/" and "\\" or self.cwd:gsub("/", "\\")) .. ">"
end

function term:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, BG, nil, " ")
  local rows = self.h - 1
  local total = #self.lines
  local last = total - self.scroll
  local shown = min(rows, last)
  for r = 1, shown do
    local line = self.lines[last - shown + r]
    if line then Screen.text(ax + 1, ay + r - 1, line[2] or FG, line[1], BG) end
  end
  local y = ay + (self.scroll == 0 and min(total, rows) or rows)
  local p = self:prompt()
  Screen.text(ax + 1, y, FG, p, BG)
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

-- ---------- команды
local cmds = {}

local function path(arg)
  arg = tostring(arg or "."):gsub("\\", "/"):gsub("^%a:", "")
  if arg == "" then arg = "/" end
  return System.join(term.cwd, arg)
end

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
  say("  wget <url> [файл]   скачать файл       curl <url>   показать начало страницы")
  say("  open Browser <url>  открыть сайт в браузере")
  say("  apps  mem  df  date  uptime  ver  neofetch  whoami")
  say("  pack <App.app>      создать пакет .cpk    dir cls type copy move del md — как в Windows")
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
  for _, protected in ipairs({"/", "/init.lua", "/Libraries", "/System", "/Applications"}) do
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
  Desktop.launchById(a[1], a[2] and {url = a[2]} or nil)
end

cmds.wget = function(a)
  local url = a[1]
  if not url then say("wget: укажите адрес, например: wget https://example.com/ page.html", RED) return end
  if not url:match("^%a[%w+.-]*://") then url = "https://" .. url end
  local name = a[2] or HTTP.urldecode(((HTTP.parseUrl(url) or {path = ""}).path:match("([^/]+)/?$")) or "index.html")
  local target = path(name)
  if System.isDir(target) then target = target .. "/index.html" end
  local fh = System.fs.open(target, "w")
  if not fh then say("wget: не удалось создать " .. target, RED) return end
  local total, failed = 0, nil
  say("Скачиваю " .. url .. " … (Esc — отмена)", GRAY)
  Desktop.render()
  local res = HTTP.fetch(url, {timeout = 60, idleTimeout = 20, sink = function(chunk)
    if not failed and not System.fs.write(fh, chunk) then failed = "диск переполнен" end
    total = total + #chunk
  end})
  System.fs.close(fh)
  if not res.ok or failed or (res.code and res.code >= 400) then
    System.remove(target)
    say("wget: " .. tostring(failed or res.error or ("HTTP " .. tostring(res.code))), RED)
    say(HTTP.hint(failed or res.error or ""), GRAY)
  else
    say("Готово: " .. target .. " (" .. System.formatSize(total) .. ")", GREEN)
  end
end

cmds.curl = function(a)
  local url = a[1]
  if not url then say("curl: укажите адрес", RED) return end
  if not url:match("^%a[%w+.-]*://") then url = "https://" .. url end
  Desktop.render()
  local res = HTTP.fetch(url, {maxBytes = 6000, truncate = true, timeout = 30})
  if not res.ok then
    say("curl: " .. tostring(res.error), RED)
    say(HTTP.hint(res.error), GRAY)
    return
  end
  say("HTTP " .. tostring(res.code) .. "  " .. tostring(res.headers["content-type"] or ""), YELLOW)
  say(res.body or "")
  if res.truncated then say("… (показано первые 6000 байт)", GRAY) end
end

cmds.neofetch = function()
  local used, total = System.memory()
  local w, h = Desktop.screenSize()
  local rows = {
    {"   ▄▄▄▄▄▄   ", GREEN, System.settings.username .. "@cubeos"},
    {" ▄██████████▄", GREEN, "─────────────────"},
    {" ████▀▀▀▀████", GREEN, "ОС:      CubeOS " .. System.version},
    {" ██▀▀    ▀▀██", 0x15803D, "Ядро:    Lua " .. (_VERSION or "5.3"):gsub("Lua ", "")},
    {" ██  ▄▄▄▄  ██", 0x15803D, "ОЗУ:     " .. System.formatSize(used) .. " / " .. System.formatSize(total)},
    {" ██▄▄████▄▄██", 0x15803D, "Экран:   " .. w .. "×" .. h},
    {"   ▀▀▀▀▀▀▀▀   ", 0x15803D, "Время:   " .. System.uptimeText()},
  }
  for _, r in ipairs(rows) do say(r[1] .. "  " .. r[3], r[2]) end
end

cmds.reboot = function() computer.shutdown(true) end
cmds.shutdown = function() computer.shutdown() end
cmds.exit = function() win:close() end

cmds.pack = function(a)
  if not a[1] then say("pack: укажите папку приложения, например: pack /Applications/Todo.app", RED) return end
  local data, err = System.packApp(path(a[1]))
  if not data then say("pack: " .. tostring(err), RED) return end
  local out = "/Users/Documents/" .. System.basename(path(a[1])):gsub("%.app$", "") .. ".cpk"
  System.writeFile(out, data)
  say("Пакет создан: " .. out .. " (" .. System.formatSize(#data) .. ")", GREEN)
end

-- привычные команды Windows
cmds.dir, cmds.cls, cmds.type, cmds.del, cmds.copy, cmds.move, cmds.md = cmds.ls, cmds.clear, cmds.cat, cmds.rm, cmds.cp, cmds.mv, cmds.mkdir
cmds.rd, cmds.cd, cmds.tasklist, cmds.systeminfo = cmds.rm, cmds.cd, cmds.apps, cmds.neofetch

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

term:print("CubeOS [версия " .. System.version .. "]", FG)
term:print("Введите help, чтобы увидеть список команд (dir, cd, type, copy, del, wget …).", FG)
term:print("")
]]},
  {"/Libraries/GUI.lua", [[
-- ----------
--  CubeOS :: GUI  —  Windows 7 «Aero»
--  Стеклянные синие заголовки, глянцевые кнопки с фаской,
--  белые поля с утопленной рамкой, меню с полосой значков,
--  зелёный прогресс и полоса прокрутки Aero.
--
--  Экран OpenComputers: ячейка 8×16, полублок «▀» даёт два
--  «пикселя» по вертикали — на этом и построен весь глянец.
-- ----------
local computer, unicode = computer, unicode
local Screen = require("Screen")
local floor, max, min = math.floor, math.max, math.min

local GUI = {}

-- ---------- палитра Aero
GUI.themes = {
  light = {
    win         = 0xF0F0F0, -- фон окна Windows 7
    winAlt      = 0xFFFFFF,
    panel       = 0xE9EDF2, -- голубовато-серая панель
    text        = 0x1A1A1A,
    dim         = 0x6E7479,
    border      = 0xA0A8B0,
    title       = 0x2A6FB5, -- стекло заголовка (низ)
    titleTop    = 0x6FB2E8, -- блик заголовка (верх)
    titleText   = 0xFFFFFF,
    titleDim    = 0xC6D8EA,
    frame       = 0x4E93D6, -- стеклянная рамка окна
    frameDim    = 0x8FA9BF, -- рамка неактивного окна
    button      = 0xEDEDED,
    buttonTop   = 0xFDFDFD,
    buttonText  = 0x1A1A1A,
    buttonEdge  = 0x8E9299,
    input       = 0xFFFFFF,
    inputText   = 0x1A1A1A,
    inputBorder = 0x7A8794,
    danger      = 0xC0392B,
    success     = 0x2E8B22,
    warning     = 0xC98A00,
    menu        = 0xF5F6F7,
    menuText    = 0x1A1A1A,
    menuDim     = 0x8A9099,
    menuSel     = 0x3C8CD8,
    menuSelTop  = 0x9CCBF0,
    menuGutter  = 0xE4E9EF, -- полоса значков слева
    menuBorder  = 0x9AA3AC,
    menubar     = 0xF0F0F0,
    menubarText = 0x1A1A1A,
    scrollTrack = 0xF1F1F1,
    scrollThumb = 0xCDCDCD,
  },
  dark = {
    win         = 0x2B2F35,
    winAlt      = 0x33383F,
    panel       = 0x24282D,
    text        = 0xF2F5F8,
    dim         = 0x9AA3AC,
    border      = 0x4A525B,
    title       = 0x1B4A80,
    titleTop    = 0x3E82C4,
    titleText   = 0xFFFFFF,
    titleDim    = 0xA8BDD2,
    frame       = 0x2E6BB0,
    frameDim    = 0x475562,
    button      = 0x3A4048,
    buttonTop   = 0x4C545E,
    buttonText  = 0xF2F5F8,
    buttonEdge  = 0x5B646E,
    input       = 0x1E2226,
    inputText   = 0xF2F5F8,
    inputBorder = 0x5B646E,
    danger      = 0xE06A5C,
    success     = 0x6CCB5F,
    warning     = 0xE8B33C,
    menu        = 0x2F343A,
    menuText    = 0xF2F5F8,
    menuDim     = 0x8A9099,
    menuSel     = 0x2E6BB0,
    menuSelTop  = 0x4E93D6,
    menuGutter  = 0x272B31,
    menuBorder  = 0x4A525B,
    menubar     = 0x2B2F35,
    menubarText = 0xF2F5F8,
    scrollTrack = 0x272B31,
    scrollThumb = 0x59626C,
  },
}

-- Панель задач и «Пуск»: стекло Aero (тёмное по умолчанию, как в Windows 7)
GUI.sysThemes = {
  aero = {
    taskbar      = 0x10365C, taskbarTop  = 0x3E82C4, taskbarEdge = 0x7FB6E6,
    taskbarText  = 0xFFFFFF, taskbarDim  = 0xBFD6EC,
    taskbarHover = 0x2C6BA8, taskbarActive = 0x1C538C,
    start        = 0xF2F5F9, startRail   = 0xDCE6F2,
    startText    = 0x1A2733, startDim    = 0x5C6B7A,
    startHover   = 0xD6E8FA, startSel    = 0x3C8CD8,
    startHead    = 0x1B4A80, startHeadTop = 0x3E82C4,
    orb1         = 0x7FD2FF, orb2 = 0x1668B8, orbEdge = 0x0B3B6B,
    toast        = 0xFFF8DC, toastText = 0x2A2A1A, toastDim = 0x7A7050,
    toastEdge    = 0xC8B96A,
  },
  light = {
    taskbar      = 0xC9DCEE, taskbarTop  = 0xF2F8FD, taskbarEdge = 0xFFFFFF,
    taskbarText  = 0x14304A, taskbarDim  = 0x41637F,
    taskbarHover = 0xDCEBF8, taskbarActive = 0xAFCEE8,
    start        = 0xF7FAFD, startRail   = 0xE4EDF6,
    startText    = 0x14304A, startDim    = 0x5C6B7A,
    startHover   = 0xDCEBF8, startSel    = 0x3C8CD8,
    startHead    = 0x2A6FB5, startHeadTop = 0x6FB2E8,
    orb1         = 0x7FD2FF, orb2 = 0x1668B8, orbEdge = 0x0B3B6B,
    toast        = 0xFFF8DC, toastText = 0x2A2A1A, toastDim = 0x7A7050,
    toastEdge    = 0xC8B96A,
  },
  dark = {
    taskbar      = 0x0A1E33, taskbarTop  = 0x24567F, taskbarEdge = 0x4E93D6,
    taskbarText  = 0xEAF2FA, taskbarDim  = 0x9DB6CD,
    taskbarHover = 0x1C4570, taskbarActive = 0x123659,
    start        = 0x232830, startRail   = 0x1B1F26,
    startText    = 0xEAF2FA, startDim    = 0x9AA3AC,
    startHover   = 0x2E3540, startSel  = 0x2E6BB0,
    startHead    = 0x14395F, startHeadTop = 0x2A6FB5,
    orb1         = 0x7FD2FF, orb2 = 0x1668B8, orbEdge = 0x081F35,
    toast        = 0x2B2F35, toastText = 0xF2F5F8, toastDim = 0x9AA3AC,
    toastEdge    = 0x4E93D6,
  },
}

-- Цвета выделения Windows 7 (по умолчанию — «Небо»)
GUI.accents = {
  {name = "Небо",       color = 0x3C8CD8},
  {name = "Море",       color = 0x1B7FA8},
  {name = "Лист",       color = 0x4CA02C},
  {name = "Закат",      color = 0xE08A1E},
  {name = "Рубин",      color = 0xC0392B},
  {name = "Орхидея",    color = 0xB0479B},
  {name = "Аметист",    color = 0x7A5BC0},
  {name = "Графит",     color = 0x5C6670},
}

GUI.color = {}
local C = GUI.color

function GUI.setTheme(name, accent, sys)
  local t = GUI.themes[name] or GUI.themes.light
  for k, v in pairs(t) do C[k] = v end
  local st = GUI.sysThemes[sys or "aero"] or GUI.sysThemes.aero
  for k, v in pairs(st) do C[k] = v end
  local a = GUI.accents[accent or 1] or GUI.accents[1]
  C.accent = a.color
  local r, g, b = floor(a.color / 65536) % 256, floor(a.color / 256) % 256, a.color % 256
  C.accentText = (0.299 * r + 0.587 * g + 0.114 * b) > 170 and 0x10202C or 0xFFFFFF
  C.accentLight = Screen.blend(0xFFFFFF, a.color, 0.45)
  C.accentDark = Screen.blend(0x000000, a.color, 0.62)
  C.selectTop = Screen.blend(0xFFFFFF, a.color, 0.55)
  C.selectEdge = Screen.blend(0x000000, a.color, 0.75)
end
GUI.setTheme("light", 1, "aero")

local function rc(v, default)
  if type(v) == "string" then return C[v] or default end
  return v or default
end
GUI.rc = rc

-- ---------- утилиты
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

--- Вертикальный градиент полублоками (два «пикселя» на ячейку).
--- Между соседними полосами ставится шахматное дизерирование: палитра
--- OpenComputers всего 256 цветов, и без него видны грубые ступени.
function GUI.gradient(x, y, w, h, c1, c2)
  local den = max(1, h * 2 - 1)
  local prevBottom
  for r = 1, h do
    local top = Screen.blend(c2, c1, (r * 2 - 2) / den)
    local bottom = Screen.blend(c2, c1, (r * 2 - 1) / den)
    Screen.rect(x, y + r - 1, w, 1, bottom, top, "▀")
    if prevBottom then
      -- растворяем стык предыдущей полосы в верхней половине текущей
      for cx = x + (r % 2), x + w - 1, 2 do
        Screen.set(cx, y + r - 1, bottom, prevBottom, "▀")
      end
    end
    prevBottom = bottom
  end
end

--- Глянцевая полоса высотой 1: светлый верх, тёмный низ — основа стиля Aero
function GUI.gloss(x, y, w, top, bottom)
  Screen.rect(x, y, w, 1, bottom, top, "▀")
end

--- Панель Aero с фаской: блик сверху, тень снизу, боковые грани
function GUI.bevel(x, y, w, h, topColor, bottomColor, edge)
  if w < 1 or h < 1 then return end
  if h == 1 then
    GUI.gloss(x, y, w, topColor, bottomColor)
    return
  end
  GUI.gloss(x, y, w, topColor, Screen.blend(bottomColor, topColor, 0.55))
  if h > 2 then Screen.rect(x, y + 1, w, h - 2, bottomColor, nil, " ") end
  GUI.gloss(x, y + h - 1, w, Screen.blend(topColor, bottomColor, 0.35), Screen.blend(0x000000, bottomColor, 0.16))
  if edge then
    for r = 0, h - 1 do
      Screen.set(x, y + r, nil, edge, "▏")
      Screen.set(x + w - 1, y + r, nil, edge, "▕")
    end
  end
end

-- ---------- иконки 8×8
local basePal = {
  r = 0xD64541, g = 0x4CA02C, b = 0x3C8CD8, y = 0xF0B429, w = 0xFFFFFF, k = 0x1B2530,
  a = 0x9AA6B2, d = 0x51606E, o = 0xE08A1E, p = 0x9B7BD4, c = 0x37B6C9, n = 0x8B5E3C,
  l = 0xE6EDF4, t = 0x2FB5A6, m = 0xD96BA8, s = 0x4E6FD0, e = 0x2B2F35, u = 0x1B4A80,
}

local function palette(icon)
  if not icon.pal then icon.pal = {} end
  if not getmetatable(icon.pal) then setmetatable(icon.pal, {__index = basePal}) end
  return icon.pal
end

function GUI.drawIcon(x, y, icon)
  local pal = palette(icon)
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

function GUI.drawIconBig(x, y, icon)
  local pal = palette(icon)
  for r = 1, 8 do
    local row = icon[r] or ""
    for c = 1, 8 do
      local col = pal[row:sub(c, c)]
      if col then Screen.rect(x + (c - 1) * 2, y + r - 1, 2, 1, col, nil, " ") end
    end
  end
end

function GUI.drawIconSmall(x, y, icon)
  local pal = palette(icon)
  local function pick(pr, pc)
    for dr = 0, 1 do
      local row = icon[pr + dr] or ""
      for dc = 0, 1 do
        local col = pal[row:sub(pc + dc, pc + dc)]
        if col then return col end
      end
    end
  end
  for r = 1, 2 do
    for c = 1, 4 do
      local tc, bc = pick(r * 4 - 3, c * 2 - 1), pick(r * 4 - 1, c * 2 - 1)
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

function GUI.iconColor(icon)
  if not icon then return C.accent end
  if icon._dom then return icon._dom end
  local pal, count = palette(icon), {}
  for r = 1, 8 do
    local row = icon[r] or ""
    for c = 1, 8 do
      local col = pal[row:sub(c, c)]
      if col then count[col] = (count[col] or 0) + 1 end
    end
  end
  local best, bestScore = nil, -1
  for col, n in pairs(count) do
    local rr, gg, bb = floor(col / 65536) % 256, floor(col / 256) % 256, col % 256
    local lum = 0.299 * rr + 0.587 * gg + 0.114 * bb
    local sat = max(rr, gg, bb) - min(rr, gg, bb)
    local score = n * (1 + sat / 90)
    if lum < 28 or lum > 235 then score = score * 0.15 end
    if score > bestScore then best, bestScore = col, score end
  end
  best = best or C.accent
  local br, bg2, bb = floor(best / 65536) % 256, floor(best / 256) % 256, best % 256
  if 0.299 * br + 0.587 * bg2 + 0.114 * bb < 75 then best = Screen.blend(0xFFFFFF, best, 0.3) end
  icon._dom = best
  return icon._dom
end

-- ---------- крупные цифры (3×5)
local FONT = {
  ["0"] = {"111", "101", "101", "101", "111"},
  ["1"] = {"010", "110", "010", "010", "111"},
  ["2"] = {"111", "001", "111", "100", "111"},
  ["3"] = {"111", "001", "111", "001", "111"},
  ["4"] = {"101", "101", "111", "001", "001"},
  ["5"] = {"111", "100", "111", "001", "111"},
  ["6"] = {"111", "100", "111", "101", "111"},
  ["7"] = {"111", "001", "001", "001", "001"},
  ["8"] = {"111", "101", "111", "101", "111"},
  ["9"] = {"111", "101", "111", "001", "111"},
  [":"] = {"0", "1", "0", "1", "0"},
  ["."] = {"0", "0", "0", "0", "1"},
  ["-"] = {"000", "000", "111", "000", "000"},
  ["+"] = {"000", "010", "111", "010", "000"},
  [" "] = {"00", "00", "00", "00", "00"},
}

function GUI.bigWidth(text)
  local w = 0
  for ch in tostring(text):gmatch(".") do
    local g = FONT[ch]
    if g then w = w + #g[1] * 2 + 2 end
  end
  return max(0, w - 2)
end

function GUI.bigText(x, y, text, color)
  local cx = x
  for ch in tostring(text):gmatch(".") do
    local g = FONT[ch]
    if g then
      for r = 1, 5 do
        local row = g[r]
        for c = 1, #row do
          if row:sub(c, c) == "1" then Screen.rect(cx + (c - 1) * 2, y + r - 1, 2, 1, color, nil, " ") end
        end
      end
      cx = cx + #g[1] * 2 + 2
    end
  end
  return cx - x - 2
end

-- ---------- базовый виджет
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

-- ---------- панель
local Panel = class()
function Panel:drawSelf(ax, ay)
  if self.bg then Screen.rect(ax, ay, self.w, self.h, rc(self.bg, C.win), nil, " ") end
end
function GUI.panel(x, y, w, h, bg)
  local p = new(Panel, x, y, w, h)
  p.bg = bg
  return p
end

-- ---------- метка
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
function GUI.label(x, y, text, fg, bg, width, align)
  local l = new(Label, x, y, width or 0, 1)
  l.fg, l.bg, l.align = fg, bg, align
  l.fixed = width ~= nil
  l:setText(text)
  return l
end

-- ---------- кнопка Aero
local Button = class()
function Button:drawSelf(ax, ay)
  local top, bottom, fg, edge = C.buttonTop, C.button, C.buttonText, C.buttonEdge
  if self.disabled then
    top, bottom, fg, edge = C.panel, C.panel, C.dim, C.border
  elseif self.active or self.style == "primary" then
    top, bottom, fg = C.selectTop, C.accent, C.accentText
    edge = C.selectEdge
  elseif self.style == "danger" then
    top, bottom, fg = Screen.blend(0xFFFFFF, C.danger, 0.55), C.danger, 0xFFFFFF
    edge = Screen.blend(0x000000, C.danger, 0.7)
  elseif self.color then
    bottom = rc(self.color)
    top = Screen.blend(0xFFFFFF, bottom, 0.42)
    fg = self.textColor and rc(self.textColor) or C.text
    edge = Screen.blend(0x000000, bottom, 0.65)
  elseif self.style == "flat" then
    top, bottom, edge = nil, nil, nil
    fg = C.text
  end
  if bottom then
    GUI.bevel(ax, ay, self.w, self.h, top, bottom, edge)
  end
  local label = GUI.fit(self.text, self.w - 2)
  local tx = ax + floor((self.w - unicode.len(label)) / 2)
  local ty = ay + floor((self.h - 1) / 2)
  -- на глянце текст читаем поверх, сохраняя градиент под буквами
  Screen.text(tx, ty, fg, label)
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

-- ---------- поле ввода (утопленное, белое)
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
  local bc = focused and C.accent or C.inputBorder
  -- утопленная рамка: сверху тень, снизу блик
  Screen.text(ax, ay, bc, "▏", bg)
  Screen.text(ax + self.w - 1, ay, bc, "▕", bg)
  Screen.set(ax + 1, ay, nil, Screen.blend(0x000000, bg, 0.14), "▔")
  Screen.set(ax + self.w - 2, ay, nil, Screen.blend(0x000000, bg, 0.14), "▔")
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
    Screen.text(ax + 1 + self.cursor - self.scroll, ay, C.accent, ch, C.accentText)
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

-- ---------- полоса прокрутки Aero
local function scrollbar(x, y, h, total, visible, scroll)
  if total <= visible or h < 2 then return end
  Screen.rect(x, y, 1, h, C.scrollTrack, nil, " ")
  local thumbH = max(1, floor(h * visible / total))
  local thumbY = floor((h - thumbH) * scroll / max(1, total - visible))
  for r = 0, thumbH - 1 do
    Screen.set(x, y + thumbY + r, nil, C.scrollThumb, "┃")
  end
  Screen.set(x, y, nil, C.border, "▴")
  Screen.set(x, y + h - 1, nil, C.border, "▾")
end
GUI.scrollbar = scrollbar

-- ---------- список
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
  local base = rc(self.bg, C.winAlt)
  Screen.rect(ax, ay, self.w, self.h, base, nil, " ")
  local total = #self.items
  if self.scroll > total - vis then self.scroll = max(0, total - vis) end
  local needBar = total > vis
  local textW = self.w - (needBar and 1 or 0)
  for row = 1, vis do
    local idx = self.scroll + row
    local item = self.items[idx]
    if not item then break end
    local y = ay + (row - 1) * rh
    local sel = idx == self.selected
    local bg = base
    if sel then
      bg = C.accent
      for r = 0, rh - 1 do
        GUI.gloss(ax, y + r, textW, C.selectTop, C.accent)
      end
    elseif self.striped and idx % 2 == 0 then
      bg = rc(self.bg, C.winAlt) == C.winAlt and C.win or C.winAlt
      Screen.rect(ax, y, textW, rh, bg, nil, " ")
    end
    if self.render then
      self.render(self, item, idx, ax, y, textW, sel, bg)
    else
      local label = type(item) == "table" and item.text or tostring(item)
      Screen.text(ax + 1, y, sel and C.accentText or C.text, GUI.fit(label, textW - 2), bg)
    end
  end
  if needBar then scrollbar(ax + self.w - 1, ay, self.h, total, vis, self.scroll) end
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

-- ---------- текстовый блок
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
    scrollbar(ax + self.w - 1, ay, self.h, #self.lines, self.h, self.scroll)
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

-- ---------- переключатель и прогресс
local Switch = class()
function Switch:drawSelf(ax, ay)
  local off = Screen.blend(0x000000, C.border, 0.85)
  GUI.gloss(ax, ay, 6, self.on and C.selectTop or C.buttonTop, self.on and C.accent or off)
  local knobX = ax + (self.on and 4 or 0)
  GUI.gloss(knobX, ay, 2, 0xFFFFFF, 0xC8CED4)
  Screen.set(knobX, ay, nil, C.buttonEdge, "▏")
  Screen.set(knobX + 1, ay, nil, C.buttonEdge, "▕")
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
  -- прогресс Windows 7: утопленный жёлоб и зелёный глянцевый столбик
  local bgc = rc(self.bg, C.win)
  Screen.rect(ax, ay, self.w, 1, bgc, nil, " ")
  GUI.gloss(ax, ay, self.w, Screen.blend(0x000000, bgc, 0.14), Screen.blend(0xFFFFFF, bgc, 0.6))
  local n = floor(self.w * max(0, min(1, self.value)) + 0.5)
  if n > 0 then
    local base = rc(self.color, 0x2FA82F)
    GUI.gloss(ax, ay, n, Screen.blend(0xFFFFFF, base, 0.72), base)
  end
  Screen.set(ax, ay, nil, C.border, "▏")
  Screen.set(ax + self.w - 1, ay, nil, C.border, "▕")
end
function GUI.progress(x, y, w, value, color)
  local p = new(Progress, x, y, w, 1)
  p.value, p.color = value or 0, color
  return p
end

function GUI.hline(x, y, w, color)
  return GUI.label(x, y, string.rep("─", w), color or "border")
end

-- ---------- окно Aero
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

--- Кнопки заголовка Windows 7: [─] [□] [✕] справа
function Window:titleButton(px)
  local rx = px - (self.x + self.w - 1)
  if rx > 0 then return nil end
  if rx > -5 then return "close" end
  if self.modal then return nil end
  if rx > -10 then return "max" end
  if rx > -15 then return "min" end
end

function Window:draw(focused)
  local x, y, w, h = self.x, self.y, self.w, self.h
  -- Тень окна — только с эффектами: на слабом железе это лишние вызовы GPU.
  if not self.maximized and self.shadow ~= false then
    Screen.rect(x + 1, y + 1, w, h, 0x000000, nil, nil, 0.38)
  end
  -- стеклянный заголовок
  local tTop = focused and C.titleTop or Screen.blend(C.titleTop, C.frameDim, 0.75)
  local tBot = focused and C.title or Screen.blend(C.title, C.frameDim, 0.75)
  GUI.gloss(x, y, w, tTop, tBot)
  -- тонкая светлая кромка по краям стекла
  Screen.set(x, y, nil, focused and C.frame or C.frameDim, "▏")
  Screen.set(x + w - 1, y, nil, focused and C.frame or C.frameDim, "▕")

  local fg = focused and C.titleText or C.titleDim
  local iconCol = focused and (self.iconColor or C.accentLight) or C.titleDim
  Screen.text(x + 1, y, iconCol, "◆", tBot)

  local btnW = self.modal and 6 or 16
  local label = GUI.fit(self.title or "", max(1, w - 4 - btnW))
  -- лёгкая тень под текстом заголовка — фирменный приём Aero
  Screen.text(x + 4, y, Screen.blend(0x000000, tBot, 0.55), label)
  Screen.text(x + 3, y, fg, label)

  -- кнопки управления окном
  local bx = x + w - 5
  local closeTop = focused and 0xF08A80 or Screen.blend(C.titleTop, C.frameDim, 0.7)
  local closeBot = focused and 0xC0392B or Screen.blend(C.title, C.frameDim, 0.7)
  GUI.gloss(bx, y, 5, closeTop, closeBot)
  Screen.text(bx + 2, y, 0xFFFFFF, "✕")
  if not self.modal then
    GUI.gloss(bx - 5, y, 5, tTop, tBot)
    Screen.text(bx - 3, y, self.resizable and fg or C.titleDim, self.maximized and "❐" or "□")
    GUI.gloss(bx - 10, y, 5, tTop, tBot)
    Screen.text(bx - 8, y, fg, "─")
  end

  self.content.w, self.content.h = w, h - 1
  self.content:draw(x, y + 1)

  if self.menu then
    local mx = x + 1
    Screen.rect(x + 1, y + 1, w - 2, 1, C.menubar, nil, " ")
    self.menuHits = {}
    for _, m in ipairs(self.menu) do
      local text = " " .. m.title .. " "
      local len = unicode.len(text)
      Screen.text(mx, y + 1, C.menubarText, text, C.menubar)
      self.menuHits[#self.menuHits + 1] = {x1 = mx, x2 = mx + len - 1, m = m}
      mx = mx + len
    end
  end
  if self.resizable and not self.maximized then
    Screen.text(x + w - 2, y + h - 1, C.dim, "◢", rc(self.content.bg, C.win))
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

function Window:openMenu(hit)
  local items = hit.m.items
  if type(items) == "function" then items = items() end
  GUI.menu(hit.x1, self.y + 2, items)
end

function Window:dispatch(e)
  local c, t = self.content, e.type
  if t == "touch" then
    if self.menu and e.y == self.y + 1 then
      for _, h in ipairs(self.menuHits or {}) do
        if e.x >= h.x1 and e.x <= h.x2 then
          self:openMenu(h)
          return true
        end
      end
      return true
    end
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

function Window:event(e)
  if e.type == "touch" and e.y == self.y and self:titleButton(e.x) == "close" then
    self.closed = true
  elseif e.type == "key" and e.code == 1 then
    self.closed = true
  else
    self:dispatch(e)
  end
end

-- ---------- диалоги
function GUI.runModal(modal)
  return GUI.desktop.runModal(modal)
end

function GUI.modalWindow(title, w, h)
  local sw, sh = Screen.size()
  w, h = min(w, sw), min(h, sh - 4)
  local win = GUI.window(floor((sw - w) / 2) + 1, max(1, floor((sh - 3 - h) / 2) + 1), w, h, title)
  win.modal = true
  return win
end

--- Нижняя панель диалога, как в Windows 7 (серая полоса с кнопками справа)
local function dialogFooter(win, y)
  local c = win.content
  Screen.rect(win.x + 1, win.y + y, win.w - 2, 2, C.panel, nil, " ")
  return c
end

function GUI.alert(title, message, okText)
  local lines = GUI.wrap(message, 42)
  local n = min(#lines, 18)
  local win = GUI.modalWindow(title, 52, n + 7)
  local c = win.content
  Screen.rect(2, 2, 5, n + 1, C.win, nil, " ")
  Screen.text(3, 3, C.accent, "◉", C.win)
  for i = 1, n do c:add(GUI.label(8, 1 + i, lines[i])) end
  dialogFooter(win, n + 3)
  c:add(GUI.button(win.w - 17, n + 4, 14, 2, okText or "OK", function() win.closed = true end, "primary"))
  win.onEnter = function() win.closed = true end
  GUI.runModal(win)
end

function GUI.confirm(title, message, yesText, noText, danger)
  local lines = GUI.wrap(message, 42)
  local n = min(#lines, 18)
  local win = GUI.modalWindow(title, 52, n + 7)
  local c = win.content
  Screen.text(3, 3, danger and C.danger or C.warning, danger and "▲" or "?", C.win)
  for i = 1, n do c:add(GUI.label(8, 1 + i, lines[i])) end
  dialogFooter(win, n + 3)
  c:add(GUI.button(win.w - 33, n + 4, 14, 2, yesText or "Да", function() win.result = true win.closed = true end, danger and "danger" or "primary"))
  c:add(GUI.button(win.w - 17, n + 4, 14, 2, noText or "Отмена", function() win.result = false win.closed = true end))
  win.onEnter = function() win.result = true win.closed = true end
  return GUI.runModal(win) == true
end

function GUI.prompt(title, message, default, mask)
  local lines = GUI.wrap(message, 44)
  local n = min(#lines, 10)
  local win = GUI.modalWindow(title, 52, n + 9)
  local c = win.content
  for i = 1, n do c:add(GUI.label(3, 1 + i, lines[i])) end
  local input = c:add(GUI.input(3, n + 3, 46, default or "", nil, {mask = mask}))
  c.focused = input
  local function ok() win.result = input.text win.closed = true end
  input.onSubmit = ok
  dialogFooter(win, n + 5)
  c:add(GUI.button(win.w - 33, n + 6, 14, 2, "OK", ok, "primary"))
  c:add(GUI.button(win.w - 17, n + 6, 14, 2, "Отмена", function() win.closed = true end))
  return GUI.runModal(win)
end

function GUI.select(title, options)
  local h = min(#options, 14)
  local win = GUI.modalWindow(title, 46, h + 7)
  local c = win.content
  local list = c:add(GUI.list(2, 2, 42, h, options))
  list.selected = 1
  c.focused = list
  list.onActivate = function(_, idx) win.result = idx win.closed = true end
  dialogFooter(win, h + 3)
  c:add(GUI.button(win.w - 33, h + 4, 14, 2, "Выбрать", function()
    if list.selected > 0 then win.result = list.selected win.closed = true end
  end, "primary"))
  c:add(GUI.button(win.w - 17, h + 4, 14, 2, "Отмена", function() win.closed = true end))
  return GUI.runModal(win)
end

-- ---------- контекстное меню Windows 7
function GUI.menu(x, y, items)
  local sw, sh = Screen.size()
  local w = 12
  for _, it in ipairs(items) do
    if not it.separator then
      w = max(w, unicode.len(it.text) + (it.hint and unicode.len(it.hint) + 3 or 0) + 7)
    end
  end
  local h = #items + 2
  x = max(1, min(x, sw - w))
  y = max(1, min(y, sh - h))
  local m = {x = x, y = y, w = w, h = h, items = items, noDim = true, closed = false}
  for i, it in ipairs(items) do
    if not it.separator and not it.disabled then m.sel = i break end
  end
  function m:draw()
    Screen.rect(self.x + 1, self.y + 1, self.w, self.h, 0x000000, nil, nil, 0.35)
    Screen.rect(self.x, self.y, self.w, self.h, C.menu, nil, " ")
    -- полоса значков слева, как в меню Windows 7
    Screen.rect(self.x + 1, self.y + 1, 3, self.h - 2, C.menuGutter, nil, " ")
    for r = 0, self.h - 1 do
      Screen.set(self.x, self.y + r, nil, C.menuBorder, "▏")
      Screen.set(self.x + self.w - 1, self.y + r, nil, C.menuBorder, "▕")
    end
    GUI.gloss(self.x + 1, self.y, self.w - 2, C.menuBorder, C.menu)
    GUI.gloss(self.x + 1, self.y + self.h - 1, self.w - 2, C.menu, C.menuBorder)
    for i, it in ipairs(self.items) do
      local yy = self.y + i
      if it.separator then
        Screen.text(self.x + 4, yy, C.menuBorder, string.rep("─", self.w - 5), C.menu)
      else
        local sel = i == self.sel
        local bg = C.menu
        if sel then
          bg = C.menuSel
          GUI.gloss(self.x + 4, yy, self.w - 5, C.menuSelTop, C.menuSel)
        end
        local fg = it.disabled and C.menuDim or (sel and 0xFFFFFF or C.menuText)
        Screen.text(self.x + 5, yy, fg, GUI.fit(it.text, self.w - 7), bg)
        if it.hint then
          Screen.text(self.x + self.w - unicode.len(it.hint) - 2, yy, sel and 0xE8F2FB or C.menuDim, it.hint, bg)
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
      if e.x >= self.x and e.x < self.x + self.w and e.y > self.y and e.y < self.y + self.h - 1 then
        local it = self.items[e.y - self.y]
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
  {"/Libraries/HTML.lua", [=[
-- ----------
--  CubeOS :: HTML
--  Лёгкий движок страниц для текстового экрана OpenComputers:
--    HTML.parse(src, {base})      — HTML → документ (блоки, ссылки, поля форм)
--    HTML.markdown(src, {base})   — Markdown → тот же документ
--    HTML.plain(text)             — обычный текст
--    HTML.layout(doc, width)      — документ → строки экрана (перенос слов)
--    HTML.toUtf8(body, charset)   — windows-1251 / latin1 → UTF-8
--
--  JavaScript не выполняется: <script> и <style> пропускаются.
--
--  ВАЖНО: OpenComputers убивает Lua, который долго не отдаёт управление.
--  Поэтому тяжёлые функции вызывают checkpoint(): если HTML.async включён и
--  вышло время HTML.deadline — сопрограмма уступает ход (coroutine.yield).
--  Драйвер (Браузер) запускает их в сопрограмме и дорабатывает в onTick.
-- ----------
local unicode = unicode
local HTTP = require("HTTP")
local utf8lib = utf8
local ulen, usub = unicode.len, unicode.sub
local max, min = math.max, math.min
local clock = os.clock or require("computer").uptime

local HTML = {async = false, deadline = math.huge}

local function checkpoint()
  if HTML.async and clock() >= HTML.deadline then coroutine.yield() end
end

-- ---------- кодировки
local CP1251, LATIN1 = {}, {}
do
  local special = {
    [128] = 0x402, [129] = 0x403, [130] = 0x201A, [131] = 0x453, [132] = 0x201E, [133] = 0x2026, [134] = 0x2020,
    [135] = 0x2021, [136] = 0x20AC, [137] = 0x2030, [138] = 0x409, [139] = 0x2039, [140] = 0x40A, [141] = 0x40C,
    [142] = 0x40B, [143] = 0x40F, [144] = 0x452, [145] = 0x2018, [146] = 0x2019, [147] = 0x201C, [148] = 0x201D,
    [149] = 0x2022, [150] = 0x2013, [151] = 0x2014, [152] = 63, [153] = 0x2122, [154] = 0x459, [155] = 0x203A,
    [156] = 0x45A, [157] = 0x45C, [158] = 0x45B, [159] = 0x45F, [160] = 32, [161] = 0x40E, [162] = 0x45E,
    [163] = 0x408, [164] = 0xA4, [165] = 0x490, [166] = 0xA6, [167] = 0xA7, [168] = 0x401, [169] = 0xA9,
    [170] = 0x404, [171] = 0xAB, [172] = 0xAC, [173] = 0xAD, [174] = 0xAE, [175] = 0x407, [176] = 0xB0,
    [177] = 0xB1, [178] = 0x406, [179] = 0x456, [180] = 0x491, [181] = 0xB5, [182] = 0xB6, [183] = 0xB7,
    [184] = 0x451, [185] = 0x2116, [186] = 0x454, [187] = 0xBB, [188] = 0x458, [189] = 0x405, [190] = 0x455,
    [191] = 0x457,
  }
  for b = 128, 191 do CP1251[string.char(b)] = unicode.char(special[b]) end
  for b = 192, 255 do CP1251[string.char(b)] = unicode.char(0x410 + b - 192) end
  for b = 128, 255 do LATIN1[string.char(b)] = unicode.char(b == 160 and 32 or b) end
end

--- Определить кодировку: из заголовка Content-Type, затем из <meta charset>
function HTML.charsetOf(contentType, body)
  local cs = (contentType or ""):lower():match("charset%s*=%s*[\"']?([%w_%-]+)")
  if cs then return cs end
  return body:sub(1, 2048):lower():match("charset%s*=%s*[\"']?([%w_%-]+)")
end

--- Привести тело страницы к корректному UTF-8
function HTML.toUtf8(body, charset)
  charset = (charset or ""):lower()
  if charset == "windows-1251" or charset == "cp1251" or charset == "win-1251" or charset == "x-cp1251" then
    return (body:gsub("[\128-\255]", CP1251))
  elseif charset == "iso-8859-1" or charset == "latin1" or charset == "windows-1252" or charset == "iso-8859-15" then
    return (body:gsub("[\128-\255]", LATIN1))
  end
  if utf8lib and not utf8lib.len(body) then
    -- обрезанный на полуслове хвост (страница усечена по лимиту)
    for cut = 1, 3 do
      local t = body:sub(1, #body - cut)
      if utf8lib.len(t) then return t end
    end
    if charset == "" then return (body:gsub("[\128-\255]", CP1251)) end -- нет заголовка: чаще всего русский сайт
    for _ = 1, 300 do -- прочие ошибки: заменяем битые байты на «?»
      local ok, pos = utf8lib.len(body)
      if ok then break end
      body = body:sub(1, pos - 1) .. "?" .. body:sub(pos + 1)
    end
  end
  return body
end

-- ---------- сущности и очистка текста
local ENT = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", ensp = " ", emsp = " ", thinsp = " ",
  copy = "©", reg = "®", trade = "™", mdash = "—", ndash = "–", hellip = "…", laquo = "«", raquo = "»",
  ldquo = "“", rdquo = "”", bdquo = "„", lsquo = "‘", rsquo = "’", sbquo = "‚", bull = "•", middot = "·",
  rarr = "→", larr = "←", uarr = "↑", darr = "↓", harr = "↔", euro = "€", times = "×", divide = "÷",
  deg = "°", plusmn = "±", para = "¶", sect = "§", pound = "£", yen = "¥", cent = "¢", frac12 = "½",
  frac14 = "¼", frac34 = "¾", micro = "µ", hearts = "♥", check = "✓", shy = "", zwnj = "", zwj = "",
  lrm = "", rlm = "", ne = "≠", le = "≤", ge = "≥", infin = "∞", prime = "′", Prime = "″",
}

local function decode(s)
  if not s:find("&", 1, true) then return s end
  return (s:gsub("&(#?)(%w+);", function(hash, name)
    if hash == "#" then
      local first = name:sub(1, 1)
      local code
      if first == "x" or first == "X" then code = tonumber(name:sub(2), 16) else code = tonumber(name) end
      if not code or (code < 32 and code ~= 9 and code ~= 10) or code > 0x10FFFF or (code >= 0xD800 and code < 0xE000) then
        return ""
      end
      if code == 160 then return " " end
      return unicode.char(code)
    end
    return ENT[name]
  end))
end

--- Убираем то, что ломает сетку текстового экрана: широкие иероглифы и эмодзи занимают 2 ячейки
local function sanitize(s)
  if not s:find("[\194\226-\244]") then return s end
  s = s:gsub("\239\187\191", "")                              -- BOM
  s = s:gsub("\226\128[\139-\143]", "")                       -- нулевой ширины
  s = s:gsub("\226\128[\168-\174]", "")
  s = s:gsub("\194\173", "")                                  -- мягкий перенос
  s = s:gsub("[\227-\237][\128-\191][\128-\191]", "?")        -- CJK, хангыль
  s = s:gsub("\239[\188\189][\128-\191]", "?")                -- полноширинные формы
  s = s:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", "?") -- эмодзи и редкие символы
  return s
end

local function trim(s) return (s:match("^%s*(.-)%s*$")) end

-- ---------- построитель документа
local function newBuilder(base)
  local doc = {title = "", blocks = {}, items = {}, forms = {}, anchors = {}, nanchors = 0, base = base}
  local blocks, items = doc.blocks, doc.items
  local cur, gap = nil, false
  local ctx = {indent = 0, bar = 0, lists = {}, pre = 0, bold = 0, italic = 0, code = 0, dim = 0, head = nil, link = nil}
  local B = {doc = doc, ctx = ctx, form = nil}

  function B.gap() gap = true end

  function B.push()
    if cur then
      if cur.has then blocks[#blocks + 1] = cur end
      cur = nil
    end
  end

  function B.new(kind)
    B.push()
    cur = {kind = kind or "p", indent = ctx.indent, bar = ctx.bar > 0 or nil, pre = ctx.pre > 0 or nil, gap = gap or nil, runs = {}}
    gap = false
    return cur
  end

  function B.current() return cur end

  function B.style()
    if ctx.link then return "link" end
    if ctx.pre > 0 then return "pre" end
    if ctx.code > 0 then return "code" end
    if ctx.head then return ctx.head end
    if ctx.bold > 0 then return ctx.italic > 0 and "bolditalic" or "bold" end
    if ctx.italic > 0 then return "italic" end
    if ctx.dim > 0 then return "dim" end
    return "plain"
  end

  --- Добавить уже раскодированный текст
  function B.text(text)
    text = sanitize(text)
    if ctx.pre > 0 then
      text = text:gsub("\r\n?", "\n"):gsub("\t", "  ")
    else
      text = text:gsub("%s+", " ")
      if text == " " and not cur then return end
    end
    if text == "" then return end
    if not cur then B.new() end
    local runs = cur.runs
    local last = runs[#runs]
    if ctx.pre == 0 and text:sub(1, 1) == " " and (not last or last.br or (last.t and last.t:sub(-1) == " ")) then
      text = text:sub(2)
      if text == "" then return end
    end
    local style, item = B.style(), ctx.link
    if last and last.t and last.s == style and last.i == item then
      last.t = last.t .. text
    else
      runs[#runs + 1] = {t = text, s = style, i = item}
    end
    if not cur.has and text:find("%S") then cur.has = true end
  end

  --- Добавить кусок как есть (картинки, разделители)
  function B.run(text, style, item)
    if not cur then B.new() end
    cur.runs[#cur.runs + 1] = {t = text, s = style, i = item}
    cur.has = true
  end

  function B.br()
    if not cur then B.new() end
    cur.runs[#cur.runs + 1] = {br = true}
  end

  function B.rule()
    B.push()
    blocks[#blocks + 1] = {kind = "hr", rule = true, indent = ctx.indent, gap = gap or nil, runs = {}}
    gap = false
  end

  function B.addItem(item)
    items[#items + 1] = item
    return #items
  end

  function B.anchor(id)
    if id ~= "" and not doc.anchors[id] and doc.nanchors < 400 then
      doc.anchors[id] = #blocks + 1
      doc.nanchors = doc.nanchors + 1
    end
  end

  function B.field(f)
    f.form = B.form
    if B.form then B.form.fields[#B.form.fields + 1] = f end
    if f.kind == "hidden" then return end
    local idx = B.addItem({kind = "field", field = f})
    if not cur then B.new() end
    cur.runs[#cur.runs + 1] = {f = f, i = idx, s = "field"}
    cur.has = true
  end

  return B
end

-- ---------- HTML: теги и атрибуты
local VOID = {br = 1, hr = 1, img = 1, input = 1, meta = 1, link = 1, base = 1, wbr = 1, col = 1, area = 1, source = 1, track = 1, param = 1, embed = 1}
local SKIP = {script = 1, style = 1, noscript = 1, template = 1, svg = 1, math = 1, object = 1, canvas = 1, iframe = 1, audio = 1, video = 1, datalist = 1}
local BREAK = {
  div = 1, section = 1, article = 1, header = 1, footer = 1, nav = 1, main = 1, aside = 1, address = 1, figure = 1,
  figcaption = 1, center = 1, summary = 1, legend = 1, fieldset = 1, details = 1, thead = 1, tbody = 1, tfoot = 1,
  body = 1, html = 1, hgroup = 1, menu = 1, dir = 1, search = 1,
}
local ATTRS = {a = 1, img = 1, input = 1, form = 1, button = 1, select = 1, textarea = 1, base = 1}
local EMPTY = {}
-- теги с необязательным закрывающим: «пропустить до пары» для них ненадёжно
local NOSKIP = {p = 1, li = 1, dt = 1, dd = 1, tr = 1, td = 1, th = 1, option = 1, thead = 1, tbody = 1, tfoot = 1, html = 1, body = 1, head = 1}

local ciCache = {}
local function ci(name)
  local p = ciCache[name]
  if not p then
    p = name:gsub("%a", function(ch) return "[" .. ch:lower() .. ch:upper() .. "]" end)
    ciCache[name] = p
  end
  return p
end

--- Конец тега: ищем «>» вне кавычек
local function tagEnd(s, i)
  local from = i
  while true do
    local j = s:find("[>\"']", i)
    if not j then return nil end
    local c = s:sub(j, j)
    if c == ">" then return j end
    local k = s:find(c, j + 1, true)
    if not k then return s:find(">", from, true) end
    i = k + 1
  end
end

local function parseAttrs(s)
  local a = {}
  local pos = 1
  while true do
    local ns, ne, name = s:find("^[%s/]*([^%s=/>]+)", pos)
    if not ns then break end
    pos = ne + 1
    local value = ""
    local _, e2 = s:find("^%s*=%s*", pos)
    if e2 then
      pos = e2 + 1
      local q = s:sub(pos, pos)
      if q == '"' or q == "'" then
        local close = s:find(q, pos + 1, true) or (#s + 1)
        value = s:sub(pos + 1, close - 1)
        pos = close + 1
      else
        local _, ve, v = s:find("^([^%s>]*)", pos)
        value = v or ""
        pos = (ve or pos) + 1
      end
    end
    a[name:lower()] = decode(value)
  end
  return a
end

--- HTML → документ
function HTML.parse(src, opts)
  opts = opts or {}
  local B = newBuilder(opts.base or "")
  local ctx, doc = B.ctx, B.doc
  local base = doc.base
  local n = #src
  local pos, tokens = 1, 0
  -- skipChrome («режим чтения»): выбрасываем меню, боковые панели и подвал
  local skipChrome = opts.skipChrome

  local function afterClose(from, name)
    local close = src:find("</" .. ci(name), from)
    if not close then return nil, nil end
    local ce = src:find(">", close, true)
    return close, (ce or n) + 1
  end

  --- Индекс после парного закрывающего тега (учитывая вложенность) или nil, если пары нет
  local function skipBalanced(name, from)
    local depth, p, iter = 1, from, 0
    local pat = "<(/?)" .. ci(name) .. "[%s/>]"
    while true do
      local s, e, slash = src:find(pat, p)
      if not s then return nil end
      if slash == "/" then depth = depth - 1 else depth = depth + 1 end
      iter = iter + 1
      if iter % 200 == 0 then checkpoint() end
      if depth == 0 then
        local ce = src:find(">", e, true)
        return (ce or n) + 1
      end
      p = e + 1
    end
  end

  local function onOpen(name, at, e, selfClose)
    if not VOID[name] and not selfClose and not NOSKIP[name] and not SKIP[name] then
      local hide = at.hidden ~= nil or at["aria-hidden"] == "true"
        or (at.style and at.style:lower():find("display%s*:%s*none") ~= nil)
      if not hide and skipChrome then
        hide = name == "nav" or name == "aside" or name == "footer"
          or at.role == "navigation" or at.role == "complementary" or at.role == "contentinfo"
      end
      if hide then
        local after = skipBalanced(name, e + 1)
        if after then return after end
      end
    end
    if SKIP[name] then
      if selfClose then return nil end
      local _, after = afterClose(e + 1, name)
      return after or (n + 1)
    end
    if name == "title" then
      local close, after = afterClose(e + 1, "title")
      if close then
        local t = decode(src:sub(e + 1, close - 1)):gsub("%s+", " ")
        doc.title = sanitize(trim(t))
      end
      return after or (n + 1)
    elseif name == "base" then
      if at.href then base = HTTP.join(base, at.href) end
    elseif name:match("^h[1-6]$") then
      B.gap()
      B.new(name)
      ctx.head = name
    elseif name == "p" then
      B.gap()
      B.push()
    elseif name == "br" then
      B.br()
    elseif name == "hr" then
      B.rule()
    elseif name == "img" then
      local w, h = tonumber(at.width), tonumber(at.height)
      if (w and w <= 2) or (h and h <= 2) then return nil end
      local alt = trim(sanitize(at.alt or ""))
      if ulen(alt) > 40 then alt = usub(alt, 1, 39) .. "…" end
      local label = alt ~= "" and ("[" .. alt .. "]") or "[img]"
      if ctx.link then
        B.text(label)
      else
        local srcUrl = at.src or at["data-src"]
        if srcUrl and srcUrl ~= "" and not srcUrl:match("^data:") then
          local idx = B.addItem({kind = "link", href = HTTP.join(base, srcUrl), img = true})
          B.run(label, "img", idx)
        else
          B.run(label, "dim")
        end
      end
    elseif name == "ul" or name == "ol" then
      B.push()
      if #ctx.lists == 0 then B.gap() end
      local step = name == "ol" and 4 or 3
      ctx.lists[#ctx.lists + 1] = {ordered = name == "ol", n = 0, step = step}
      ctx.indent = ctx.indent + step
    elseif name == "li" then
      B.push()
      local list = ctx.lists[#ctx.lists]
      local prefix = "• "
      if list then
        if list.ordered then
          list.n = list.n + 1
          prefix = list.n .. ". "
        elseif #ctx.lists > 1 then
          prefix = "◦ "
        end
      end
      local blk = B.new("li")
      blk.prefix = prefix
      if not list then blk.indent = ctx.indent + 2 end
    elseif name == "dl" then
      B.push()
      B.gap()
    elseif name == "dt" then
      B.push()
    elseif name == "dd" then
      B.push()
      local blk = B.new("dd")
      blk.indent = ctx.indent + 3
    elseif name == "blockquote" then
      B.push()
      B.gap()
      ctx.indent = ctx.indent + 2
      ctx.bar = ctx.bar + 1
    elseif name == "pre" then
      B.push()
      B.gap()
      ctx.pre = ctx.pre + 1
      B.new("pre")
    elseif name == "table" then
      B.push()
      B.gap()
    elseif name == "tr" then
      B.push()
    elseif name == "td" or name == "th" then
      local c0 = B.current()
      if c0 and c0.has then B.run(" │ ", "dim") end
      if name == "th" then ctx.bold = ctx.bold + 1 end
    elseif name == "caption" then
      B.push()
      B.gap()
    elseif name == "a" then
      local href = at.href
      if href and href ~= "" and href ~= "#" and not href:match("^%s*[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]:") then
        ctx.link = B.addItem({kind = "link", href = HTTP.join(base, href)})
      end
    elseif name == "b" or name == "strong" then
      ctx.bold = ctx.bold + 1
    elseif name == "i" or name == "em" or name == "cite" or name == "var" or name == "dfn" then
      ctx.italic = ctx.italic + 1
    elseif name == "code" or name == "kbd" or name == "samp" or name == "tt" then
      ctx.code = ctx.code + 1
    elseif name == "small" or name == "sub" or name == "sup" or name == "del" or name == "s" or name == "strike" then
      ctx.dim = ctx.dim + 1
    elseif name == "q" then
      B.text('"')
    elseif name == "form" then
      B.push()
      local form = {action = HTTP.join(base, at.action or ""), method = (at.method or "get"):upper(), fields = {}}
      doc.forms[#doc.forms + 1] = form
      B.form = form
    elseif name == "input" then
      local t = (at.type or "text"):lower()
      if t == "file" or t == "reset" or t == "range" or t == "color" then return nil end
      local f = {kind = "text", name = at.name, value = at.value or "", size = tonumber(at.size), placeholder = at.placeholder}
      if t == "hidden" then
        f.kind = "hidden"
      elseif t == "checkbox" or t == "radio" then
        f.kind = t
        f.checked = at.checked ~= nil
        f.value = at.value or "on"
      elseif t == "submit" or t == "button" or t == "image" then
        f.kind = "submit"
        f.label = trim(at.value or at.alt or "")
        if f.label == "" then f.label = (t == "submit") and "Отправить" or "OK" end
        f.button = t == "button"
      elseif t == "password" then
        f.kind = "password"
      end
      B.field(f)
    elseif name == "button" then
      local close, after = afterClose(e + 1, "button")
      local content = close and src:sub(e + 1, close - 1) or ""
      content = content:gsub("<[^>]*>", " ")
      local label = trim((decode(content):gsub("%s+", " ")))
      local t = (at.type or "submit"):lower()
      B.field({kind = "submit", name = at.name, value = at.value or "", label = label ~= "" and sanitize(label) or (at.value or "OK"), button = t == "button" or t == "reset"})
      return after
    elseif name == "select" then
      local close, after = afterClose(e + 1, "select")
      local content = close and src:sub(e + 1, close - 1) or ""
      local f = {kind = "select", name = at.name, options = {}, sel = 1}
      for oattr, otext in content:gmatch("<[oO][pP][tT][iI][oO][nN]([^>]*)>([^<]*)") do
        local oa = parseAttrs(oattr)
        local label = sanitize(trim((decode(otext):gsub("%s+", " "))))
        f.options[#f.options + 1] = {v = oa.value or label, label = label ~= "" and label or "—"}
        if oa.selected ~= nil then f.sel = #f.options end
      end
      if #f.options == 0 then f.options[1] = {v = "", label = "—"} end
      B.field(f)
      return after
    elseif name == "textarea" then
      local close, after = afterClose(e + 1, "textarea")
      local content = close and src:sub(e + 1, close - 1) or ""
      content = decode(content):gsub("^\r?\n", "")
      B.field({kind = "text", name = at.name, value = sanitize(content), size = 40, placeholder = at.placeholder, multi = true})
      return after
    elseif BREAK[name] then
      B.push()
    end
    return nil
  end

  local function onClose(name)
    if name:match("^h[1-6]$") then
      B.push()
      ctx.head = nil
      B.gap()
    elseif name == "p" then
      B.push()
      B.gap()
    elseif name == "ul" or name == "ol" then
      B.push()
      local list = table.remove(ctx.lists)
      if list then ctx.indent = max(0, ctx.indent - list.step) end
      if #ctx.lists == 0 then B.gap() end
    elseif name == "li" or name == "dt" or name == "dd" or name == "tr" or name == "caption" then
      B.push()
    elseif name == "dl" or name == "table" then
      B.push()
      B.gap()
    elseif name == "blockquote" then
      B.push()
      ctx.indent = max(0, ctx.indent - 2)
      ctx.bar = max(0, ctx.bar - 1)
      B.gap()
    elseif name == "pre" then
      B.push()
      ctx.pre = max(0, ctx.pre - 1)
      B.gap()
    elseif name == "th" then
      ctx.bold = max(0, ctx.bold - 1)
    elseif name == "a" then
      ctx.link = nil
    elseif name == "b" or name == "strong" then
      ctx.bold = max(0, ctx.bold - 1)
    elseif name == "i" or name == "em" or name == "cite" or name == "var" or name == "dfn" then
      ctx.italic = max(0, ctx.italic - 1)
    elseif name == "code" or name == "kbd" or name == "samp" or name == "tt" then
      ctx.code = max(0, ctx.code - 1)
    elseif name == "small" or name == "sub" or name == "sup" or name == "del" or name == "s" or name == "strike" then
      ctx.dim = max(0, ctx.dim - 1)
    elseif name == "q" then
      B.text('"')
    elseif name == "form" then
      B.push()
      B.form = nil
    elseif BREAK[name] then
      B.push()
    end
  end

  while pos <= n do
    tokens = tokens + 1
    if tokens % 48 == 0 then checkpoint() end
    local lt = src:find("<", pos, true)
    if not lt then
      B.text(decode(src:sub(pos)))
      break
    end
    if lt > pos then B.text(decode(src:sub(pos, lt - 1))) end
    local nx = src:sub(lt + 1, lt + 1)
    if src:sub(lt, lt + 3) == "<!--" then
      local e = src:find("-->", lt + 4, true)
      pos = e and (e + 3) or (n + 1)
    elseif nx == "!" or nx == "?" then
      local e = src:find(">", lt, true)
      pos = e and (e + 1) or (n + 1)
    elseif nx == "/" or nx:match("%a") then
      local e = tagEnd(src, lt + 1)
      if not e then
        pos = n + 1 -- тег оборван (страница усечена)
      else
        pos = e + 1
        local inner = src:sub(lt + 1, e - 1)
        local slash, name = inner:match("^(/?)([%w:%-]+)")
        if name then
          name = name:lower()
          if slash == "/" then
            onClose(name)
          else
            local at = EMPTY
            if ATTRS[name] or inner:find("%sid%s*=") or inner:find("hidden", 1, true) or inner:find("display", 1, true)
              or (skipChrome and inner:find("role", 1, true)) then
              at = parseAttrs(inner:sub(#name + 1))
            end
            if at.id then B.anchor(at.id) end
            if name == "a" and at.name then B.anchor(at.name) end
            local np = onOpen(name, at, e, inner:sub(-1) == "/" or VOID[name] ~= nil)
            if np then pos = np end
          end
        end
      end
    else
      B.text("<")
      pos = lt + 1
    end
  end
  B.push()
  return doc
end

-- ---------- обычный текст и Markdown
function HTML.plain(text, title)
  local B = newBuilder("")
  B.ctx.pre = 1
  B.new("pre")
  B.text(text)
  B.push()
  B.doc.title = title or ""
  return B.doc
end

--- Добавить в конец документа пояснение (например, «страница обрезана»)
function HTML.note(doc, text)
  doc.blocks[#doc.blocks + 1] = {kind = "p", indent = 0, gap = true, has = true, runs = {{t = text, s = "dim"}}}
end

function HTML.markdown(src, opts)
  local base = (opts and opts.base) or ""
  local B = newBuilder(base)
  local ctx, doc = B.ctx, B.doc
  src = src:gsub("\r\n?", "\n")

  -- заголовок режима чтения r.jina.ai: Title / URL Source / Warning / Markdown Content
  local pos = 1
  local head = src:sub(1, 1500)
  -- у вывода r.jina.ai каждая строка — отдельный блок (а не продолжение абзаца, как в обычном Markdown)
  local hard = head:match("^Title:") ~= nil
  if head:match("^Title:") then
    doc.title = sanitize(trim(head:match("^Title:%s*([^\n]*)") or ""))
    local mc = src:find("Markdown Content:\n", 1, true)
    if mc and mc < 1500 then pos = mc + #"Markdown Content:\n" end
    local warn = head:match("\nWarning:%s*([^\n]*)")
    if warn then
      B.gap()
      B.run("⚠ " .. warn, "dim")
      B.push()
    end
  end

  local function linkItem(href)
    return B.addItem({kind = "link", href = HTTP.join(base, href)})
  end

  local inline
  inline = function(text)
    local i, len = 1, #text
    while i <= len do
      local s = text:find("[%[!%*`]", i)
      if not s then
        B.text(text:sub(i))
        break
      end
      if s > i then B.text(text:sub(i, s - 1)) end
      local c = text:sub(s, s)
      local consumed = false
      if c == "`" then
        local e2 = text:find("`", s + 1, true)
        if e2 then
          ctx.code = ctx.code + 1
          B.text(text:sub(s + 1, e2 - 1))
          ctx.code = ctx.code - 1
          i, consumed = e2 + 1, true
        end
      elseif c == "*" then
        local dbl = text:sub(s, s + 1) == "**"
        local mark = dbl and "**" or "*"
        local e2 = text:find(mark, s + #mark, true)
        if e2 and e2 > s + #mark then
          if dbl then ctx.bold = ctx.bold + 1 else ctx.italic = ctx.italic + 1 end
          inline(text:sub(s + #mark, e2 - 1))
          if dbl then ctx.bold = ctx.bold - 1 else ctx.italic = ctx.italic - 1 end
          i, consumed = e2 + #mark, true
        end
      elseif c == "[" then
        local st, en, alt, _, href = text:find("^%[!%[([^%]]*)%]%(([^%)]*)%)%]%(([^%s%)]*)[^%)]*%)", s)
        if st then
          local old = ctx.link
          if href ~= "" then ctx.link = linkItem(href) end
          B.text("[" .. (alt ~= "" and alt or "img") .. "]")
          ctx.link = old
          i, consumed = en + 1, true
        else
          local st2, en2, label, href2 = text:find("^%[([^%]]*)%]%(([^%s%)]*)[^%)]*%)", s)
          if st2 then
            if href2 ~= "" and not href2:match("^[jJ]avascript:") then
              local old = ctx.link
              ctx.link = linkItem(href2)
              inline(label ~= "" and label or href2)
              ctx.link = old
            else
              inline(label)
            end
            i, consumed = en2 + 1, true
          end
        end
      else -- «!»
        local st3, en3, alt3, img3 = text:find("^!%[([^%]]*)%]%(([^%s%)]*)[^%)]*%)", s)
        if st3 then
          local label = "[" .. (alt3 ~= "" and alt3 or "img") .. "]"
          if img3 ~= "" and not img3:match("^data:") then
            B.run(label, "img", linkItem(img3))
          else
            B.run(label, "dim")
          end
          i, consumed = en3 + 1, true
        end
      end
      if not consumed then
        B.text(c)
        i = s + 1
      end
    end
  end

  local inFence, prevList = false, false
  local count = 0
  for line in src:sub(pos):gmatch("([^\n]*)\n?") do
    count = count + 1
    if count % 40 == 0 then checkpoint() end
    if line:match("^%s*```") then
      B.push()
      if inFence then
        ctx.pre = 0
        B.gap()
      else
        B.gap()
        ctx.pre = 1
        B.new("pre")
      end
      inFence, prevList = not inFence, false
    elseif inFence then
      B.text(line .. "\n")
    elseif line:match("^%s*$") then
      B.push()
      B.gap()
      prevList = false
    else
      local hashes, htext = line:match("^(#+)%s+(.-)%s*#*%s*$")
      local lsp, lmark, ltext = line:match("^(%s*)([%*%-%+])%s+(.*)$")
      local nsp, num, ntext = line:match("^(%s*)(%d+)[%.%)]%s+(.*)$")
      if hashes then
        local h = "h" .. min(#hashes, 6)
        B.push()
        B.gap()
        B.new(h)
        ctx.head = h
        inline(htext)
        B.push()
        ctx.head = nil
        B.gap()
        prevList = false
      elseif line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$") or line:match("^%s*___+%s*$") then
        B.rule()
        prevList = false
      elseif lmark or num then
        local depth = min(4, math.floor(#(lsp or nsp) / 3))
        B.push()
        if not prevList then B.gap() end
        ctx.indent = 3 * (depth + 1)
        local blk = B.new("li")
        blk.prefix = lmark and (depth > 0 and "◦ " or "• ") or (num .. ". ")
        inline(lmark and ltext or ntext)
        B.push()
        ctx.indent = 0
        prevList = true
      elseif line:match("^%s*>") then
        local qtext = line:match("^%s*>%s?(.*)$")
        B.push()
        ctx.indent, ctx.bar = 2, 1
        B.new("p")
        inline(qtext)
        B.push()
        ctx.indent, ctx.bar = 0, 0
        prevList = false
      elseif line:match("^%s*|") then
        if not line:match("^[%s|:%-]+$") then
          B.push()
          B.new("p")
          inline((line:gsub("^%s*|", ""):gsub("|%s*$", ""):gsub("|", " │ ")))
          B.push()
        end
        prevList = false
      else
        local c = B.current()
        if hard then
          B.push()
          B.new("p")
        elseif c and c.kind == "p" then
          B.text(" ")
        else
          B.push()
          B.gap()
          B.new("p")
        end
        inline(line)
        prevList = false
      end
    end
  end
  B.push()
  return doc
end

-- ---------- вёрстка
--- Ширина виджета формы в ячейках
function HTML.fieldWidth(f)
  local k = f.kind
  if k == "checkbox" or k == "radio" then return 3 end
  if k == "submit" then return ulen(f.label or "OK") + 2 end
  if k == "select" then
    local w = 0
    for _, o in ipairs(f.options) do w = max(w, ulen(o.label)) end
    return min(32, w + 4)
  end
  return min(40, max(10, f.size or 24))
end

--- Документ → строки. Каждая строка — плоский массив по 4 значения на фрагмент:
---   x (колонка), текст или поле формы, стиль, номер элемента (ссылка/поле) либо false.
--- Дополнительно у строки могут быть: rule/ch (линия), blank, bar, pfx/pfxX (маркер списка), bg (колонка начала фона).
function HTML.layout(doc, width)
  width = max(20, width)
  local lines, itemLine, blockLine = {}, {}, {}
  local MAXLINES = 9000
  local cur, x, indent, avail, block, firstLine
  local pend, pendStyle, pendItem, pendX

  local function flush()
    if pend then
      local n = #cur
      cur[n + 1], cur[n + 2], cur[n + 3], cur[n + 4] = pendX, table.concat(pend), pendStyle, pendItem
      pend = nil
    end
  end

  local function newLine()
    flush()
    local ln = {}
    if block.pre then ln.bg = indent end
    if block.bar then ln.bar = max(0, indent - 2) end
    lines[#lines + 1] = ln
    cur, x = ln, indent
    if not firstLine then
      firstLine = true
      if block.prefix then
        ln.pfx = block.prefix
        ln.pfxX = max(0, indent - ulen(block.prefix))
      end
    end
  end

  local function put(text, sp, style, item)
    item = item or false
    if sp then
      if pend and pendStyle == style and pendItem == item then
        pend[#pend + 1] = " "
        x = x + 1
      else
        flush()
        local n = #cur
        cur[n + 1], cur[n + 2], cur[n + 3], cur[n + 4] = x, " ", "plain", false
        x = x + 1
      end
    end
    if pend and (pendStyle ~= style or pendItem ~= item) then flush() end
    if not pend then
      pend, pendStyle, pendItem, pendX = {}, style, item, x
    end
    pend[#pend + 1] = text
    x = x + ulen(text)
    if item and not itemLine[item] then itemLine[item] = #lines end
  end

  local function addWord(word, sp, style, item)
    local wl = ulen(word)
    if not cur then newLine() end
    local used = x - indent
    if used > 0 and used + (sp and 1 or 0) + wl > avail then
      newLine()
      sp, used = false, 0
    end
    if sp and used == 0 then sp = false end
    while wl > avail - used do
      local take = avail - used
      put(usub(word, 1, take), sp, style, item)
      word = usub(word, take + 1)
      wl = wl - take
      newLine()
      sp, used = false, 0
    end
    put(word, sp, style, item)
  end

  local function putField(f, item)
    if not cur then newLine() end
    local fw = min(HTML.fieldWidth(f), avail)
    f.w = fw
    local used = x - indent
    if used > 0 and used + 1 + fw > avail then
      newLine()
      used = 0
    end
    flush()
    local sx = used > 0 and (x + 1) or x
    local n = #cur
    cur[n + 1], cur[n + 2], cur[n + 3], cur[n + 4] = sx, f, "field", item
    x = sx + fw
    if not itemLine[item] then itemLine[item] = #lines end
  end

  local blocks = doc.blocks
  for bi = 1, #blocks do
    block = blocks[bi]
    blockLine[bi] = #lines + 1
    if block.gap and #lines > 0 and not lines[#lines].blank then lines[#lines + 1] = {blank = true} end
    if block.rule then
      lines[#lines + 1] = {rule = true, x = block.indent}
    else
      indent = block.indent
      avail = max(8, width - indent)
      cur, firstLine, pend = nil, false, nil
      local spPending = false
      local startIdx = #lines + 1
      for _, run in ipairs(block.runs) do
        if run.br then
          newLine()
          spPending = false
        elseif run.f then
          putField(run.f, run.i)
          spPending = true
        elseif block.pre then
          local idx = 0
          for piece in (run.t .. "\n"):gmatch("(.-)\n") do
            idx = idx + 1
            if idx > 1 or not cur then newLine() end
            local pl = ulen(piece)
            while pl > avail do
              put(usub(piece, 1, avail), false, run.s, run.i)
              piece = usub(piece, avail + 1)
              pl = pl - avail
              newLine()
            end
            if pl > 0 then put(piece, false, run.s, run.i) end
            if idx % 64 == 0 then checkpoint() end
          end
        else
          local t = run.t
          for space, word in t:gmatch("(%s*)(%S+)") do
            addWord(word, spPending or space ~= "", run.s, run.i)
            spPending = false
          end
          if t:find("%s$") then spPending = true end
        end
      end
      if cur then flush() end
      while #lines >= startIdx do
        local last = lines[#lines]
        if #last == 0 and not last.pfx and not last.rule and not last.blank then lines[#lines] = nil else break end
      end
      if (block.kind == "h1" or block.kind == "h2") and #lines >= startIdx then
        lines[#lines + 1] = {rule = true, x = indent, ch = block.kind == "h1" and "═" or "─"}
      end
    end
    if #lines > MAXLINES then break end
    if bi % 12 == 0 then checkpoint() end
  end

  while #lines > 0 and lines[#lines].blank do lines[#lines] = nil end
  local anchorLine = {}
  for id, bi in pairs(doc.anchors) do anchorLine[id] = blockLine[bi] or #lines end
  return {lines = lines, itemLine = itemLine, anchorLine = anchorLine, width = width}
end

return HTML
]=]},
  {"/Libraries/HTTP.lua", [[
-- ----------
--  CubeOS :: HTTP
--  Надёжная обёртка над Internet Card.
--
--  Три уровня API:
--   • HTTP.request(url, body, headers, method, opts)  — блокирующий, простой (RYKEA)
--       успех:  тело (строка), код ответа
--       ошибка: nil, текст ошибки, код (если был)
--   • HTTP.fetch(url, opts)  — блокирующий, сам идёт по редиректам (wget, curl)
--       возвращает таблицу {ok, body, code, headers, url, error, truncated}
--   • HTTP.start(...)  — НЕблокирующий запрос: объект с :poll() / :cancel() / :result()
--       его опрашивают из onTick окна — интерфейс не замирает (браузер, загрузки)
--
--  Плюс разбор и склейка URL: parseUrl, join, urlencode, urldecode, queryParam.
-- ----------
local component, computer = component, computer
local floor = math.floor
local clock = os.clock or computer.uptime

local HTTP = {}

HTTP.log = {} -- последние запросы: {method, host, path, code, bytes, time, err}
local LOG_MAX = 14

local function addLog(entry)
  table.insert(HTTP.log, 1, entry)
  while #HTTP.log > LOG_MAX do HTTP.log[#HTTP.log] = nil end
end

HTTP.USER_AGENT = "Mozilla/5.0 (compatible; CubeOS/1.2; OpenComputers)"

--- Заголовки «как у браузера»
function HTTP.browserHeaders(extra)
  local h = {
    ["User-Agent"] = HTTP.USER_AGENT,
    ["Accept"] = "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5",
    ["Accept-Language"] = "ru,en;q=0.8",
  }
  for k, v in pairs(extra or {}) do h[k] = v end
  return h
end

function HTTP.available()
  return component.list("internet")() ~= nil
end

function HTTP.card()
  local address = component.list("internet")()
  if not address then return nil end
  return component.proxy(address)
end

--- Проверка, что запросы вообще возможны. → true  либо  false, причина
function HTTP.check()
  local card = HTTP.card()
  if not card then return false, "Не найдена Internet Card" end
  if card.isHttpEnabled then
    local ok, enabled = pcall(card.isHttpEnabled)
    if ok and enabled == false then
      return false, "HTTP-запросы выключены в конфиге OpenComputers (internet.enableHttp)"
    end
  end
  return true
end

-- ---------- URL
function HTTP.urlencode(s, plus)
  s = tostring(s):gsub("[^%w%-_%.~ ]", function(c) return string.format("%%%02X", c:byte()) end)
  if plus then return (s:gsub(" ", "+")) end
  return (s:gsub(" ", "%%20"))
end

function HTTP.urldecode(s)
  s = tostring(s):gsub("+", " ")
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

--- Разбор URL → {scheme, host, authority, path, query ("?a=b" или ""), fragment}
function HTTP.parseUrl(u)
  u = tostring(u)
  local scheme, rest = u:match("^(%a[%w+.-]*):(.*)$")
  if not scheme then return nil end
  local authority, path = "", rest
  if rest:sub(1, 2) == "//" then authority, path = rest:match("^//([^/?#]*)(.*)$") end
  local pathOnly = path:match("^[^?#]*")
  local query = path:match("^[^#]*"):sub(#pathOnly + 1)
  local fragment = path:match("#(.*)$")
  local host = authority:gsub("^.*@", ""):gsub(":%d+$", ""):lower()
  return {scheme = scheme:lower(), host = host, authority = authority, path = pathOnly, query = query, fragment = fragment}
end

function HTTP.hostOf(u)
  local p = HTTP.parseUrl(u)
  return p and p.host or ""
end

--- Значение параметра запроса (раскодированное) или nil
function HTTP.queryParam(u, name)
  local p = HTTP.parseUrl(u)
  if not p then return nil end
  for pair in p.query:sub(2):gmatch("[^&]+") do
    local k, v = pair:match("^([^=]*)=?(.*)$")
    if HTTP.urldecode(k) == name then return HTTP.urldecode(v) end
  end
end

local function removeDots(path)
  local parts = {}
  local trailing = path:sub(-1) == "/" or path:match("/%.%.?$") ~= nil
  for seg in path:gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  local r = "/" .. table.concat(parts, "/")
  if trailing and r:sub(-1) ~= "/" then r = r .. "/" end
  return r
end

--- Склейка относительной ссылки с базовым адресом (как в браузере)
function HTTP.join(base, ref)
  ref = tostring(ref):match("^%s*(.-)%s*$")
  if ref == "" then return base end
  if ref:match("^%a[%w+.-]*:") then return ref end
  local b = HTTP.parseUrl(base)
  if not b then return ref end
  local origin = b.scheme .. "://" .. b.authority
  if ref:sub(1, 2) == "//" then return b.scheme .. ":" .. ref end
  local first = ref:sub(1, 1)
  if first == "#" then return origin .. b.path .. b.query .. ref end
  if first == "?" then return origin .. (b.path == "" and "/" or b.path) .. ref end
  local refPath, tail = ref:match("^([^?#]*)(.*)$")
  if first == "/" then return origin .. removeDots(refPath) .. tail end
  local dir = b.path:match("^(.*/)") or "/"
  return origin .. removeDots(dir .. refPath) .. tail
end

-- ---------- тексты ошибок
--- Достаём человекочитаемое сообщение из тела ошибки (PostgREST/Supabase)
local function errorText(body)
  if type(body) ~= "string" or body == "" then return nil end
  local msg = body:match('"message"%s*:%s*"(.-)"')
    or body:match('"error_description"%s*:%s*"(.-)"')
    or body:match('"error"%s*:%s*"(.-)"')
  if msg then return msg end
  return (body:sub(1, 100):gsub("%s+", " "))
end

--- Подсказка пользователю по тексту ошибки
function HTTP.hint(err)
  err = tostring(err or ""):lower()
  if err:find("internet card", 1, true) then
    return "Установите Internet Card в компьютер и перезапустите приложение."
  elseif err:find("выключен в эмуляторе", 1, true) then
    return "Включите интернет кнопкой «Интернет» над экраном эмулятора."
  elseif err:find("cors", 1, true) then
    return "Это ограничение веб-эмулятора (сайт закрыт для браузера). В Minecraft через Internet Card такой проблемы нет."
  elseif err:find("enablehttp", 1, true) or err:find("выключены", 1, true) then
    return "В файле конфигурации OpenComputers включите internet.enableHttp = true."
  elseif err:find("not enough memory", 1, true) or err:find("слишком большой", 1, true) or err:find("memory", 1, true) then
    return "Не хватает ОЗУ. Уменьшите разрешение экрана (Настройки → Экран) и закройте лишние окна."
  elseif err:find("401", 1, true) or err:find("invalid api key", 1, true) or err:find("jwt", 1, true) then
    return "Сервер не принял ключ. Проверьте anon_key в /Applications/RYKEA.app/Config.lua."
  elseif err:find("404", 1, true) then
    return "Такой страницы или таблицы нет. Проверьте адрес."
  elseif err:find("unknownhost", 1, true) or err:find("unknown host", 1, true) or err:find("resolve", 1, true) or err:find("nodename", 1, true) then
    return "Не удалось найти сервер: проверьте адрес, DNS и интернет на сервере Minecraft."
  elseif err:find("not allowed", 1, true) or err:find("address is not", 1, true) then
    return "Сервер запрещает этот адрес: проверьте настройки доступа к интернету в конфиге OpenComputers."
  elseif err:find("pkix", 1, true) or err:find("ssl", 1, true) or err:find("certificate", 1, true) or err:find("handshake", 1, true) then
    return "Java на сервере не доверяет сертификату. Обновите Java до 8u101 или новее."
  elseif err:find("esc", 1, true) or err:find("отменено", 1, true) then
    return "Загрузка отменена вами."
  elseif err:find("время", 1, true) or err:find("не отвечает", 1, true) or err:find("timed out", 1, true) then
    return "Сервер слишком долго отвечает. Проверьте связь и повторите."
  end
  return "Повторите попытку. Если не помогает — откройте «Сеть» в RYKEA и сообщите текст ошибки."
end

-- ---------- неблокирующий запрос
local function normalizeHeaders(h)
  local out = {}
  if type(h) == "table" then
    for k, v in pairs(h) do
      if type(k) == "string" then
        if type(v) == "table" then v = v[1] end
        if v ~= nil then out[k:lower()] = tostring(v) end
      end
    end
  end
  return out
end

local Req = {}
Req.__index = Req

--- Читаем кусок ответа. В разных версиях OpenComputers read() по-разному относится к аргументу.
local function readChunk(self)
  local handle = self.handle
  if self.readNoArg then return pcall(handle.read) end
  local ok, a, b = pcall(handle.read, math.huge)
  if not ok then
    self.readNoArg = true
    return pcall(handle.read)
  end
  return ok, a, b
end

--- opts: timeout (с), idleTimeout (с), maxBytes, truncate (обрезать, а не ошибаться),
---       sink(chunk) — отдавать данные сюда (запись в файл), а не копить в памяти
--- → объект запроса  либо  nil, причина
function HTTP.start(url, body, headers, method, opts)
  opts = opts or {}
  local verb = method or (body and "POST" or "GET")
  local p = HTTP.parseUrl(url) or {host = "", path = tostring(url), query = ""}
  local function fail(reason)
    addLog({method = verb, host = p.host, path = (p.path .. p.query):sub(1, 90), bytes = 0, time = 0, err = reason})
    return nil, reason
  end
  local card = HTTP.card()
  if not card then return fail("Не найдена Internet Card") end
  local okCheck, why = HTTP.check()
  if not okCheck then return fail(why) end
  local ok, handle, reason = pcall(card.request, url, body, headers, method)
  if not ok then return fail(tostring(handle)) end
  if not handle then return fail(tostring(reason or "запрос отклонён")) end
  local now = computer.uptime()
  return setmetatable({
    handle = handle, url = url, method = verb, host = p.host, path = (p.path .. p.query):sub(1, 90),
    chunks = {}, total = 0, started = now, lastData = now,
    timeout = opts.timeout or 20, idle = opts.idleTimeout or 12, maxBytes = opts.maxBytes or 98304,
    truncate = opts.truncate, sinkFn = opts.sink, done = false,
  }, Req)
end

function Req:readHeaders()
  if self.code or not self.handle or not self.handle.response then return end
  local ok, code, msg, headers = pcall(self.handle.response)
  if ok and type(code) == "number" then
    self.code, self.message = code, msg
    self.headers = normalizeHeaders(headers)
  end
end

function Req:finish(failure)
  if self.done then return true end
  self.done = true
  if not failure then self:readHeaders() end
  pcall(self.handle.close)
  self.failure = failure
  if self.chunks then
    local data = table.concat(self.chunks)
    self.chunks = nil
    if self.truncated and #data > self.maxBytes then data = data:sub(1, self.maxBytes) end
    self.data = data
  end
  self.elapsed = computer.uptime() - self.started
  addLog({method = self.method, host = self.host, path = self.path, code = self.code, bytes = self.total, time = self.elapsed, err = failure})
  return true
end

--- Подключить приёмник данных «на ходу» (уже полученное — сразу туда)
function Req:setSink(fn)
  if self.chunks then
    for _, c in ipairs(self.chunks) do fn(c) end
    self.chunks = nil
  end
  self.sinkFn = fn
end

function Req:cancel(reason)
  return self:finish(reason or "отменено")
end

--- Один шаг. → done (запрос завершён), waiting (данных пока нет — можно поспать)
function Req:poll(budget)
  if self.done then return true, false end
  local t0 = clock()
  budget = budget or 0.05
  while true do
    if not self.code then self:readHeaders() end
    local okRead, chunk, err = readChunk(self)
    if not okRead then return self:finish(tostring(chunk)), false end
    if chunk == nil then
      if err then return self:finish(tostring(err)), false end
      return self:finish(nil), false
    end
    local now = computer.uptime()
    if #chunk > 0 then
      self.total = self.total + #chunk
      self.lastData = now
      if self.sinkFn then
        -- тела редиректов в файл не пишем
        local redirect = self.code and self.code >= 300 and self.code < 400 and self.code ~= 304
        if not redirect then self.sinkFn(chunk) end
      elseif self.chunks then
        self.chunks[#self.chunks + 1] = chunk
        if self.total > self.maxBytes then
          if self.truncate then
            self.truncated = true
            return self:finish(nil), false
          end
          return self:finish(string.format("ответ слишком большой (больше %d КБ) — не хватит памяти", floor(self.maxBytes / 1024))), false
        end
      end
      if clock() - t0 > budget then return false, false end
    else
      if now - self.started > self.timeout then
        return self:finish("превышено время ожидания (" .. tostring(self.timeout) .. " с)"), false
      end
      if now - self.lastData > self.idle then return self:finish("сервер не отвечает"), false end
      return false, true
    end
  end
end

function Req:result()
  return {
    ok = self.failure == nil, error = self.failure, code = self.code, message = self.message,
    headers = self.headers or {}, body = self.data, truncated = self.truncated,
    bytes = self.total, elapsed = self.elapsed, url = self.url,
  }
end

-- ---------- блокирующие обёртки
local function waitFor(req, opts)
  while true do
    local done, waiting = req:poll(0.05)
    if done then return end
    if opts.progress then opts.progress(computer.uptime() - req.started, req.total) end
    local name, _, _, code = computer.pullSignal(waiting and 0.05 or 0)
    if name == "key_down" and code == 1 then
      req:cancel("отменено (Esc)")
      return
    end
  end
end

--- Блокирующий запрос (без редиректов). opts: timeout, maxBytes, retries, progress(elapsed, bytes)
function HTTP.request(url, body, headers, method, opts)
  opts = opts or {}
  local retries = opts.retries or 1
  local data, err, code
  for try = 1, retries + 1 do
    local req, startErr = HTTP.start(url, body, headers, method, opts)
    if not req then
      data, err, code = nil, startErr, nil
      break
    end
    waitFor(req, opts)
    local res = req:result()
    code = res.code
    if res.ok then
      if code and code >= 400 then
        local msg = errorText(res.body)
        data, err = nil, "HTTP " .. code .. (msg and (": " .. msg) or "")
      else
        data, err = res.body or "", nil
      end
    else
      data, err = nil, res.error
    end
    -- повторяем только сбои сети и ошибки сервера (5xx), но не отказы и не отмену
    local final = data ~= nil
      or (code and code < 500)
      or (err and (err:find("Esc", 1, true) or err:find("слишком большой", 1, true)))
    if final then break end
    if try <= retries then computer.pullSignal(0.4) end
  end
  if data then return data, code end
  return nil, err, code
end

HTTP.MAX_REDIRECTS = 8

--- Блокирующая загрузка с переходом по редиректам.
--- opts: method, body, headers, timeout, maxBytes, truncate, sink, progress
function HTTP.fetch(url, opts)
  opts = opts or {}
  local method, body = opts.method, opts.body
  local headers = opts.headers or HTTP.browserHeaders()
  for _ = 0, HTTP.MAX_REDIRECTS do
    local req, err = HTTP.start(url, body, headers, method, opts)
    if not req then return {ok = false, error = err, url = url, headers = {}} end
    waitFor(req, opts)
    local res = req:result()
    res.url = url
    local loc = res.ok and res.headers.location
    if loc and res.code and res.code >= 300 and res.code < 400 and res.code ~= 304 then
      url = HTTP.join(url, loc)
      if res.code ~= 307 and res.code ~= 308 then method, body = nil, nil end
    else
      return res
    end
  end
  return {ok = false, error = "слишком много перенаправлений", url = url, headers = {}}
end

function HTTP.get(url, headers, opts)
  return HTTP.request(url, nil, headers, "GET", opts)
end

return HTTP
]]},
  {"/Libraries/JSON.lua", [[
-- ----------
--  CubeOS :: JSON
--  Полноценный кодировщик/декодировщик (в т.ч. \uXXXX и суррогаты)
-- ----------
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

-- ---------- декодер
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
  {"/Libraries/Screen.lua", [[
-- ----------
--  CubeOS :: Screen
--  Двойная буферизация поверх GPU. Рисуем всё в память, а на
--  экран отправляем только изменившиеся ячейки, сгруппированные
--  по цветам (меньше вызовов gpu.set — быстрее и экономнее).
--
--  Экономия ОЗУ: фон и цвет текста упакованы в одно число
--  (bg * 2^24 + fg), поэтому буфер занимает 4 массива вместо 6.
--  Используется арифметика с плавающей точкой (точна до 53 бит), а не
--  побитовые операции — так код одинаково работает и на 64-битном Lua
--  OpenComputers, и на 32-битных целых эмулятора.
--  Это ~64 байта на ячейку: 160×50 → ~500 КБ, 100×32 → ~200 КБ.
-- ----------
local floor = math.floor

local Screen = {}

local SHIFT = 16777216.0
local toint = math.tointeger or function(x) return x end
local gpu, W, H = nil, 0, 0
local curPack, curCh = {}, {} -- что сейчас на мониторе
local newPack, newCh = {}, {} -- что должно быть
local dirty = {}
local clipStack = {}
local cx1, cy1, cx2, cy2 = 1, 1, 0, 0
local runBuf = {}

--- Смешивание цветов: top поверх bottom с непрозрачностью a (0..1)
function Screen.blend(top, bottom, a)
  if a >= 1 then return top elseif a <= 0 then return bottom end
  local tr, tg, tb = floor(top / 65536) % 256, floor(top / 256) % 256, top % 256
  local br, bg, bb = floor(bottom / 65536) % 256, floor(bottom / 256) % 256, bottom % 256
  local b = 1 - a
  return floor(tr * a + br * b + 0.5) * 65536 + floor(tg * a + bg * b + 0.5) * 256 + floor(tb * a + bb * b + 0.5)
end
local blend = Screen.blend

--- Сколько байт ОЗУ займут буферы такого размера
function Screen.cost(w, h) return w * h * 64 end

function Screen.init(gpuProxy, w, h)
  gpu, W, H = gpuProxy, w, h
  curPack, curCh, newPack, newCh, dirty = {}, {}, {}, {}, {}
  for i = 1, w * h do
    curPack[i], curCh[i] = -1, "" -- заведомо отличается → полная перерисовка
    newPack[i], newCh[i] = 0, " "
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
  for i = 1, W * H do curPack[i] = -1 end
  for y = 1, H do dirty[y] = true end
end

--- Сохранить текущий кадр (обои и значки рабочего стола) в отдельный слой.
function Screen.snapshot(dstPack, dstCh)
  local n = W * H
  if #dstPack ~= n then
    for i = #dstPack + 1, n do dstPack[i], dstCh[i] = 0, " " end
    for i = n + 1, #dstPack do dstPack[i], dstCh[i] = nil, nil end
  end
  for i = 1, n do dstPack[i] = newPack[i] dstCh[i] = newCh[i] end
end

--- Подставить сохранённый слой вместо пересчёта фона.
--- Ячейка записывается и строка помечается на обновление только если содержимое
--- действительно отличается — пустой кадр не приводит ни к одной команде на GPU.
function Screen.restore(srcPack, srcCh)
  local n = W * H
  if not srcPack or #srcPack < n then return false end
  for y = 1, H do
    local base = (y - 1) * W
    local touched = false
    for x = 1, W do
      local i = base + x
      local p, c = srcPack[i], srcCh[i]
      if newPack[i] ~= p or newCh[i] ~= c then
        newPack[i], newCh[i] = p, c
        if curPack[i] ~= p or curCh[i] ~= c then touched = true end
      end
    end
    if touched then dirty[y] = true end
  end
  return true
end

-- ---------- области отсечения
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

-- ---------- примитивы
--- Установить одну ячейку. nil вместо цвета/символа — оставить как есть.
function Screen.set(x, y, bg, fg, ch)
  if x < cx1 or x > cx2 or y < cy1 or y > cy2 then return end
  local i = (y - 1) * W + x
  local p = newPack[i]
  local oldCh = newCh[i]
  local f = p % SHIFT
  local b = (p - f) / SHIFT
  if bg then b = bg end
  if ch then newCh[i] = ch end
  if newCh[i] == " " then f = b elseif fg then f = fg end
  local np = b * SHIFT + f
  if np ~= p or newCh[i] ~= oldCh then
    newPack[i] = np
    dirty[y] = true
  end
end

function Screen.get(x, y)
  if x < 1 or x > W or y < 1 or y > H then return 0, 0, " " end
  local i = (y - 1) * W + x
  local p = newPack[i]
  local f = p % SHIFT
  return (p - f) / SHIFT, f, newCh[i]
end

--- Прямоугольник. alpha < 1 — полупрозрачная заливка (затемнение, тени).
function Screen.rect(x, y, w, h, bg, fg, ch, alpha)
  bg = bg or 0
  local x1, y1 = x > cx1 and x or cx1, y > cy1 and y or cy1
  local x2, y2 = x + w - 1, y + h - 1
  if x2 > cx2 then x2 = cx2 end
  if y2 > cy2 then y2 = cy2 end
  if x1 > x2 or y1 > y2 then return end
  if alpha and alpha < 1 then
    for yy = y1, y2 do
      local base = (yy - 1) * W
      local touched = false
      for xx = x1, x2 do
        local i = base + xx
        local p = newPack[i]
        local f = p % SHIFT
        local np = blend(bg, (p - f) / SHIFT, alpha) * SHIFT + blend(bg, f, alpha)
        local oldCh = newCh[i]
        if p ~= np or (ch and oldCh ~= ch) then
          if ch then newCh[i] = ch end
          newPack[i] = np
          touched = true
        end
      end
      if touched then dirty[yy] = true end
    end
    return
  end
  ch = ch or " "
  local solid = bg * SHIFT + bg
  for yy = y1, y2 do
    local base = (yy - 1) * W
    local touched = false
    if ch == " " then
      for xx = x1, x2 do
        local i = base + xx
        if newPack[i] ~= solid or newCh[i] ~= " " then
          newPack[i], newCh[i] = solid, " "
          touched = true
        end
      end
    else
      for xx = x1, x2 do
        local i = base + xx
        local p = newPack[i]
        local np = bg * SHIFT + (fg or (p % SHIFT))
        if p ~= np or newCh[i] ~= ch then
          newCh[i] = ch
          newPack[i] = np
          touched = true
        end
      end
    end
    if touched then dirty[yy] = true end
  end
end

--- Текст. Если bg не задан — сохраняется фон под буквами.
--- Поставить один символ в строку и вернуть true, если ячейка изменилась.
local function putChar(base, xx, ch, fg, bg)
  local j = base + xx
  local b = bg
  if not b then
    local p = newPack[j]
    b = (p - p % SHIFT) / SHIFT
  end
  local np = b * SHIFT + (ch == " " and b or fg)
  if newCh[j] ~= ch or newPack[j] ~= np then
    newCh[j], newPack[j] = ch, np
    return true
  end
  return false
end

--- Текст без фона сохраняет текущий фон. Строка помечается на вывод
--- только если хотя бы одна ячейка реально изменилась.
function Screen.text(x, y, fg, str, bg)
  if y < cy1 or y > cy2 then return end
  fg = fg or 0xFFFFFF
  str = tostring(str)
  local base = (y - 1) * W
  local touched = false
  if not str:find("[\128-\255]") then
    -- ASCII: не разбираем многобайтовые последовательности (обычный случай)
    local i, n = 1, #str
    while i <= n do
      if x > cx2 then break end
      if x >= cx1 and putChar(base, x, str:sub(i, i), fg, bg) then touched = true end
      x, i = x + 1, i + 1
    end
  else
    for ch in str:gmatch("[\0-\127\194-\244][\128-\191]*") do
      if x > cx2 then break end
      if x >= cx1 and putChar(base, x, ch, fg, bg) then touched = true end
      x = x + 1
    end
  end
  if touched then dirty[y] = true end
end

function Screen.clear(bg)
  Screen.rect(1, 1, W, H, bg or 0, nil, " ")
end

-- ---------- вывод на монитор
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
        local pk, ch = newPack[i], newCh[i]
        if pk ~= curPack[i] or ch ~= curCh[i] then
          local startX = x
          local n = 1
          runBuf[1] = ch
          curPack[i], curCh[i] = pk, ch
          x = x + 1
          while x <= W do
            local j = base + x
            local c = newCh[j]
            if newPack[j] == pk and (pk ~= curPack[j] or c ~= curCh[j]) then
              n = n + 1
              runBuf[n] = c
              curPack[j], curCh[j] = pk, c
              x = x + 1
            else
              break
            end
          end
          local fg = pk % SHIFT
          local bg = toint((pk - fg) / SHIFT)
          fg = toint(fg)
          if bg ~= gBg then gpu.setBackground(bg) gBg = bg end
          if fg ~= gFg then gpu.setForeground(fg) gFg = fg end
          if n == 1 then gpu.set(startX, y, runBuf[1]) else gpu.set(startX, y, concat(runBuf, "", 1, n)) end
        else
          x = x + 1
        end
      end
    end
  end
end

return Screen
]]},
  {"/Libraries/System.lua", [[
-- ----------
--  CubeOS :: System
--  Файловая система, пути, настройки, время, список приложений.
-- ----------
local component, computer, unicode = component, computer, unicode

local System = {}
System.name = "CubeOS"
System.version = "7.2"
System.build = "Tier 2 lite"

local bootAddress = computer.getBootAddress()
local fs = component.proxy(bootAddress)
System.fs = fs
System.bootAddress = bootAddress

-- ---------- пути
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

-- ---------- файлы
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

function System.formatSize(bytes)
  bytes = bytes or 0
  if bytes < 1024 then return bytes .. " Б" end
  if bytes < 1024 * 1024 then return string.format("%.1f КБ", bytes / 1024) end
  return string.format("%.2f МБ", bytes / 1024 / 1024)
end

-- ---------- сериализация
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
  str = tostring(str or "")
  local fn = load("return " .. str, "=data", "t", {})
  if not fn then
    fn = load(str, "=data", "t", {})
  end
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

-- ---------- настройки
System.settingsPath = "/Users/Settings.cfg"
local defaults = {
  theme = "light", sysmode = "aero", accent = 1, wallpaper = 1, timezone = 3, username = "Игрок", ver = 2,
  effects = "auto", -- "auto" (по железу), "on", "off"
  pinned = {"Browser", "Finder", "Store", "RYKEA"},
  tiles = {"Browser", "Finder", "Store", "RYKEA", "Settings", "Calculator"},
}

local function copyValue(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copyValue(x) end
  return t
end

function System.loadSettings()
  local s = {}
  for k, v in pairs(defaults) do s[k] = copyValue(v) end
  -- в безопасном режиме (прошлая загрузка оборвалась) настройки не читаем
  local data = (not SAFE_MODE) and System.readFile(System.settingsPath) or nil
  if data then
    local t = System.unserialize(data)
    if type(t) == "table" then
      -- настройки старого образца (до Windows-стиля): внешний вид сбрасываем, остальное сохраняем
      if t.ver ~= 2 then t.theme, t.accent, t.wallpaper, t.sysmode, t.ver = nil, nil, nil, nil, 2 end
      for k, v in pairs(t) do s[k] = v end
    end
  end
  System.settings = s
  return s
end

function System.saveSettings()
  System.writeFile(System.settingsPath, System.serialize(System.settings))
end

function System.resetSettings()
  System.settings = {}
  for k, v in pairs(defaults) do System.settings[k] = copyValue(v) end
  System.saveSettings()
end

System.loadSettings()

-- ---------- время
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

--- Журнал системы: /Users/Logs/system.log (при росте >24 КБ старый уходит в .old)
System.logPath = "/Users/Logs/system.log"
function System.log(message)
  return pcall(function()
    local text = tostring(message):gsub("\n", " | ")
    local line = "[" .. System.date("%d.%m %H:%M:%S") .. "] " .. text .. "\n"
    local size = fs.exists(System.logPath) and fs.size(System.logPath) or 0
    if size > 24 * 1024 then
      fs.remove(System.logPath .. ".old")
      fs.rename(System.logPath, System.logPath .. ".old")
    end
    System.writeFile(System.logPath, line, true)
  end)
end

--- Сборка мусора (в эмуляторе collectgarbage может быть недоступен)
function System.collect()
  pcall(collectgarbage)
  pcall(collectgarbage)
end

function System.freeMemory()
  return computer.freeMemory()
end

function System.memory()
  local total = computer.totalMemory()
  return total - computer.freeMemory(), total
end

function System.uptimeText()
  local s = math.floor(computer.uptime())
  return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

-- ---------- приложения
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

-- ---------- календарь
function System.daysInMonth(y, m)
  if m == 2 then return ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) and 29 or 28 end
  return ({31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31})[m]
end

--- День недели: 0 = понедельник … 6 = воскресенье
function System.weekday(y, m, d)
  local t = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}
  if m < 3 then y = y - 1 end
  local w = (y + y // 4 - y // 100 + y // 400 + t[m] + d) % 7 -- 0 = воскресенье
  return (w + 6) % 7
end

-- ---------- Магазин: установка и удаление приложений
-- Готовые пакеты лежат в /System/Store/<Имя>.app. «Установка» копирует папку в /Applications.
System.STORE = "/System/Store"

function System.dirSize(path)
  local total = 0
  for _, name in ipairs(fs.list(path) or {}) do
    local full = path .. "/" .. name:gsub("/$", "")
    if name:sub(-1) == "/" then total = total + System.dirSize(full) else total = total + (fs.size(full) or 0) end
  end
  return total
end

function System.storeApps()
  local list = {}
  for _, name in ipairs(System.list(System.STORE)) do
    if name:match("%.app/$") then
      local path = System.STORE .. "/" .. name:sub(1, -2)
      local info = System.loadData(path .. "/Info.lua")
      if type(info) == "table" then
        info.path, info.id, info.size = path, name:sub(1, -6), System.dirSize(path)
        list[#list + 1] = info
      end
    end
  end
  table.sort(list, function(a, b) return unicode.lower(a.title or a.id) < unicode.lower(b.title or b.id) end)
  return list
end

function System.isInstalled(id) return fs.exists("/Applications/" .. id .. ".app") end

function System.installedInfo(id)
  return System.loadData("/Applications/" .. id .. ".app/Info.lua")
end

--- Список файлов папки (относительные пути)
local function walk(root, rel, out)
  for _, name in ipairs(fs.list(root .. rel) or {}) do
    local n = name:gsub("/$", "")
    if name:sub(-1) == "/" then walk(root, rel .. "/" .. n, out) else out[#out + 1] = rel .. "/" .. n end
  end
  return out
end

--- Установить приложение из магазина. progress(i, n, name) вызывается после каждого файла.
function System.installApp(id, progress)
  local src = System.STORE .. "/" .. id .. ".app"
  if not fs.isDirectory(src) then return nil, "пакет не найден" end
  local files = walk(src, "", {})
  local need = System.dirSize(src)
  if fs.spaceTotal() - fs.spaceUsed() < need + 2048 then return nil, "недостаточно места на диске" end
  local dst = "/Applications/" .. id .. ".app"
  for i, rel in ipairs(files) do
    local data = System.readFile(src .. rel)
    if not data then return nil, "не удалось прочитать " .. rel end
    local ok, err = System.writeFile(dst .. rel, data)
    if not ok then
      System.remove(dst)
      return nil, tostring(err or "ошибка записи")
    end
    if progress then progress(i, #files, rel:sub(2)) end
  end
  return true
end

--- Установить приложение из облака (добавлено через сайт CubeOS 7).
--- app: {id, title, version, icon, category, desc, author, code=Main.lua}
function System.installRemote(app, progress)
  local id = tostring(app.id or "")
  if not id:match("^[%w_]+$") or #id > 32 then return nil, "недопустимое имя приложения" end
  local code = tostring(app.code or "")
  if #code < 10 or #code > 160 * 1024 then return nil, "некорректный код приложения" end
  if fs.spaceTotal() - fs.spaceUsed() < #code + 4096 then return nil, "недостаточно места на диске" end
  local info = {
    id = id, title = tostring(app.title or id), short = tostring(app.title or id),
    version = tostring(app.version or "1.0"), category = tostring(app.category or "Игры"),
    desc = tostring(app.desc or ""), author = tostring(app.author or "CubeOS Cloud"),
    icon = app.icon, remote = true, order = 90,
  }
  local dst = "/Applications/" .. id .. ".app"
  if progress then progress(1, 2, "Info.lua") end
  local ok, err = System.writeFile(dst .. "/Info.lua", "return " .. System.serialize(info))
  if not ok then System.remove(dst) return nil, tostring(err or "ошибка записи") end
  if progress then progress(2, 2, "Main.lua") end
  ok, err = System.writeFile(dst .. "/Main.lua", code)
  if not ok then System.remove(dst) return nil, tostring(err or "ошибка записи") end
  return true
end

function System.uninstallApp(id)
  local s = System.settings
  for _, key in ipairs({"pinned", "tiles"}) do
    local list = s[key] or {}
    for i = #list, 1, -1 do
      if list[i] == id then table.remove(list, i) end
    end
  end
  System.saveSettings()
  return System.remove("/Applications/" .. id .. ".app")
end

--- Версии вида «1.2» → число для сравнения
function System.versionNumber(v)
  local a, b = tostring(v or "1"):match("^(%d+)%.?(%d*)")
  return (tonumber(a) or 0) * 1000 + (tonumber(b) or 0)
end

-- ---------- пакеты .cpk (обмен приложениями)
-- .cpk — Lua-таблица: {format=1, id="Имя", files={["Info.lua"]="…", ["Main.lua"]="…"}}.
-- Разбирается в «пустом» окружении (без функций), поэтому сам файл ничего выполнить не может.
function System.packApp(appPath)
  appPath = appPath:gsub("/$", "")
  if not fs.isDirectory(appPath) then return nil, "не папка: " .. appPath end
  local id = System.basename(appPath):gsub("%.app$", "")
  local files = {}
  for _, rel in ipairs(walk(appPath, "", {})) do
    files[rel:sub(2)] = System.readFile(appPath .. rel)
  end
  if not files["Info.lua"] or not files["Main.lua"] then return nil, "в приложении нет Info.lua и Main.lua" end
  return System.serialize({format = 1, id = id, files = files})
end

--- Проверить и установить пакет. → id либо nil, ошибка
function System.installPackage(data)
  local pkg = System.unserialize(data)
  if type(pkg) ~= "table" or type(pkg.files) ~= "table" or type(pkg.id) ~= "string" then
    return nil, "это не пакет CubeOS (.cpk)"
  end
  if not pkg.id:match("^[%w_]+$") or #pkg.id > 32 then return nil, "недопустимое имя приложения" end
  if not pkg.files["Info.lua"] or not pkg.files["Main.lua"] then return nil, "в пакете нет Info.lua или Main.lua" end
  local total = 0
  for rel, text in pairs(pkg.files) do
    if type(rel) ~= "string" or type(text) ~= "string" or rel:find("..", 1, true) or rel:sub(1, 1) == "/"
      or not rel:match("^[%w_%-%.]+[%w_%-%./]*$") or #text > 160 * 1024 then
      return nil, "недопустимый файл в пакете: " .. tostring(rel)
    end
    total = total + #text
  end
  if total > 400 * 1024 then return nil, "пакет слишком большой" end
  if fs.spaceTotal() - fs.spaceUsed() < total + 2048 then return nil, "недостаточно места на диске" end
  local dst = "/Applications/" .. pkg.id .. ".app"
  for rel, text in pairs(pkg.files) do
    local ok, err = System.writeFile(dst .. "/" .. rel, text)
    if not ok then
      System.remove(dst)
      return nil, tostring(err or "ошибка записи")
    end
  end
  return pkg.id
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
]]},
  {"/System/Desktop.lua", [[
-- ----------
--  CubeOS :: Desktop  —  оболочка Windows 7 «Aero»
--  Обои Harmony, стеклянная панель задач с круглой кнопкой
--  «Пуск», суперпанель запущенных программ, трей с часами,
--  классическое двухколоночное меню «Пуск» и окна Aero.
-- ----------
local component, computer, unicode = component, computer, unicode
local Screen = require("Screen")
local GUI = require("GUI")
local System = require("System")
local C = GUI.color
local floor, max, min = math.floor, math.max, math.min

local Desktop = {}
GUI.desktop = Desktop

Desktop.windows, Desktop.modals, Desktop.toasts, Desktop.apps = {}, {}, {}, {}
Desktop.history = {}
Desktop.dirty, Desktop.cascade, Desktop.running = true, 0, true
Desktop.mods = {ctrl = false, shift = false, alt = false}

local W, H = 80, 25
local TB = 3                      -- высота панели задач
local gpu
local dragState, resizeState
local preciseScreen
local screenOk = true
local updateFails = 0
local BOOT_FLAG = "/Users/.booting"

-- Не больше ~15 кадров в секунду: событие мыши не должно вызывать полную перерисовку
local RENDER_INTERVAL = 0.065
local INTERACTIVE_INTERVAL = 0.020 -- перетаскивание/изменение размера: ~50 кадров/с
local iconPositions, iconPosDirty = nil, false
local iconDrag = nil
local windowsCache, windowsCacheDirty = nil, true
local function markWindowsDirty() windowsCacheDirty = true Desktop.dirty = true end
-- Кэш слоя рабочего стола (обои + значки)
local bgPack, bgCh, bgValid = nil, nil, false

local overlay
local taskItems = {}
local lastTitle = {t = 0}
local deskIcons, deskSel, deskLast = {}, nil, {t = 0}
local deskSignature = ""
local hiddenByShowDesktop
local closeOverlay, openOverlay, appMenu, windowsOf, invalidateBg

invalidateBg = function() bgValid = false Desktop.dirty = true end

local function iconLayerDirty()
  -- Значки входят в кэш фона, поэтому при перетаскивании invalidateBg
  -- при каждом кадре дорого: кэш отключаем до конца перетаскивания.
  Desktop.dirty = true
end

-- Слабое железо: маленький экран, мало цветов или мало ОЗУ.
-- В таком случае оформление упрощается само (настройка «Эффекты»: авто).
function Desktop.lowSpec()
  local depth = 8
  if gpu and gpu.getDepth then
    local ok, d = pcall(gpu.getDepth)
    if ok and type(d) == "number" then depth = d end
  end
  return W <= 80 or depth < 8 or computer.totalMemory() < 768 * 1024
end

--- Эффекты Aero: "auto" (по железу), "on", "off".
function Desktop.effectsEnabled()
  local m = System.settings.effects
  if m == "off" then return false end
  if m == "on" then return true end
  return not Desktop.lowSpec()
end

local PRESETS = {{160, 50}, {140, 44}, {120, 40}, {100, 32}, {80, 25}}

local MONTHS = {"Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"}
local MONTHS_GEN = {"января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"}
local WEEKDAYS = {"понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"}
local DOW = {"Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"}

local function isMemoryError(err)
  err = tostring(err):lower()
  return err:find("not enough memory", 1, true) ~= nil or err:find("out of memory", 1, true) ~= nil
end

local function tb(e)
  if debug and debug.traceback then return debug.traceback(tostring(e), 2) end
  return tostring(e)
end

-- Обои Windows 7
Desktop.wallpapers = {
  {name = "Гармония", c1 = 0x07203C, c2 = 0x2A6FB5, logo = true},
  {name = "Луг",      c1 = 0x0E2A16, c2 = 0x4E9A3C, logo = true,
    ramp = {0x002400, 0x004900, 0x336D00, 0x339200, 0x66B62A, 0x99DB55}},
  {name = "Закат",    c1 = 0x2A1230, c2 = 0xC0703C,
    ramp = {0x330000, 0x662400, 0x994900, 0xCC6D00, 0xFF922A, 0xFFB655}},
  {name = "Полночь",  c1 = 0x060C18, c2 = 0x24466E,
    ramp = {0x000000, 0x002440, 0x002480, 0x3349BF, 0x336DFF, 0x6692FF}},
  {name = "Графит",   c1 = 0x14171B, c2 = 0x4A545E,
    ramp = {0x0F0F0F, 0x1E1E1E, 0x3C3C3C, 0x5A5A5A, 0x787878, 0x969696}},
  {name = "Классика", c1 = 0x1B4A80, c2 = 0x1B4A80,
    ramp = {0x004980, 0x004980, 0x004980, 0x004980, 0x004980, 0x004980}},
}

function Desktop.screenSize() return W, H end
function Desktop.dockHeight() return TB end
function Desktop.taskbarHeight() return TB end

function Desktop.applyTheme()
  local s = System.settings
  GUI.setTheme(s.theme, s.accent, s.sysmode)
  -- Переключение эффектов применяется и к уже открытым окнам.
  local fx = Desktop.effectsEnabled()
  for _, w in ipairs(Desktop.windows) do w.shadow = fx end
  invalidateBg()
end

-- ---------- значки рабочего стола
local ICON_COMPUTER = {pal = {k = 0x1B2530, s = 0x8FD0F0, b = 0x2A86D8, w = 0xFFFFFF},
  "..kkkk..", ".kssssk.", ".kswbsk.", ".kssbsk.", ".kssssk.", ".kkkkkk.", "...kk...", "..kkkk.."}
local ICON_TRASH = {pal = {b = 0x9CCBF0, l = 0xFFFFFF},
  "..bbbb..", ".llllll.", ".lbllbl.", ".llllll.", ".lbllbl.", ".llllll.", ".llllll.", "..llll.."}
local ICON_FOLDER = {pal = {y = 0xFFD96B, o = 0xE0A030, w = 0xFFF6D8},
  "..yyy...", "..yyyyyy", ".yyyyyyy", "yyyyyyyy", "ywwwwwwy", "yooooooy", "yooooooy", "yyyyyyyy"}
local ICON_FILE = {"wwwwww..", "wlllllw.", "wwwwwww.", "wllllw..", "wwwwwww.", "wllllw..", "wwwwwww.", "wwwwwww."}
local ICON_IMAGE = {pal = {g = 0x4CA02C, s = 0x8FD0F0},
  "wwwwwwww", "wsssssww", "wssyssww", "wsssssgw", "wsssggggw", "wsgggggw", "wggggggw", "wwwwwwww"}
local ICON_LUA = {pal = {b = 0x2A5FB0},
  ".bbbbbb.", "bbwwbbbb", "bbwwbbwb", "bbbbbbbb", "bbbbbbbb", "bbbbbwbb", "bbbbbbbb", ".bbbbbb."}

local function iconForFile(name, isDir)
  if isDir then return ICON_FOLDER end
  local ext = System.extension(name)
  if ext == "cpaint" then return ICON_IMAGE end
  if ext == "lua" then return ICON_LUA end
  return ICON_FILE
end

-- ---------- окна
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
  markWindowsDirty()
end

function Desktop.isFocused(win)
  return Desktop.top() == win and #Desktop.modals == 0
end

local function removeWindow(win)
  for i, w in ipairs(Desktop.windows) do
    if w == win then table.remove(Desktop.windows, i) break end
  end
  markWindowsDirty()
end

function Desktop.closeWindow(win)
  if win.onClose and win.onClose(win) == false then return end
  removeWindow(win)
  -- Две полные сборки мусора на каждое закрытие окна заметно тормозят OC.
  if computer.freeMemory() < 150 * 1024 then System.collect() end
end

function Desktop.closeAll()
  for i = #Desktop.windows, 1, -1 do
    local w = Desktop.windows[i]
    if w then Desktop.closeWindow(w) end
  end
end

function Desktop.newWindow(ctx, w, h, title, opts)
  w, h = min(w, W), min(h, H - TB)
  local n = Desktop.cascade
  Desktop.cascade = (n + 1) % 6
  local x = max(1, floor((W - w) / 2) + 1 + (n - 2) * 3)
  local y = max(1, floor((H - TB - h) / 2) + 1 + (n - 2))
  local win = GUI.window(x, y, w, h, title)
  win.app = ctx
  win.shadow = Desktop.effectsEnabled()
  if ctx and ctx.info and ctx.info.icon then win.iconColor = GUI.iconColor(ctx.info.icon) end
  if opts then for k, v in pairs(opts) do win[k] = v end end
  table.insert(Desktop.windows, win)
  closeOverlay()
  markWindowsDirty()
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
    win.x, win.y = 1, 1
    win:resize(W, H - TB)
  end
  markWindowsDirty()
end

function Desktop.showDesktop()
  if hiddenByShowDesktop then
    for _, w in ipairs(hiddenByShowDesktop) do w.minimized = false end
    hiddenByShowDesktop = nil
  else
    hiddenByShowDesktop = {}
    for _, w in ipairs(Desktop.windows) do
      if not w.minimized then
        w.minimized = true
        hiddenByShowDesktop[#hiddenByShowDesktop + 1] = w
      end
    end
    if #hiddenByShowDesktop == 0 then hiddenByShowDesktop = nil end
  end
  markWindowsDirty()
end

-- ---------- приложения
function Desktop.reloadApps()
  Desktop.apps = System.apps()
  markWindowsDirty()
  invalidateBg()
end

local function appById(id)
  for _, app in ipairs(Desktop.apps) do
    if app.id == id then return app end
  end
end

local function appByPath(path)
  for _, app in ipairs(Desktop.apps) do
    if app.path == path then return app end
  end
end

function Desktop.launch(path, args)
  local code = System.readFile(path .. "/Main.lua")
  if not code then
    GUI.alert("Ошибка запуска", "Не найден файл " .. path .. "/Main.lua")
    return
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

function Desktop.ensureInstalled(id)
  if appById(id) then return true end
  if not System.exists(System.STORE .. "/" .. id .. ".app") then return false end
  local ok, err = System.installApp(id)
  if not ok then
    Desktop.notify("Не удалось установить " .. id .. ": " .. tostring(err), "Магазин")
    return false
  end
  Desktop.reloadApps()
  return true
end

function Desktop.launchById(id, args, autoInstall)
  if autoInstall then Desktop.ensureInstalled(id) end
  local app = appById(id)
  if app then return Desktop.launch(app.path, args) end
end

windowsOf = function(path)
  local list = {}
  for _, w in ipairs(Desktop.windows) do
    if w.app and w.app.path == path then list[#list + 1] = w end
  end
  return list
end

function Desktop.launchOrFocus(app)
  local ws = windowsOf(app.path)
  if #ws > 0 then
    for _, w in ipairs(ws) do w.minimized = false end
    Desktop.focus(ws[#ws])
  else
    Desktop.launch(app.path)
  end
end

local ASSOC = {html = "Browser", htm = "Browser", md = "Browser", cpaint = "Paint", cpk = "Store"}

function Desktop.openFile(path)
  local ext = System.extension(path)
  if path:match("%.app/?$") then
    Desktop.launch((path:gsub("/$", "")))
  elseif System.isDir(path) then
    Desktop.launchById("Finder", {path = path})
  else
    local id = ASSOC[ext]
    if id == "Browser" then
      Desktop.launchById("Browser", {url = "file://" .. path})
    elseif id == "Store" then
      Desktop.launchById("Store", {package = path})
    elseif id then
      if appById(id) then
        Desktop.launchById(id, {file = path})
      elseif System.exists(System.STORE .. "/" .. id .. ".app") then
        local info = System.loadData(System.STORE .. "/" .. id .. ".app/Info.lua") or {}
        if GUI.confirm("Нет подходящего приложения", "Чтобы открыть этот файл, нужно приложение «" .. tostring(info.title or id) .. "». Открыть его в Магазине?", "В Магазин", "Отмена") then
          Desktop.launchById("Store", {app = id})
        end
      else
        Desktop.launchById("Editor", {file = path})
      end
    else
      Desktop.launchById("Editor", {file = path})
    end
  end
end

function Desktop.uninstall(app)
  if not System.exists(System.STORE .. "/" .. app.id .. ".app") then
    GUI.alert("Нельзя удалить", "«" .. tostring(app.title) .. "» — встроенное приложение CubeOS.")
    return false
  end
  if not GUI.confirm("Удаление программы", "Удалить «" .. tostring(app.title) .. "»? Ваши файлы останутся на месте.", "Удалить", "Отмена", true) then
    return false
  end
  for _, w in ipairs(windowsOf(app.path)) do Desktop.closeWindow(w) end
  System.uninstallApp(app.id)
  Desktop.reloadApps()
  Desktop.notify("«" .. tostring(app.title) .. "» удалено", "Программы и компоненты")
  return true
end

function Desktop.reportError(err)
  if Desktop.inError then return end
  System.log("ERROR " .. tostring(err))
  if isMemoryError(err) then Desktop.recoverMemory() end
  Desktop.inError = true
  pcall(GUI.alert, "Ошибка в приложении", tostring(err))
  Desktop.inError = false
end

function Desktop.notify(text, title)
  text, title = tostring(text), title or "CubeOS"
  Desktop.toasts[#Desktop.toasts + 1] = {text = text, title = title, expires = computer.uptime() + 4.5}
  while #Desktop.toasts > 3 do table.remove(Desktop.toasts, 1) end
  table.insert(Desktop.history, 1, {text = text, title = title, time = System.clock(), unread = true})
  while #Desktop.history > 30 do Desktop.history[#Desktop.history] = nil end
  Desktop.dirty = true
end

function Desktop.showText(title, text)
  local w, h = min(W - 4, 76), min(H - TB - 4, 24)
  local win = GUI.modalWindow(title, w, h)
  local c = win.content
  c:add(GUI.textView(2, 2, w - 3, h - 6, text))
  Screen.rect(win.x + 1, win.y + h - 3, w - 2, 2, C.panel, nil, " ")
  c:add(GUI.button(w - 17, h - 3, 14, 2, "Закрыть", function() win.closed = true end, "primary"))
  win.onEnter = function() win.closed = true end
  GUI.runModal(win)
end

function Desktop.runScript(path)
  local code, err = System.readFile(path)
  if not code then GUI.alert("Ошибка", tostring(err)) return end
  local ok, out = System.runLua(code, path, {Desktop = Desktop, GUI = GUI, System = System})
  Desktop.showText((ok and "Готово: " or "Ошибка: ") .. System.basename(path), out ~= "" and out or "(скрипт ничего не вывел)")
end

function Desktop.showLog()
  local data = System.readFile(System.logPath)
  if not data or data == "" then data = "Журнал пуст — ошибок не было." end
  if #data > 6000 then data = "…" .. data:sub(-6000) end
  Desktop.showText("Журнал системы", data)
end

function Desktop.maxResolution()
  return gpu.maxResolution()
end

function Desktop.resync()
  local w, h = gpu.getResolution()
  if w == W and h == H then return end
  W, H = w, h
  Screen.init(gpu, W, H)
  for _, win in ipairs(Desktop.windows) do
    if win.maximized then
      win.x, win.y = 1, 1
      win:resize(W, H - TB)
    end
    win.x = max(1, min(win.x, W - 10))
    win.y = max(1, min(win.y, H - TB - 1))
  end
  closeOverlay()
  System.collect()
  invalidateBg()
end

function Desktop.setResolution(w, h)
  local ok = pcall(gpu.setResolution, w, h)
  if not ok then return false end
  Desktop.resync()
  return true
end

function Desktop.rebind()
  local ga, sa = component.list("gpu")(), component.list("screen")()
  if not (ga and sa) then
    screenOk = false
    return
  end
  gpu = component.proxy(ga)
  pcall(gpu.bind, sa, false)
  -- Точные координаты нужны только рисованию; окна работают в ячейках GPU.
  preciseScreen = false
  pcall(function() component.proxy(sa).setPrecise(false) end)
  screenOk = true
  W, H = 0, 0
  Desktop.resync()
  Screen.invalidate()
  invalidateBg()
end

--- Paint может временно запросить субсимвольные координаты для рисования.
--- Менеджер окон сам возвращает обычный режим после завершения мазка.
function Desktop.setPrecise(enabled)
  local address = component.list("screen")()
  if not address then return false end
  local ok, result = pcall(function() return component.proxy(address).setPrecise(enabled) end)
  if ok and result ~= false then preciseScreen = enabled and true or false return true end
  return false
end

function Desktop.recoverMemory()
  System.collect()
  if computer.freeMemory() > 90 * 1024 then return end
  for _, p in ipairs(PRESETS) do
    if p[1] < W then
      if Desktop.setResolution(p[1], p[2]) then
        Desktop.notify(string.format("Мало памяти: разрешение %d×%d", p[1], p[2]))
        System.log("Мало памяти: разрешение уменьшено до " .. p[1] .. "x" .. p[2])
      end
      break
    end
  end
  System.collect()
  if computer.freeMemory() > 60 * 1024 then return end
  local victim = Desktop.windows[#Desktop.windows]
  if victim then
    removeWindow(victim)
    Desktop.notify("Мало памяти: окно «" .. tostring(victim.title) .. "» закрыто")
    System.collect()
  end
end

-- ---------- системные окна
function Desktop.about()
  local used, total = System.memory()
  local fs = System.fs
  GUI.alert("О системе", string.format(
    "CubeOS %s  (сборка %s)\nОболочка в стиле Windows 7 для OpenComputers\n\nОЗУ: %s из %s\nЭкран: %d×%d\nДиск: занято %s из %s\nВремя работы: %s",
    System.version, System.build,
    System.formatSize(used), System.formatSize(total), W, H,
    System.formatSize(fs.spaceUsed()), System.formatSize(fs.spaceTotal()), System.uptimeText()))
end

function Desktop.welcome()
  local ctx = {path = "/System/Welcome", title = "Начало работы"}
  local win = Desktop.newWindow(ctx, 66, 21, "Начало работы с CubeOS")
  local c = win.content
  c:add(GUI.label(3, 2, "Добро пожаловать, " .. tostring(System.settings.username) .. "!", "accent"))
  c:add(GUI.label(3, 3, "CubeOS " .. System.version .. " — оболочка в стиле Windows 7", "dim"))
  c:add(GUI.textView(3, 5, 60, 10,
    "•  Круглая кнопка «Пуск» слева внизу открывает меню программ.\n" ..
    "•  Правый клик по программе — закрепить на панели задач или удалить.\n" ..
    "•  Магазин: Paint, Календарь, Погода, Курсы валют, игры — бесплатно.\n" ..
    "•  Щелчок по часам — календарь, флажок в трее — центр поддержки.\n" ..
    "•  Alt+Tab — переключение окон, Ctrl+Esc — «Пуск», Alt+F4 — закрыть.\n" ..
    "•  Перетаскивание окна к верхней кромке разворачивает его (Aero Snap).\n" ..
    "•  Браузер и RYKEA работают через Internet Card."))
  Screen.rect(2, 17, win.w - 2, 3, C.panel, nil, " ")
  c:add(GUI.button(3, 18, 22, 2, "Открыть Магазин", function()
    win:close()
    Desktop.launchById("Store")
  end, "primary"))
  c:add(GUI.button(27, 18, 16, 2, "Понятно", function() win:close() end))
  win.onClose = function()
    System.settings.welcomed = true
    System.saveSettings()
  end
end

-- ---------- обои и значки
-- Палитра обоев подобрана так, чтобы каждая ступень точно попадала
-- в 256-цветную палитру экрана OpenComputers и оставалась синей:
-- линейный градиент на таком экране даёт грязные зелёные полосы.
-- Упорядоченное дизерирование Байера 4×4: на 256-цветном экране
-- только так градиент выглядит гладким, без ступеней и колец.
local BAYER = {
  {0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5},
}

local function drawWallpaper()
  local wp = Desktop.wallpapers[System.settings.wallpaper] or Desktop.wallpapers[1]
  local ah = H - TB
  -- Лёгкий режим для Tier 2 / малого ОЗУ: ровная заливка вместо
  -- градиента с дизерингом — быстро и читаемо при 16 цветах.
  if not Desktop.effectsEnabled() then
    Screen.rect(1, 1, W, ah, wp.c1, nil, " ")
    return
  end
  local ramp = wp.ramp or {0x002440, 0x004980, 0x336DBF, 0x3392FF, 0x66B6FF, 0x99DBFF}
  local bands = #ramp
  -- каждый полублок — отдельная ступень: 2 «пикселя» на ячейку
  local steps = ah * 2
  for y = 1, ah do
    local bayer = BAYER[(y - 1) % 4 + 1]
    for x = 1, W do
      local bx = bayer[(x - 1) % 4 + 1] / 16 - 0.5
      local col = {}
      for half = 0, 1 do
        local py = (y - 1) * 2 + half
        local t = (py / max(1, steps - 1)) * 0.86 + (x / W) * 0.14
        local pos = t * (bands - 1) + bx * 0.34
        local idx = floor(pos + 0.5) + 1
        if idx < 1 then idx = 1 elseif idx > bands then idx = bands end
        col[half + 1] = ramp[idx]
      end
      Screen.rect(x, y, 1, 1, col[2], col[1], "▀")
    end
  end
  local pw, ph = max(6, floor(W * 0.085)), max(3, floor(ah * 0.20))
  local cx, cy = floor(W * 0.63), floor(ah * 0.46)
  local x0, y0 = cx - pw, cy - ph
  if wp.logo then
    local function pane(px, py, w2, h2, fill, top)
      Screen.rect(px, py, w2, h2, fill, nil, " ")
      Screen.rect(px, py, w2, 1, fill, top, "▀")
    end
    pane(x0, y0, pw, ph, 0x66B6FF, 0xCCEEFF)
    pane(x0 + pw + 1, y0, pw, ph, 0x3392FF, 0x99DBFF)
    pane(x0, y0 + ph + 1, pw, ph, 0x3392FF, 0xCCEEFF)
    pane(x0 + pw + 1, y0 + ph + 1, pw, ph, 0x004980, 0x66B6FF)
  end
end

local CELL_W, CELL_H = 12, 6
local ICON_LAYOUT = "/Users/Desktop.layout"

-- У каждого значка стабильный ключ: системные значки и программы не
-- меняют порядок при добавлении файлов на рабочий стол.
local function iconKey(it)
  return it.key or it.path or it.label
end

local function loadIconPositions()
  local data = System.loadData(ICON_LAYOUT)
  return type(data) == "table" and data or {}
end
iconPositions = loadIconPositions()

local function saveIconPositions()
  if not iconPosDirty then return end
  local parts = {}
  for k, p in pairs(iconPositions) do
    parts[#parts + 1] = "[" .. string.format("%q", k) .. "]=" .. string.format("{%d,%d}", p[1], p[2])
  end
  System.writeFile(ICON_LAYOUT, "return {" .. table.concat(parts, ",") .. "}\n")
  iconPosDirty = false
end

local function defaultPos(i)
  local rows = max(1, floor((H - TB - 1) / CELL_H))
  local col, row = floor((i - 1) / rows), (i - 1) % rows
  return {2 + col * CELL_W, 2 + row * CELL_H}
end

--- Позиция значка в ячейках экрана. Пользовательские координаты всегда
--- приводятся к сетке, чтобы значки не перекрывали друг друга.
local function deskPos(i)
  local it = deskIcons[i]
  local p = it and iconPositions[iconKey(it)]
  if p and type(p) == "table" and #p >= 2 then
    local x = max(1, min(W - CELL_W + 1, tonumber(p[1]) or 1))
    local y = max(1, min(H - TB - CELL_H, floor(tonumber(p[2]) or 1)))
    return x, y
  end
  local d = defaultPos(i)
  return d[1], d[2]
end

--- Ближайшее свободное место сетки (во время перетаскивания).
local function snapIcon(x, y, except)
  local gx = max(1, min(W - CELL_W + 1, x))
  local gy = max(1, min(H - TB - CELL_H, y))
  local cellCols = max(1, floor((W - 2) / CELL_W))
  local cellRows = max(1, floor((H - TB - 1) / CELL_H))
  local function free(cx, cy)
    if cx < 1 or cy < 1 or cx > cellCols or cy > cellRows then return false end
    for j, other in ipairs(deskIcons) do
      if j ~= except then
        local ox, oy = deskPos(j)
        if ox == 2 + (cx - 1) * CELL_W and oy == 2 + (cy - 1) * CELL_H then return false end
      end
    end
    return true
  end
  local cx = max(1, min(cellCols, floor((gx - 2) / CELL_W) + 1))
  local cy = max(1, min(cellRows, floor((gy - 2) / CELL_H) + 1))
  if free(cx, cy) then return 2 + (cx - 1) * CELL_W, 2 + (cy - 1) * CELL_H end
  -- ищем ближайшую свободную ячейку по спирали
  for radius = 1, max(cellCols, cellRows) do
    for dy = -radius, radius do
      for dx = -radius, radius do
        if math.abs(dx) == radius or math.abs(dy) == radius then
          if free(cx + dx, cy + dy) then
            return 2 + (cx + dx - 1) * CELL_W, 2 + (cy + dy - 1) * CELL_H
          end
        end
      end
    end
  end
  return gx, gy
end

local function buildDeskIcons()
  local list = {
    {key = "system:computer", label = "Компьютер", icon = ICON_COMPUTER, open = function() Desktop.launchById("Finder", {path = "/"}) end},
    {key = "system:trash", label = "Корзина", icon = ICON_TRASH, trash = true, open = function()
      System.mkdirs("/Users/.Trash")
      Desktop.launchById("Finder", {path = "/Users/.Trash"})
    end},
  }
  for _, id in ipairs({"Browser", "Store"}) do
    local app = appById(id)
    if app then
      list[#list + 1] = {key = "app:" .. id, label = app.short or app.title, icon = app.icon, open = function() Desktop.launchOrFocus(app) end}
    end
  end
  for _, name in ipairs(System.list("/Users/Desktop")) do
    local isDir = name:sub(-1) == "/"
    local clean = name:gsub("/$", "")
    local path = "/Users/Desktop/" .. clean
    local app = isDir and clean:match("%.app$") and appByPath(path)
    list[#list + 1] = {
      key = "file:" .. clean, label = (clean:gsub("%.app$", "")), icon = iconForFile(clean, isDir), path = path, isFile = true,
      open = function() Desktop.openFile(path) end,
    }
    if app then list[#list].icon = app.icon end
  end
  for _, it in ipairs(list) do
    local lines = GUI.wrap(it.label, CELL_W - 1)
    it.labelLines = {lines[1] or "", #lines > 1 and lines[2] or ""}
    it.labelLen = {unicode.len(it.labelLines[1]), unicode.len(it.labelLines[2])}
  end
  return list
end

function Desktop.refreshIcons(force)
  local names = {}
  for _, n in ipairs(System.list("/Users/Desktop")) do names[#names + 1] = n end
  local sig = table.concat(names, "|") .. #Desktop.apps
  if sig == deskSignature and not force then return end
  deskSignature = sig
  local oldKeys = {}
  for _, it in ipairs(deskIcons) do oldKeys[iconKey(it)] = true end
  deskIcons = buildDeskIcons()
  -- Новым значкам назначаем первое свободное место сетки.
  for i, it in ipairs(deskIcons) do
    if not oldKeys[iconKey(it)] and not iconPositions[iconKey(it)] then
      local x, y = snapIcon(defaultPos(i)[1], defaultPos(i)[2], i)
      iconPositions[iconKey(it)] = {x, y}
      iconPosDirty = true
    end
  end
  saveIconPositions()
  iconLayerDirty()
end

--- Сбросить расположение значков к стандартному.
function Desktop.resetIconPositions()
  iconPositions = {}
  iconPosDirty = true
  for i, it in ipairs(deskIcons) do
    local d = defaultPos(i)
    iconPositions[iconKey(it)] = {d[1], d[2]}
  end
  saveIconPositions()
  iconLayerDirty()
end

local function deskIconAt(px, py)
  for i = 1, #deskIcons do
    local x, y = deskPos(i)
    if px >= x and px < x + CELL_W and py >= y - 1 and py < y - 1 + CELL_H then return i end
  end
end

local function drawDeskIcons()
  for i, it in ipairs(deskIcons) do
    local x, y = deskPos(i)
    if iconDrag and iconDrag.index == i then x, y = iconDrag.x, iconDrag.y end
    if i == deskSel or (iconDrag and iconDrag.index == i) then
      Screen.rect(x, y - 1, CELL_W, CELL_H, 0x7FB6E6, nil, nil, 0.34)
    end
    GUI.drawIcon(x + 2, y, it.icon)
    local lines = it.labelLines
    if lines then
      for k = 1, 2 do
        local text = lines[k]
        if text ~= "" then
          local tx = x + floor((CELL_W - it.labelLen[k]) / 2)
          Screen.rect(tx - 1, y + 3 + k, it.labelLen[k] + 2, 1, 0x08131F, nil, nil, 0.32)
          Screen.text(tx, y + 3 + k, 0xFFFFFF, text)
        end
      end
    end
  end
end

-- ---------- панель задач Aero
local function trayText()
  local used, total = System.memory()
  local parts = {}
  parts[#parts + 1] = component.list("internet")() and "▂▄▆" or "▂×"
  local e, me = computer.energy(), computer.maxEnergy()
  if me and me > 0 and me < math.huge then parts[#parts + 1] = "▮" .. floor(e / me * 100) .. "%" end
  parts[#parts + 1] = "ОЗУ " .. floor(used / total * 100) .. "%"
  return table.concat(parts, " ")
end

local function buildTaskItems()
  local items, byKey = {}, {}
  for _, id in ipairs(System.settings.pinned or {}) do
    local app = appById(id)
    if app then
      local it = {app = app, key = app.path, pinned = true, windows = {}}
      items[#items + 1], byKey[app.path] = it, it
    end
  end
  for _, w in ipairs(Desktop.windows) do
    local key = w.app and w.app.path or tostring(w)
    local it = byKey[key]
    if not it then
      local app = w.app and appByPath(w.app.path)
      it = {app = app, key = key, windows = {}, title = w.title}
      items[#items + 1], byKey[key] = it, it
    end
    it.windows[#it.windows + 1] = w
  end
  return items
end

local function taskbarGeometry()
  local tray = trayText()
  local showX = W                       -- полоска «Показать рабочий стол»
  local notifX1, notifX2 = W - 4, W - 1 -- флажок центра поддержки
  local clockX2 = notifX1 - 1
  local clockX1 = clockX2 - 10
  local trayX = clockX1 - unicode.len(tray) - 2
  return {clockX1 = clockX1, clockX2 = clockX2, notifX1 = notifX1, notifX2 = notifX2,
          trayX = trayX, tray = tray, showX = showX}
end

--- Круглая глянцевая кнопка «Пуск»
local function drawOrb(x, y, lit)
  local o1, o2, edge = C.orb1, C.orb2, C.orbEdge
  if lit then
    o1 = Screen.blend(0xFFFFFF, o1, 0.55)
    o2 = Screen.blend(0xFFFFFF, o2, 0.25)
  end
  local bg = C.taskbar
  Screen.rect(x, y, 7, TB, bg, nil, " ")
  Screen.text(x + 1, y, o1, "▗▄▄▄▖", bg)
  Screen.rect(x + 1, y + 1, 5, 1, o2, nil, " ")
  Screen.set(x, y + 1, bg, edge, "▐")
  Screen.set(x + 6, y + 1, bg, edge, "▌")
  -- четыре «окошка» флага Windows: красный, зелёный, синий, жёлтый
  Screen.text(x + 2, y + 1, 0xF45F4C, "▘", o2)
  Screen.text(x + 3, y + 1, 0x8ED13F, "▝", o2)
  Screen.text(x + 4, y + 1, 0x46B7F2, "▖", o2)
  Screen.text(x + 5, y + 1, 0xFFC63F, "▗", o2)
  Screen.text(x + 1, y + 2, o2, "▝▀▀▀▘", bg)
end

local function drawTaskbar()
  local y0 = H - TB + 1
  local g = taskbarGeometry()
  local top = Desktop.top()

  -- стекло панели задач
  Screen.rect(1, y0, W, TB, C.taskbar, nil, " ")
  GUI.gloss(1, y0, W, C.taskbarTop, Screen.blend(C.taskbarTop, C.taskbar, 0.55))
  Screen.rect(1, y0 + 1, W, 1, Screen.blend(C.taskbarTop, C.taskbar, 0.18), nil, " ")
  for cx = 1, W do Screen.set(cx, y0, nil, C.taskbarEdge, "▔") end

  drawOrb(1, y0, overlay and overlay.kind == "start")

  if windowsCacheDirty or not windowsCache then
    windowsCache = buildTaskItems()
    windowsCacheDirty = false
  end
  taskItems = windowsCache
  local x = 9
  for _, it in ipairs(taskItems) do
    if x + 6 >= g.trayX then break end
    it.x1, it.x2 = x, x + 6
    local running = #it.windows > 0
    local focused = false
    if running and top then
      for _, w in ipairs(it.windows) do
        if w == top then focused = true end
      end
    end
    if focused then
      GUI.gloss(x, y0, 7, Screen.blend(0xFFFFFF, C.taskbarActive, 0.45), C.taskbarActive)
      Screen.rect(x, y0 + 1, 7, TB - 1, C.taskbarActive, nil, " ")
      for r = 0, TB - 1 do
        Screen.set(x, y0 + r, nil, C.taskbarEdge, "▏")
        Screen.set(x + 6, y0 + r, nil, C.taskbarEdge, "▕")
      end
    elseif running then
      GUI.gloss(x, y0, 7, Screen.blend(0xFFFFFF, C.taskbarHover, 0.3), C.taskbarHover)
      Screen.rect(x, y0 + 1, 7, TB - 1, C.taskbarHover, nil, " ")
      for r = 0, TB - 1 do
        Screen.set(x, y0 + r, nil, Screen.blend(0xFFFFFF, C.taskbarHover, 0.5), "▏")
        Screen.set(x + 6, y0 + r, nil, Screen.blend(0xFFFFFF, C.taskbarHover, 0.5), "▕")
      end
    end
    local icon = it.app and it.app.icon
    -- суперпанель Windows 7: только значки, без подписей
    if icon then
      GUI.drawIconSmall(x + 1, y0, icon)
      if running then
        Screen.text(x + 1, y0 + 2, focused and C.accentLight or C.taskbarDim, "▔▔▔▔",
          focused and C.taskbarActive or C.taskbarHover)
      end
    else
      Screen.text(x + 2, y0 + 1, C.taskbarText, "▣", focused and C.taskbarActive or C.taskbar)
    end
    x = x + 8
  end

  -- системный трей
  Screen.text(g.trayX, y0 + 1, C.taskbarDim, g.tray, C.taskbar)

  local cbg = (overlay and overlay.kind == "clock") and C.taskbarActive or C.taskbar
  Screen.rect(g.clockX1, y0, g.clockX2 - g.clockX1 + 1, TB, cbg, nil, " ")
  local t, d = System.clock(), System.date("%d.%m.%Y")
  Screen.text(g.clockX2 - unicode.len(t), y0, C.taskbarText, t, cbg)
  Screen.text(g.clockX2 - unicode.len(d), y0 + 1, C.taskbarText, d, cbg)

  local unread = 0
  for _, n in ipairs(Desktop.history) do
    if n.unread then unread = unread + 1 end
  end
  local nbg = (overlay and overlay.kind == "action") and C.taskbarActive or C.taskbar
  Screen.rect(g.notifX1, y0, 4, TB, nbg, nil, " ")
  Screen.text(g.notifX1 + 1, y0, unread > 0 and 0xFFD34D or C.taskbarText, "⚑", nbg)
  if unread > 0 then Screen.text(g.notifX1 + 1, y0 + 1, C.taskbarDim, tostring(min(unread, 9)), nbg) end

  -- «Показать рабочий стол» — узкая стеклянная полоска справа
  for r = 0, TB - 1 do
    Screen.set(W, y0 + r, C.taskbar, C.taskbarEdge, "▏")
  end
end

local function launchItem(it)
  if #it.windows == 0 then
    if it.app then Desktop.launch(it.app.path) end
  elseif #it.windows == 1 then
    local w = it.windows[1]
    if w == Desktop.top() then
      w.minimized = true
    else
      Desktop.focus(w)
    end
  else
    local entries = {}
    for _, w in ipairs(it.windows) do
      entries[#entries + 1] = {text = GUI.fit(tostring(w.title), 40), action = function() Desktop.focus(w) end}
    end
    entries[#entries + 1] = {separator = true}
    if it.app then entries[#entries + 1] = {text = "Новое окно", action = function() Desktop.launch(it.app.path) end} end
    GUI.menu(it.x1, H - TB - #entries - 1, entries)
  end
end

local function taskItemMenu(it)
  local entries = {}
  if it.app then
    entries[#entries + 1] = {text = tostring(it.app.title), action = function() Desktop.launch(it.app.path) end}
    entries[#entries + 1] = {separator = true}
    local pinned = false
    for _, id in ipairs(System.settings.pinned or {}) do
      if id == it.app.id then pinned = true end
    end
    entries[#entries + 1] = {text = pinned and "Изъять из панели задач" or "Закрепить на панели задач", action = function()
      local list = System.settings.pinned
      if pinned then
        for i = #list, 1, -1 do
          if list[i] == it.app.id then table.remove(list, i) end
        end
      else
        list[#list + 1] = it.app.id
      end
      System.saveSettings()
      Desktop.dirty = true
    end}
  end
  if #it.windows > 0 then
    entries[#entries + 1] = {text = #it.windows > 1 and "Закрыть все окна" or "Закрыть окно", action = function()
      for _, w in ipairs(it.windows) do Desktop.closeWindow(w) end
    end}
  end
  if #entries > 0 then GUI.menu(it.x1, H - TB - #entries - 1, entries) end
end

local function taskbarTouch(e)
  local g = taskbarGeometry()
  if e.x <= 7 then
    if e.button == 0 then
      if overlay and overlay.kind == "start" then closeOverlay() else openOverlay(Desktop.Start) end
    else
      GUI.menu(1, H - TB - 8, {
        {text = "Проводник", action = function() Desktop.launchById("Finder") end},
        {text = "Диспетчер задач", action = function() Desktop.launchById("Monitor") end},
        {text = "Панель управления", action = function() Desktop.launchById("Settings") end},
        {text = "Программы и компоненты", action = function() Desktop.launchById("Settings", {page = "apps"}) end},
        {separator = true},
        {text = "Свойства", action = Desktop.about},
      })
    end
  elseif e.x >= g.showX then
    Desktop.showDesktop()
  elseif e.x >= g.notifX1 and e.x <= g.notifX2 then
    openOverlay(Desktop.Action)
  elseif e.x >= g.clockX1 and e.x <= g.clockX2 then
    openOverlay(Desktop.Clock)
  else
    for _, it in ipairs(taskItems) do
      if it.x1 and e.x >= it.x1 and e.x <= it.x2 then
        if e.button == 1 then taskItemMenu(it) else launchItem(it) end
        return
      end
    end
  end
end

-- ---------- меню «Пуск» Windows 7
local Start = {kind = "start", search = "", scroll = 0, sel = 1, rowHits = {}, linkHits = {}}
Desktop.Start = Start

local startRowsCache, startRowsSig

local function sortedApps()
  local list = {}
  for _, a in ipairs(Desktop.apps) do list[#list + 1] = a end
  local function key(a)
    local t = unicode.lower(a.title or a.id)
    return ((t:byte(1) or 0) >= 0xD0 and "0" or "1") .. t
  end
  table.sort(list, function(a, b) return key(a) < key(b) end)
  return list
end

function Start.rows()
  local st = System.settings
  local sig = unicode.lower(Start.search) .. "#" .. #Desktop.apps
  if sig == startRowsSig then return startRowsCache end
  local rows, apps = {}, sortedApps()
  local q = unicode.lower(Start.search)
  if q ~= "" then
    for _, a in ipairs(apps) do
      if unicode.lower(a.title or a.id):find(q, 1, true) then rows[#rows + 1] = {app = a} end
    end
    startRowsSig, startRowsCache = sig, rows
    return rows
  end
  -- «Недавние»: закреплённые сверху, затем алфавитный список
  local pinnedIds = st.pinned or {}
  if #pinnedIds > 0 then
    for _, id in ipairs(pinnedIds) do
      local app = appById(id)
      if app then rows[#rows + 1] = {app = app} end
    end
    rows[#rows + 1] = {separator = true}
  end
  local letter
  for _, a in ipairs(apps) do
    local l = unicode.upper(unicode.sub(a.title or a.id, 1, 1))
    if l ~= letter then
      letter = l
      rows[#rows + 1] = {header = l}
    end
    rows[#rows + 1] = {app = a}
  end
  startRowsSig, startRowsCache = sig, rows
  return rows
end

function Start.geom()
  local h = min(32, H - TB - 1)
  local rightW = W >= 92 and 26 or 0
  local leftW = W >= 92 and 34 or min(38, W - 4)
  return {x = 1, y = H - TB - h + 1, w = leftW + rightW + 2, h = h, leftW = leftW, rightW = rightW}
end

function Start.open()
  Start.search, Start.scroll, Start.sel = "", 0, 1
  startRowsSig = nil
end

function Start.contains(px, py)
  local g = Start.geom()
  return px >= g.x and px < g.x + g.w and py >= g.y and py < g.y + g.h
end

function Start.toggleHit(e) return e.x <= 7 end

local LINKS = {
  {label = "Документы", key = "docs"},
  {label = "Изображения", key = "pics"},
  {label = "Загрузки", key = "dl"},
  {label = "Игры", key = "games"},
  {sep = true},
  {label = "Компьютер", key = "computer"},
  {label = "Панель управления", key = "settings"},
  {label = "Магазин", key = "store"},
  {sep = true},
  {label = "Справка и поддержка", key = "help"},
}

local function linkAction(key)
  closeOverlay()
  if key == "docs" then Desktop.launchById("Finder", {path = "/Users/Documents"})
  elseif key == "pics" then Desktop.launchById("Finder", {path = "/Users/Pictures"})
  elseif key == "dl" then Desktop.launchById("Finder", {path = "/Users/Downloads"})
  elseif key == "games" then Desktop.launchById("Store", {tab = "games"})
  elseif key == "computer" then Desktop.launchById("Finder", {path = "/"})
  elseif key == "settings" then Desktop.launchById("Settings")
  elseif key == "store" then Desktop.launchById("Store")
  elseif key == "help" then Desktop.about() end
end

function Start.draw()
  local g = Start.geom()
  local x, y, w, h = g.x, g.y, g.w, g.h
  if Desktop.effectsEnabled() then
    Screen.rect(x + 1, y + 1, w, h - 1, 0x000000, nil, nil, 0.4)
  end
  -- корпус меню: стекло по краям, белая левая колонка
  Screen.rect(x, y, w, h, C.startRail, nil, " ")
  GUI.gloss(x, y, w, C.startHeadTop, C.startHead)
  Screen.text(x + 2, y, 0xFFFFFF, "CubeOS 7", C.startHead)

  local lx, lw = x + 1, g.leftW
  Screen.rect(lx, y + 1, lw, h - 4, C.start, nil, " ")
  Screen.rect(lx, y + h - 3, lw, 2, C.startRail, nil, " ")

  -- список программ
  local rows = Start.rows()
  local visible = h - 5
  Start.visible = visible
  Start.rowCount = #rows
  Start.scroll = max(0, min(Start.scroll, max(0, #rows - visible)))
  Start.rowHits = {}
  local appCount = 0
  for _, r in ipairs(rows) do
    if r.app then
      appCount = appCount + 1
      r.n = appCount
    end
  end
  Start.sel = max(1, min(Start.sel, max(1, appCount)))
  for r = 1, visible do
    local row = rows[Start.scroll + r]
    if not row then break end
    local yy = y + 1 + r
    if row.separator then
      Screen.text(lx + 2, yy, C.startDim, string.rep("─", lw - 4), C.start)
    elseif row.header then
      Screen.text(lx + 2, yy, C.startHead, row.header, C.start)
    else
      local a = row.app
      local sel = row.n == Start.sel
      local bg = C.start
      if sel then
        bg = C.startSel
        GUI.gloss(lx + 1, yy, lw - 2, C.selectTop, C.startSel)
      end
      local chip = a.icon and GUI.iconColor(a.icon) or C.accent
      Screen.rect(lx + 2, yy, 2, 1, chip, nil, " ")
      Screen.text(lx + 5, yy, sel and 0xFFFFFF or C.startText, GUI.fit(a.title or a.id, lw - 7), bg)
      Start.rowHits[yy] = a
    end
  end
  if #rows > visible then
    GUI.scrollbar(lx + lw - 1, y + 2, visible, #rows, visible, Start.scroll)
  end
  if #rows == 0 then
    Screen.text(lx + 2, y + 3, C.startDim, "Ничего не найдено", C.start)
  end

  -- строка поиска
  local sy = y + h - 3
  Screen.rect(lx + 1, sy, lw - 2, 1, 0xFFFFFF, nil, " ")
  Screen.set(lx + 1, sy, nil, C.inputBorder, "▏")
  Screen.set(lx + lw - 2, sy, nil, C.inputBorder, "▕")
  if Start.search == "" then
    Screen.text(lx + 2, sy, C.startDim, GUI.fit("Найти программы и файлы", lw - 6), 0xFFFFFF)
  else
    Screen.text(lx + 2, sy, C.startText, GUI.fit(Start.search, lw - 6) .. "▏", 0xFFFFFF)
  end
  Screen.text(lx + lw - 3, sy, C.startHead, "⌕", 0xFFFFFF)
  Start.searchY = sy

  -- правая колонка ссылок
  Start.linkHits = {}
  Start.shutdownRect = nil
  if g.rightW > 0 then
    local rx, rw = x + 1 + lw, g.rightW
    Screen.rect(rx, y + 1, rw, h - 2, C.startRail, nil, " ")
    -- «аватар» пользователя
    Screen.rect(rx + 2, y + 2, 6, 3, C.startHead, nil, " ")
    GUI.gloss(rx + 2, y + 2, 6, C.startHeadTop, C.startHead)
    Screen.text(rx + 4, y + 3, 0xFFFFFF, "☺", C.startHead)
    Screen.text(rx + 10, y + 3, C.startText, GUI.fit(tostring(System.settings.username or "Пользователь"), rw - 11), C.startRail)
    local yy = y + 6
    for _, l in ipairs(LINKS) do
      if yy < y + h - 4 then
        if l.sep then
          Screen.text(rx + 2, yy, C.startDim, string.rep("─", rw - 4), C.startRail)
        else
          local sel = Start.linkSel == l.key
          local bg = C.startRail
          if sel then
            bg = C.startSel
            GUI.gloss(rx + 1, yy, rw - 2, C.selectTop, C.startSel)
          end
          Screen.text(rx + 3, yy, sel and 0xFFFFFF or C.startText, GUI.fit(l.label, rw - 5), bg)
          Start.linkHits[yy] = l.key
        end
        yy = yy + 1
      end
    end
    -- кнопка «Завершение работы»
    local by = y + h - 3
    GUI.bevel(rx + 2, by, rw - 6, 2, C.buttonTop, C.button, C.buttonEdge)
    local label = "Завершение работы"
    Screen.text(rx + 3, by, C.buttonText, GUI.fit(label, rw - 8))
    GUI.bevel(rx + rw - 4, by, 3, 2, C.buttonTop, C.button, C.buttonEdge)
    Screen.text(rx + rw - 3, by, C.buttonText, "▸")
    Start.shutdownRect = {x1 = rx + 2, x2 = rx + rw - 5, y1 = by, y2 = by + 1}
    Start.shutdownArrow = {x1 = rx + rw - 4, x2 = rx + rw - 2, y1 = by, y2 = by + 1}
  end
end

local function startLaunch(app)
  closeOverlay()
  Desktop.launchOrFocus(app)
end

local function powerMenu(x, y)
  GUI.menu(x, y, {
    {text = "Завершение работы", action = function()
      closeOverlay()
      if GUI.confirm("Завершение работы", "Выключить компьютер?", "Выключить", "Отмена") then computer.shutdown() end
    end},
    {text = "Перезагрузка", action = function()
      closeOverlay()
      if GUI.confirm("Перезагрузка", "Перезагрузить компьютер?", "Перезагрузить", "Отмена") then computer.shutdown(true) end
    end},
    {text = "Спящий режим", action = function()
      closeOverlay()
      Desktop.showDesktop()
      Desktop.notify("Экран очищен. Щёлкните «Показать рабочий стол», чтобы вернуть окна.", "Питание")
    end},
  })
end

function Start.event(e)
  local t = e.type
  local g = Start.geom()
  if t == "touch" then
    if Start.shutdownRect and e.y >= Start.shutdownRect.y1 and e.y <= Start.shutdownRect.y2 then
      if e.x >= Start.shutdownArrow.x1 and e.x <= Start.shutdownArrow.x2 then
        powerMenu(e.x, e.y - 6)
        return
      elseif e.x >= Start.shutdownRect.x1 and e.x <= Start.shutdownRect.x2 then
        closeOverlay()
        if GUI.confirm("Завершение работы", "Выключить компьютер?", "Выключить", "Отмена") then computer.shutdown() end
        return
      end
    end
    local lk = Start.linkHits[e.y]
    if lk and e.x > g.x + g.leftW then linkAction(lk) return end
    local app = Start.rowHits[e.y]
    if app and e.x <= g.x + g.leftW then
      if e.button == 1 then appMenu(app, e.x, e.y) else startLaunch(app) end
      return
    end
  elseif t == "scroll" then
    Start.scroll = max(0, min(max(0, (Start.rowCount or 0) - (Start.visible or 1)), Start.scroll - e.dir * 3))
  elseif t == "paste" then
    Start.search = Start.search .. (tostring(e.text):match("^[^\r\n]*") or "")
    startRowsSig = nil
  elseif t == "key" then
    local code, ch = e.code, e.char
    if code == 1 then
      closeOverlay()
    elseif code == 200 then Start.sel = max(1, Start.sel - 1)
    elseif code == 208 then Start.sel = Start.sel + 1
    elseif code == 28 or code == 156 then
      for _, r in ipairs(Start.rows()) do
        if r.app and r.n == Start.sel then startLaunch(r.app) return end
      end
    elseif code == 14 then
      Start.search = unicode.sub(Start.search, 1, max(0, unicode.len(Start.search) - 1))
      Start.sel, Start.scroll, startRowsSig = 1, 0, nil
    elseif ch and ch >= 32 and ch ~= 127 and not e.ctrl then
      Start.search = Start.search .. unicode.char(ch)
      Start.sel, Start.scroll, startRowsSig = 1, 0, nil
    end
    local idx
    for i, r in ipairs(Start.rows()) do
      if r.app and r.n == Start.sel then idx = i end
    end
    if idx then
      if idx <= Start.scroll then Start.scroll = max(0, idx - 1) end
      if idx > Start.scroll + (Start.visible or 1) then Start.scroll = idx - (Start.visible or 1) end
    end
  end
end

appMenu = function(app, x, y)
  local s = System.settings
  local function has(list)
    for _, id in ipairs(list or {}) do
      if id == app.id then return true end
    end
    return false
  end
  local function toggle(key)
    local list = s[key]
    if has(list) then
      for i = #list, 1, -1 do
        if list[i] == app.id then table.remove(list, i) end
      end
    else
      list[#list + 1] = app.id
    end
    System.saveSettings()
    startRowsSig = nil
    invalidateBg()
  end
  local entries = {
    {text = "Открыть", action = function() closeOverlay() Desktop.launchOrFocus(app) end},
    {text = "Новое окно", action = function() closeOverlay() Desktop.launch(app.path) end},
    {separator = true},
    {text = has(s.pinned) and "Изъять из панели задач" or "Закрепить на панели задач", action = function() toggle("pinned") end},
    {text = has(s.tiles) and "Убрать из недавних" or "Показывать в недавних", action = function() toggle("tiles") end},
  }
  if System.exists(System.STORE .. "/" .. app.id .. ".app") then
    entries[#entries + 1] = {separator = true}
    entries[#entries + 1] = {text = "Удалить", action = function() closeOverlay() Desktop.uninstall(app) end}
  end
  GUI.menu(x, y, entries)
end

-- ---------- центр поддержки
local Action = {kind = "action"}
Desktop.Action = Action

function Action.geom()
  local w = min(42, W - 2)
  local h = min(24, H - TB - 1)
  return {x = W - w + 1, y = H - TB - h + 1, w = w, h = h}
end

function Action.open()
  for _, n in ipairs(Desktop.history) do n.unread = nil end
end

function Action.contains(px, py)
  local g = Action.geom()
  return px >= g.x and px < g.x + g.w and py >= g.y and py < g.y + g.h
end

function Action.toggleHit(e)
  local g = taskbarGeometry()
  return e.x >= g.notifX1 and e.x <= g.notifX2
end

function Action.draw()
  local g = Action.geom()
  Screen.rect(g.x + 1, g.y + 1, g.w, g.h - 1, 0x000000, nil, nil, 0.35)
  Screen.rect(g.x, g.y, g.w, g.h, C.start, nil, " ")
  GUI.gloss(g.x, g.y, g.w, C.startHeadTop, C.startHead)
  Screen.text(g.x + 2, g.y, 0xFFFFFF, "⚑ Центр поддержки", C.startHead)
  Screen.text(g.x + g.w - 14, g.y, 0xE4F0FB, "Очистить всё", C.startHead)
  Action.hits = {}
  local y = g.y + 2
  local limit = g.y + g.h - 8
  if #Desktop.history == 0 then
    Screen.text(g.x + 2, y, C.startDim, "Новых сообщений нет", C.start)
  end
  for _, n in ipairs(Desktop.history) do
    if y + 3 > limit then break end
    Screen.rect(g.x + 1, y, g.w - 2, 3, C.startHover, nil, " ")
    Screen.text(g.x + 2, y, C.startHead, GUI.fit(n.title, g.w - 12), C.startHover)
    Screen.text(g.x + g.w - 8, y, C.startDim, n.time or "", C.startHover)
    local lines = GUI.wrap(n.text, g.w - 6)
    for k = 1, min(2, #lines) do
      Screen.text(g.x + 2, y + k, C.startText, GUI.fit(lines[k], g.w - 5), C.startHover)
    end
    y = y + 4
  end
  local qy = g.y + g.h - 6
  Screen.text(g.x + 2, qy - 1, C.startDim, "Быстрые действия", C.start)
  local dark = System.settings.theme == "dark"
  local quick = {
    {"Панель управления", false, function() closeOverlay() Desktop.launchById("Settings") end},
    {dark and "Тёмная тема: вкл" or "Тёмная тема: выкл", dark, function()
      local s = System.settings
      s.theme = dark and "light" or "dark"
      System.saveSettings()
      Desktop.applyTheme()
    end},
    {"Магазин", false, function() closeOverlay() Desktop.launchById("Store") end},
  }
  local tw = floor((g.w - 5) / 2)
  for i, qa in ipairs(quick) do
    local col, row = (i - 1) % 2, floor((i - 1) / 2)
    local qx, yy = g.x + 2 + col * (tw + 1), qy + row * 3
    local top = qa[2] and C.selectTop or C.buttonTop
    local bot = qa[2] and C.accent or C.button
    GUI.bevel(qx, yy, tw, 2, top, bot, qa[2] and C.selectEdge or C.buttonEdge)
    Screen.text(qx + 1, yy, qa[2] and C.accentText or C.buttonText, GUI.fit(qa[1], tw - 2))
    Action.hits[#Action.hits + 1] = {x1 = qx, x2 = qx + tw - 1, y1 = yy, y2 = yy + 1, fn = qa[3]}
  end
end

function Action.event(e)
  if e.type == "touch" and e.button == 0 then
    local g = Action.geom()
    if e.y == g.y and e.x >= g.x + g.w - 14 then
      Desktop.history = {}
      return
    end
    for _, h in ipairs(Action.hits or {}) do
      if e.x >= h.x1 and e.x <= h.x2 and e.y >= h.y1 and e.y <= h.y2 then
        h.fn()
        return
      end
    end
  elseif e.type == "key" and e.code == 1 then
    closeOverlay()
  end
end

-- ---------- часы и календарь
local Clock = {kind = "clock"}
Desktop.Clock = Clock

function Clock.geom()
  local w, h = 38, 20
  return {x = W - w + 1, y = H - TB - h + 1, w = w, h = h}
end

function Clock.open()
  Clock.year, Clock.month = tonumber(System.date("%Y")), tonumber(System.date("%m"))
end

function Clock.contains(px, py)
  local g = Clock.geom()
  return px >= g.x and px < g.x + g.w and py >= g.y and py < g.y + g.h
end

function Clock.toggleHit(e)
  local g = taskbarGeometry()
  return e.x >= g.clockX1 and e.x <= g.clockX2
end

function Clock.draw()
  local g = Clock.geom()
  Screen.rect(g.x + 1, g.y + 1, g.w, g.h - 1, 0x000000, nil, nil, 0.35)
  Screen.rect(g.x, g.y, g.w, g.h, C.start, nil, " ")
  GUI.gloss(g.x, g.y, g.w, C.startHeadTop, C.startHead)
  local ty, tm, td = tonumber(System.date("%Y")), tonumber(System.date("%m")), tonumber(System.date("%d"))
  Screen.text(g.x + 2, g.y, 0xFFFFFF, System.date("%H:%M:%S"), C.startHead)
  Screen.text(g.x + 12, g.y, 0xE4F0FB, WEEKDAYS[System.weekday(ty, tm, td) + 1], C.startHead)
  GUI.bigText(g.x + 4, g.y + 2, System.clock(), C.startHead)
  Screen.text(g.x + 3, g.y + 8, C.startDim, td .. " " .. MONTHS_GEN[tm] .. " " .. ty, C.start)
  Screen.rect(g.x + 1, g.y + 10, g.w - 2, 1, C.startHover, nil, " ")
  local head = MONTHS[Clock.month] .. " " .. Clock.year
  Screen.text(g.x + floor((g.w - unicode.len(head)) / 2), g.y + 10, C.startText, head, C.startHover)
  Screen.text(g.x + 2, g.y + 10, C.startHead, "‹", C.startHover)
  Screen.text(g.x + g.w - 3, g.y + 10, C.startHead, "›", C.startHover)
  for i, d in ipairs(DOW) do
    Screen.text(g.x + 5 + (i - 1) * 4, g.y + 12, i > 5 and C.startHead or C.startDim, d, C.start)
  end
  local first = System.weekday(Clock.year, Clock.month, 1)
  local days = System.daysInMonth(Clock.year, Clock.month)
  for d = 1, days do
    local idx = first + d - 1
    local col, row = idx % 7, floor(idx / 7)
    local cx, cy = g.x + 5 + col * 4, g.y + 13 + row
    local today = Clock.year == ty and Clock.month == tm and d == td
    local s = tostring(d)
    if today then
      GUI.gloss(cx, cy, 3, C.selectTop, C.accent)
      Screen.text(cx + 2 - unicode.len(s) + 1, cy, C.accentText, s)
    else
      Screen.text(cx + 2 - unicode.len(s) + 1, cy, C.startText, s, C.start)
    end
  end
end

function Clock.event(e)
  if e.type == "touch" and e.button == 0 then
    local g = Clock.geom()
    if e.y == g.y + 10 then
      local delta = e.x <= g.x + 5 and -1 or (e.x >= g.x + g.w - 6 and 1 or 0)
      if delta ~= 0 then
        Clock.month = Clock.month + delta
        if Clock.month < 1 then Clock.month, Clock.year = 12, Clock.year - 1 end
        if Clock.month > 12 then Clock.month, Clock.year = 1, Clock.year + 1 end
      end
    end
  elseif e.type == "key" and e.code == 1 then
    closeOverlay()
  end
end

closeOverlay = function()
  if overlay then
    overlay = nil
    Desktop.dirty = true
  end
end

openOverlay = function(o)
  if o.open then o.open() end
  overlay = o
  Desktop.dirty = true
end

-- ---------- всплывающие сообщения
local function drawToasts()
  local y = H - TB
  local w = min(40, W - 2)
  for i = #Desktop.toasts, 1, -1 do
    local t = Desktop.toasts[i]
    local lines = GUI.wrap(t.text, w - 5)
    local n = min(#lines, 2)
    local h = n + 3
    local x, top = W - w, y - h
    if overlay and overlay.kind == "action" then x = x - Action.geom().w end
    if Desktop.effectsEnabled() then
      Screen.rect(x + 1, top + 1, w, h, 0x000000, nil, nil, 0.35)
    end
    Screen.rect(x, top, w, h, C.toast, nil, " ")
    for r = 0, h - 1 do
      Screen.set(x, top + r, nil, C.toastEdge, "▏")
      Screen.set(x + w - 1, top + r, nil, C.toastEdge, "▕")
    end
    GUI.gloss(x + 1, top, w - 2, Screen.blend(0xFFFFFF, C.toast, 0.6), C.toast)
    Screen.text(x + 2, top + 1, C.toastText, GUI.fit(t.title, w - 8), C.toast)
    Screen.text(x + w - 3, top + 1, C.toastDim, "✕", C.toast)
    for k = 1, n do
      Screen.text(x + 2, top + 1 + k, C.toastDim, GUI.fit(lines[k], w - 5), C.toast)
    end
    y = top - 1
  end
end

-- ---------- рисование кадра
function Desktop.render()
  if not screenOk then return end
  Desktop.lastRender = computer.uptime()
  local n = W * H
  if not bgPack or #bgPack ~= n then
    bgPack, bgCh = {}, {}
    for i = 1, n do bgPack[i], bgCh[i] = 0, " " end
    bgValid = false
  end
  Screen.resetClip()
  -- Кэш фона тоже занимает ОЗУ, поэтому в лёгком режиме его нет:
  -- ровная заливка и так рисуется быстро.
  if Desktop.effectsEnabled() then
    if not bgValid then
      drawWallpaper()
      Screen.snapshot(bgPack, bgCh)
      bgValid = true
    else
      Screen.restore(bgPack, bgCh)
    end
  else
    drawWallpaper()
  end
  -- Значки не входят в кэш: их можно перетаскивать без пересчёта обоев.
  drawDeskIcons()
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
  drawTaskbar()
  drawToasts()
  if overlay then
    local ok, err = xpcall(overlay.draw, tb)
    if not ok then overlay = nil bad = bad or {} bad[#bad + 1] = {nil, err} end
  end
  for _, m in ipairs(Desktop.modals) do
    Screen.resetClip()
    local ok, err = xpcall(m.draw, tb, m, true)
    if not ok then
      m.closed = true
      bad = bad or {}
      bad[#bad + 1] = {nil, err}
    end
  end
  Screen.resetClip()
  local okUpdate, errUpdate = pcall(Screen.update)
  if okUpdate then
    updateFails = 0
  else
    System.log("GPU: " .. tostring(errUpdate))
    Screen.invalidate()
    Desktop.dirty = true
    updateFails = updateFails + 1
    if updateFails > 20 then error(errUpdate, 0) end
  end
  if bad then
    for _, b in ipairs(bad) do
      if b[1] then removeWindow(b[1]) end
      Desktop.reportError(b[2])
    end
  end
end

-- ---------- события
local function windowAt(x, y)
  for i = #Desktop.windows, 1, -1 do
    local w = Desktop.windows[i]
    if not w.minimized and w:hit(x, y) then return w end
  end
end

local function desktopMenu(e)
  GUI.menu(e.x, e.y, {
    {text = "Вид", disabled = true},
    {text = "Обновить", action = function() Desktop.refreshIcons(true) end},
    {separator = true},
    {text = "Создать папку", action = function()
      local name = GUI.prompt("Новая папка", "Имя папки:", "Новая папка")
      if name and name ~= "" and not name:find("/", 1, true) then System.mkdirs("/Users/Desktop/" .. name) Desktop.refreshIcons(true) end
    end},
    {text = "Создать текстовый документ", action = function()
      local name = GUI.prompt("Новый документ", "Имя файла:", "Новый документ.txt")
      if name and name ~= "" and not name:find("/", 1, true) then System.writeFile("/Users/Desktop/" .. name, "") Desktop.refreshIcons(true) end
    end},
    {text = "Упорядочить значки", action = function() Desktop.resetIconPositions() end},
    {separator = true},
    {text = "Разрешение экрана", action = function() Desktop.launchById("Settings", {page = "system"}) end},
    {text = "Персонализация", action = function() Desktop.launchById("Settings", {page = "personal"}) end},
  })
end

local function iconMenu(idx, e)
  local it = deskIcons[idx]
  local entries = {{text = "Открыть", action = it.open}}
  if it.trash then
    entries[#entries + 1] = {text = "Очистить корзину", action = function()
      if GUI.confirm("Очистка корзины", "Удалить все файлы из корзины безвозвратно?", "Очистить", "Отмена", true) then
        System.remove("/Users/.Trash")
        System.mkdirs("/Users/.Trash")
        Desktop.notify("Корзина очищена")
      end
    end}
  elseif it.isFile then
    entries[#entries + 1] = {separator = true}
    entries[#entries + 1] = {text = "Удалить", action = function()
      if GUI.confirm("Удаление", "Переместить «" .. it.label .. "» в корзину?", "Удалить", "Отмена", true) then
        System.mkdirs("/Users/.Trash")
        local target = "/Users/.Trash/" .. System.basename(it.path)
        if System.exists(target) then System.remove(target) end
        System.rename(it.path, target)
        Desktop.refreshIcons(true)
      end
    end}
  end
  GUI.menu(e.x, e.y, entries)
end

local function onTouch(e)
  -- Сброс прошлого захвата: в OC «drop» приходит не всегда.
  dragState, resizeState, iconDrag = nil, nil, nil
  if preciseScreen then Desktop.setPrecise(false) end
  if overlay then
    if overlay.contains(e.x, e.y) then
      overlay.event(e)
      return
    end
    local was = overlay
    closeOverlay()
    if e.y > H - TB and was.toggleHit(e) then return end
  end
  if e.y > H - TB then return taskbarTouch(e) end
  local win = windowAt(e.x, e.y)
  if not win then
    local i = deskIconAt(e.x, e.y)
    if i then
      if deskSel ~= i then iconLayerDirty() end
      deskSel = i
      if e.button == 1 then
        iconMenu(i, e)
      else
        -- Открытие по отпусканию мыши: перетаскивание не может случайно
        -- сработать как двойной щелчок, даже если перед этим был клик.
        local x, y = deskPos(i)
        iconDrag = {index = i, dx = e.x - x, dy = e.y - y, x = x, y = y,
                    startX = e.x, startY = e.y, moved = false}
        iconLayerDirty()
      end
    else
      if deskSel ~= nil then iconLayerDirty() end
      deskSel = nil
      if e.button == 1 then desktopMenu(e) end
    end
    return
  end
  if deskSel ~= nil then iconLayerDirty() end
  deskSel = nil
  if win ~= Desktop.top() then Desktop.focus(win) end
  if e.y == win.y then
    if e.button ~= 0 then return end
    local btn = win:titleButton(e.x)
    if btn == "close" then
      Desktop.closeWindow(win)
    elseif btn == "min" then
      win.minimized = true
    elseif btn == "max" then
      Desktop.toggleMaximize(win)
    else
      local now = computer.uptime()
      if lastTitle.win == win and now - lastTitle.t < 0.5
        and math.abs(e.x - (lastTitle.x or 0)) <= 2 then
        lastTitle.t = 0
        Desktop.toggleMaximize(win)
      else
        lastTitle.win, lastTitle.t, lastTitle.x = win, now, e.x
        if not win.maximized then
          dragState = {win = win, dx = e.x - win.x, dy = e.y - win.y, moved = false}
        end
      end
    end
    return
  end
  if win.resizable and not win.maximized and e.y == win.y + win.h - 1 and e.x >= win.x + win.w - 3 then
    resizeState = {win = win}
    return
  end
  win:dispatch(e)
end

local function onDrag(e)
  if iconDrag then
    if math.abs(e.x - iconDrag.startX) >= 2 or math.abs(e.y - iconDrag.startY) >= 1 then
      iconDrag.moved = true
      iconDrag.x = max(1, min(W - CELL_W + 1, e.x - iconDrag.dx))
      iconDrag.y = max(1, min(H - TB - CELL_H, e.y - iconDrag.dy))
      iconLayerDirty()
    end
    return
  end
  if dragState then
    local win = dragState.win
    local x = max(2 - win.w + 8, min(W - 8, e.x - dragState.dx))
    local y = max(1, min(H - TB - 1, e.y - dragState.dy))
    if x ~= win.x or y ~= win.y then
      win.x, win.y = x, y
      dragState.moved = true
      lastTitle.t = 0
      -- кэш фона остаётся нетронутым: изменилось только окно
      Desktop.dirty = true
    end
    return
  end
  if resizeState then
    local win = resizeState.win
    win:resize(max(win.minW, min(W - win.x + 1, e.x - win.x + 1)), max(win.minH, min(H - TB - win.y + 1, e.y - win.y + 1)))
    Desktop.dirty = true
    return
  end
  local win = Desktop.top()
  if win then win:dispatch(e) end
end

local function onDrop(e)
  if iconDrag then
    if iconDrag.moved then
      local x, y = snapIcon(iconDrag.x, iconDrag.y, iconDrag.index)
      iconPositions[iconKey(deskIcons[iconDrag.index])] = {x, y}
      iconPosDirty = true
      saveIconPositions()
      deskLast.t = 0 -- мазок не считается щелчком
      invalidateBg()
    else
      local i = iconDrag.index
      local now = computer.uptime()
      if deskLast.idx == i and now - deskLast.t < 0.6 then
        deskLast.t = 0
        deskIcons[i].open()
      else
        deskLast.idx, deskLast.t = i, now
      end
    end
    iconDrag = nil
    return
  end
  if dragState then
    if e.y <= 1 and dragState.win.resizable and not dragState.win.maximized then
      Desktop.toggleMaximize(dragState.win)
    end
    dragState = nil
    return
  end
  if resizeState then
    resizeState = nil
    return
  end
  local win = Desktop.top()
  if win then win:dispatch(e) end
end
local function globalKeys(e)
  local code = e.code
  if e.ctrl and e.shift and code == 1 then
    Desktop.launchById("Monitor")
    return true
  elseif e.ctrl and code == 1 then
    if overlay and overlay.kind == "start" then closeOverlay() else openOverlay(Start) end
    return true
  elseif e.alt and code == 15 then
    for i = #Desktop.windows - 1, 1, -1 do
      if not Desktop.windows[i].minimized then
        Desktop.focus(Desktop.windows[i])
        break
      end
    end
    return true
  elseif e.alt and code == 62 then
    local top = Desktop.top()
    if top then Desktop.closeWindow(top) end
    return true
  end
  return false
end

local function dispatch(e)
  Desktop.dirty = true
  local modal = Desktop.modals[#Desktop.modals]
  if modal then
    modal:event(e)
    return
  end
  local t = e.type
  if t == "key" and globalKeys(e) then return end
  if overlay and (t == "key" or t == "paste") then
    overlay.event(e)
    return
  end
  if t == "touch" then onTouch(e)
  elseif t == "drag" then onDrag(e)
  elseif t == "drop" then onDrop(e)
  elseif t == "scroll" then
    if overlay and overlay.contains(e.x, e.y) then overlay.event(e) return end
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
    end
  elseif name == "touch" or name == "drag" or name == "drop" then
    -- screen.setPrecise(false) обеспечивает те же целые координаты, что GPU.
    -- При мазке Paint сохраняем дробные fx/fy, но окна всё равно используют ячейки.
    local x, y = tonumber(sig[3]), tonumber(sig[4])
    if x and y then
      dispatch({type = name, x = floor(x), y = floor(y), fx = x, fy = y, button = sig[5], player = sig[6]})
    end
  elseif name == "scroll" then
    dispatch({type = "scroll", x = floor(sig[3]), y = floor(sig[4]), dir = sig[5]})
  elseif name == "clipboard" then
    dispatch({type = "paste", text = sig[3]})
  elseif name == "screen_resized" then
    Desktop.resync()
  elseif name == "component_added" or name == "component_removed" then
    local t = sig[3]
    if t == "gpu" or t == "screen" then Desktop.rebind() end
  elseif name == "cubeos_launch" then
    local arg3 = sig[3] and tostring(sig[3]) or nil
    local args = nil
    if arg3 then
      args = {url = arg3, page = arg3, path = arg3}
    end
    Desktop.launchById(tostring(sig[2]), args, true)
    Desktop.dirty = true
  end
end

function Desktop.runModal(modal)
  modal.closed = false
  Desktop.modals[#Desktop.modals + 1] = modal
  Desktop.dirty = true
  local ok, err = xpcall(function()
    while not modal.closed do
      Desktop.step(0.5)
    end
  end, tb)
  for i, m in ipairs(Desktop.modals) do
    if m == modal then table.remove(Desktop.modals, i) break end
  end
  Desktop.dirty = true
  if not ok then error(err, 0) end
  return modal.result
end

function Desktop.step(maxWait)
  local timeout = maxWait or 1
  for _, w in ipairs(Desktop.windows) do
    if w.onTick and w.tickInterval then timeout = min(timeout, w.tickInterval) end
  end
  if #Desktop.toasts > 0 then timeout = min(timeout, 0.5) end
  if Desktop.dirty then
    local interval = (dragState or resizeState or iconDrag) and INTERACTIVE_INTERVAL or RENDER_INTERVAL
    local wait = interval - (computer.uptime() - (Desktop.lastRender or -999))
    timeout = wait > 0 and min(timeout, wait) or 0
  end

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

  if now - (Desktop.lastMemCheck or 0) > 2 then
    Desktop.lastMemCheck = now
    if computer.freeMemory() < 100 * 1024 then
      System.collect()
      if computer.freeMemory() < 70 * 1024 then Desktop.recoverMemory() end
    end
  end

  if now - (Desktop.lastIconScan or 0) > 3 then
    Desktop.lastIconScan = now
    Desktop.refreshIcons()
  end

  local tray = trayText() .. System.clock() .. #Desktop.history
  if tray ~= Desktop.lastTray then
    Desktop.lastTray = tray
    Desktop.dirty = true
  end

  local interval = (dragState or resizeState or iconDrag) and INTERACTIVE_INTERVAL or RENDER_INTERVAL
  if Desktop.dirty and computer.uptime() - (Desktop.lastRender or -999) >= interval then
    Desktop.dirty = false
    Desktop.render()
  end
end

local function fitResolution()
  local mw, mh = gpu.maxResolution()
  -- После буфера экрана оставляем ~300 КБ на систему и окна:
  -- этого хватает режиму 80×25 даже на одной планке Tier 3.5.
  local budget = computer.freeMemory() + Screen.cost(W, H) - 300 * 1024
  local capW, capH = W, H
  local saved = System.settings.res
  if not SAFE_MODE and type(saved) == "table" and saved[1] and saved[2] and saved[1] <= mw and saved[2] <= mh then
    capW, capH = saved[1], saved[2]
  end
  for _, p in ipairs(PRESETS) do
    if p[1] <= capW and p[2] <= capH and p[1] <= mw and p[2] <= mh and Screen.cost(p[1], p[2]) <= budget then
      if p[1] ~= W or p[2] ~= H then Desktop.setResolution(p[1], p[2]) end
      return
    end
  end
  Desktop.setResolution(min(80, mw), min(25, mh))
end

function Desktop.run()
  gpu = component.proxy(component.list("gpu")())
  W, H = gpu.getResolution()
  Screen.init(gpu, W, H)
  fitResolution()
  Desktop.setPrecise(false)
  Desktop.applyTheme()
  for _, p in ipairs({"/Users", "/Users/Documents", "/Users/Desktop", "/Users/Downloads", "/Users/Pictures", "/Users/Logs", "/Users/.Trash"}) do
    System.mkdirs(p)
  end
  Desktop.reloadApps()
  Desktop.refreshIcons(true)
  if SAFE_MODE then
    Desktop.notify("Безопасный режим: прошлая загрузка не завершилась", "CubeOS")
  else
    Desktop.notify("Система готова к работе", "CubeOS 7")
    if not System.settings.welcomed then Desktop.welcome() end
  end
  Desktop.render()
  pcall(System.remove, BOOT_FLAG)

  local fails, lastFail = 0, 0
  while Desktop.running do
    local ok, err = xpcall(Desktop.step, tb, 1)
    if not ok then
      System.log("LOOP " .. tostring(err))
      local now = computer.uptime()
      if now - lastFail > 15 then fails = 0 end
      fails, lastFail = fails + 1, now
      if isMemoryError(err) then Desktop.recoverMemory() end
      Screen.invalidate()
      Desktop.dirty = true
      if fails >= 6 then error(err, 0) end
    end
  end
end

return Desktop
]]},
  {"/System/Store/Calendar.app/Info.lua", [[
return {
  title = "Календарь", short = "Календарь", order = 21, category = "Продуктивность", version = "1.0", author = "Команда CubeOS",
  desc = "Календарь на месяц с выделением сегодняшнего дня. К любой дате можно добавить заметку — дни с заметками отмечены точкой. Листайте месяцы стрелками или клавишами PageUp и PageDown, двигайтесь по дням стрелками.",
  icon = {
    pal = {r = 0xE74856, w = 0xFFFFFF, k = 0x444444},
    "rrrrrrrr",
    "rrrrrrrr",
    "wwwwwwww",
    "wkwkwkww",
    "wwwwwwww",
    "wkwkwkww",
    "wwwwwwww",
    "wwwwwwww",
  },
}
]]},
  {"/System/Store/Calendar.app/Main.lua", [[
-- Календарь с заметками
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local DIR = "/Users/Calendar"
System.mkdirs(DIR)
local notes = System.loadData(DIR .. "/notes.lua")
if type(notes) ~= "table" then notes = {} end
local function saveNotes() System.writeFile(DIR .. "/notes.lua", System.serialize(notes)) end

local MONTHS = {"Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"}
local MONTHS_GEN = {"января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"}
local DOW = {"Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"}
local WEEKDAYS = {"понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"}

local today = {y = tonumber(System.date("%Y")), m = tonumber(System.date("%m")), d = tonumber(System.date("%d"))}
local sel = {y = today.y, m = today.m, d = today.d}
local view = {y = today.y, m = today.m}

local win = ctx.window(68, 27, "Календарь")
local c = win.content

local function key(y, m, d) return string.format("%04d-%02d-%02d", y, m, d) end

local title, noteLabel, noteInput, grid

local function updateTexts()
  title:setText(MONTHS[view.m] .. " " .. view.y)
  local wd = System.weekday(sel.y, sel.m, sel.d)
  noteLabel:setText(WEEKDAYS[wd + 1] .. ", " .. sel.d .. " " .. MONTHS_GEN[sel.m] .. " " .. sel.y)
  noteInput:setText(notes[key(sel.y, sel.m, sel.d)] or "")
end

local function setView(y, m)
  if m < 1 then m, y = 12, y - 1 end
  if m > 12 then m, y = 1, y + 1 end
  view.y, view.m = y, m
  updateTexts()
end

local function select(y, m, d)
  sel.y, sel.m, sel.d = y, m, d
  if y ~= view.y or m ~= view.m then view.y, view.m = y, m end
  updateTexts()
end

local function stepDay(delta)
  local y, m, d = sel.y, sel.m, sel.d
  local dir = delta > 0 and 1 or -1
  for _ = 1, math.abs(delta) do
    d = d + dir
    if d < 1 then
      m = m - 1
      if m < 1 then m, y = 12, y - 1 end
      d = System.daysInMonth(y, m)
    elseif d > System.daysInMonth(y, m) then
      d, m = 1, m + 1
      if m > 12 then m, y = 1, y + 1 end
    end
  end
  select(y, m, d)
end

-- ---------- сетка месяца
local Grid = GUI.class()

local function cellDate(cell)
  local first = System.weekday(view.y, view.m, 1)
  local n = cell - first + 1
  local dim = System.daysInMonth(view.y, view.m)
  if n < 1 then
    local pm, py = view.m - 1, view.y
    if pm < 1 then pm, py = 12, py - 1 end
    return py, pm, System.daysInMonth(py, pm) + n, false
  elseif n > dim then
    local nm, ny = view.m + 1, view.y
    if nm > 12 then nm, ny = 1, ny + 1 end
    return ny, nm, n - dim, false
  end
  return view.y, view.m, n, true
end

function Grid:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, C.win, nil, " ")
  for i, d in ipairs(DOW) do
    Screen.text(ax + (i - 1) * 9 + 3, ay, i > 5 and C.accent or C.dim, d, C.win)
  end
  for cell = 0, 41 do
    local col, row = cell % 7, floor(cell / 7)
    local x, y = ax + col * 9, ay + 1 + row * 3
    local yy, mm, dd, inMonth = cellDate(cell)
    local isToday = yy == today.y and mm == today.m and dd == today.d
    local isSel = yy == sel.y and mm == sel.m and dd == sel.d
    local bg = isToday and C.accent or (isSel and Screen.blend(C.accent, C.win, 0.3) or C.winAlt)
    local fg = isToday and C.accentText or (inMonth and (col >= 5 and C.accent or C.text) or C.dim)
    Screen.rect(x, y, 8, 2, bg, nil, " ")
    Screen.text(x + 1, y, fg, tostring(dd), bg)
    local note = notes[key(yy, mm, dd)]
    if note and note ~= "" then
      Screen.text(x + 6, y + 1, isToday and C.accentText or C.accent, "●", bg)
      Screen.text(x + 1, y + 1, isToday and C.accentText or C.dim, GUI.fit(note, 5), bg)
    end
    if isSel and not isToday then Screen.text(x, y, C.accent, "▏", bg) Screen.text(x, y + 1, C.accent, "▏", bg) end
  end
end

function Grid:onEvent(e, ax, ay)
  if e.type ~= "touch" then return false end
  self:focus()
  local col, row = floor((e.x - ax) / 9), floor((e.y - ay - 1) / 3)
  if col >= 0 and col < 7 and row >= 0 and row < 6 and (e.x - ax) % 9 < 8 then
    local yy, mm, dd = cellDate(row * 7 + col)
    select(yy, mm, dd)
  end
  return true
end

function Grid:onKey(e)
  local code = e.code
  if code == 203 then stepDay(-1)
  elseif code == 205 then stepDay(1)
  elseif code == 200 then stepDay(-7)
  elseif code == 208 then stepDay(7)
  elseif code == 201 then setView(view.y, view.m - 1)
  elseif code == 209 then setView(view.y, view.m + 1)
  elseif code == 199 then select(today.y, today.m, today.d)
  else return false end
  return true
end

-- ---------- интерфейс
local prev = c:add(GUI.button(2, 1, 4, 1, " ‹ ", function() setView(view.y, view.m - 1) end))
local nxt = c:add(GUI.button(7, 1, 4, 1, " › ", function() setView(view.y, view.m + 1) end))
title = c:add(GUI.label(13, 1, "", "accent"))
c:add(GUI.button(c.w - 14, 1, 12, 1, "Сегодня", function() select(today.y, today.m, today.d) end, "primary"))

grid = c:add(GUI.new(Grid, 3, 3, 62, 19))
grid.focusable = true

noteLabel = c:add(GUI.label(3, 23, "", "text"))
noteInput = c:add(GUI.input(3, 24, 62, "", "Заметка на этот день — Enter, чтобы сохранить"))
noteInput.onSubmit = function(self, text)
  local k = key(sel.y, sel.m, sel.d)
  if text == "" then notes[k] = nil else notes[k] = text end
  saveNotes()
  Desktop.notify(text == "" and "Заметка удалена" or "Заметка сохранена", "Календарь")
  grid:focus()
end
c:add(GUI.label(3, 25, "Стрелки — день, PageUp/PageDown — месяц, Home — сегодня", "dim"))
c.focused = grid
updateTexts()
]]},
  {"/System/Store/Clock.app/Info.lua", [[
return {
  title = "Часы", short = "Часы", order = 22, category = "Продуктивность", version = "1.0", author = "Команда CubeOS",
  desc = "Часы с мировым временем, таймер, секундомер с кругами и будильники. Таймер и секундомер продолжают идти, пока приложение открыто, даже если вы переключились на другую вкладку. Будильник звонит, пока окно «Часы» открыто.",
  icon = {
    pal = {b = 0x0078D7, w = 0xFFFFFF},
    "..bbbb..",
    ".bwwwwb.",
    "bwwwbwwb",
    "bwwwbwwb",
    "bwwwbbwb",
    "bwwwwwwb",
    ".bwwwwb.",
    "..bbbb..",
  },
}
]]},
  {"/System/Store/Clock.app/Main.lua", [[
-- Часы: мировое время, таймер, секундомер, будильник
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local computer, unicode = computer, unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local DIR = "/Users/Clock"
System.mkdirs(DIR)
local alarms = System.loadData(DIR .. "/alarms.lua")
if type(alarms) ~= "table" then alarms = {} end
local function saveAlarms() System.writeFile(DIR .. "/alarms.lua", System.serialize(alarms)) end

local win = ctx.window(72, 27, "Часы")
local c = win.content
local view = c:add(GUI.panel(1, 3, win.w, win.h - 3, "win"))
local current = "clock"
local rebuild

local timer = {total = 300, left = 300, running = false, endsAt = 0}
local watch = {running = false, base = 0, elapsed = 0, laps = {}}
local ring = {until_ = 0, label = "", nextBeep = 0}
local lastAlarmMinute

local WORLD = {{"Москва", 3}, {"Лондон", 0}, {"Берлин", 1}, {"Нью-Йорк", -5}, {"Токио", 9}, {"Сидней", 10}}

-- ---------- крупный дисплей
local Big = GUI.class()
function Big:drawSelf(ax, ay)
  local text = self.getText()
  local tw = GUI.bigWidth(text)
  GUI.bigText(ax + max(0, floor((self.w - tw) / 2)), ay, text, self.color and GUI.rc(self.color) or C.text)
end
local function big(y, getText, color)
  local b = GUI.new(Big, 1, y, view.w, 5)
  b.getText, b.color = getText, color
  return view:add(b)
end

local function hms(sec)
  sec = max(0, floor(sec + 0.0001))
  local h, m, s = floor(sec / 3600), floor(sec / 60) % 60, sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%02d:%02d", m, s)
end

-- ---------- вкладки
local function viewClock()
  big(2, function() return System.date("%H:%M:%S") end)
  local d = view:add(GUI.label(1, 8, "", "dim", nil, view.w, "center"))
  d.update = function()
    local y, m, dd = tonumber(System.date("%Y")), tonumber(System.date("%m")), tonumber(System.date("%d"))
    local names = {"понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"}
    local gen = {"января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"}
    d:setText(names[System.weekday(y, m, dd) + 1] .. ", " .. dd .. " " .. gen[m] .. " " .. y)
  end
  d.update()
  view:add(GUI.label(4, 11, "Мировое время", "text"))
  for i, w in ipairs(WORLD) do
    local row = 12 + i
    view:add(GUI.label(4, row, w[1], "text"))
    local t = view:add(GUI.label(20, row, "", "accent", nil, 8))
    t.update = function() t:setText(System.date("%H:%M", System.time() + w[2] * 3600, true)) end
    t.update()
    view:add(GUI.label(30, row, string.format("UTC%+d", w[2]), "dim"))
  end
end

local function setTimer(sec)
  timer.total, timer.left, timer.running = sec, sec, false
  rebuild()
end

local function viewTimer()
  big(2, function() return hms(timer.left) end, timer.left <= 0 and "danger" or "text")
  view:add(GUI.label(4, 9, "Быстрая установка", "dim"))
  local x = 4
  for _, m in ipairs({1, 3, 5, 10, 15, 30, 60}) do
    view:add(GUI.button(x, 10, 7, 1, m .. " мин", function() setTimer(m * 60) end))
    x = x + 8
  end
  view:add(GUI.label(4, 12, "Свой интервал, минут:", "dim"))
  local input = view:add(GUI.input(26, 12, 8, tostring(floor(timer.total / 60))))
  input.onSubmit = function(_, t)
    local v = tonumber(t)
    if v and v > 0 and v <= 600 then setTimer(floor(v * 60)) end
  end
  view:add(GUI.button(4, 14, 16, 1, timer.running and "Пауза" or "Старт", function()
    if timer.running then
      timer.left = max(0, timer.endsAt - computer.uptime())
      timer.running = false
    else
      if timer.left <= 0 then timer.left = timer.total end
      timer.endsAt = computer.uptime() + timer.left
      timer.running = true
    end
    rebuild()
  end, "primary"))
  view:add(GUI.button(22, 14, 14, 1, "Сброс", function() setTimer(timer.total) end))
  view:add(GUI.progress(4, 16, view.w - 8, timer.total > 0 and (1 - timer.left / timer.total) or 0))
end

local function watchElapsed()
  return watch.running and (watch.elapsed + computer.uptime() - watch.base) or watch.elapsed
end

local function viewWatch()
  big(2, function()
    local t = watchElapsed()
    local m, s = floor(t / 60), t % 60
    return string.format("%02d:%04.1f", m, s)
  end)
  view:add(GUI.button(4, 9, 16, 1, watch.running and "Стоп" or "Старт", function()
    if watch.running then
      watch.elapsed = watchElapsed()
      watch.running = false
    else
      watch.base, watch.running = computer.uptime(), true
    end
    rebuild()
  end, "primary"))
  view:add(GUI.button(22, 9, 14, 1, "Круг", function()
    if watch.running or watch.elapsed > 0 then
      local t = watchElapsed()
      local last = watch.laps[#watch.laps]
      watch.laps[#watch.laps + 1] = {total = t, split = t - (last and last.total or 0)}
      rebuild()
    end
  end))
  view:add(GUI.button(38, 9, 14, 1, "Сброс", function()
    watch.running, watch.elapsed, watch.laps = false, 0, {}
    rebuild()
  end))
  local list = view:add(GUI.list(4, 11, view.w - 8, view.h - 12, watch.laps))
  list.striped = true
  list.render = function(_, lap, idx, x, y, w, sel, bg)
    local fg = sel and C.accentText or C.text
    Screen.text(x + 1, y, fg, string.format("Круг %d", idx), bg)
    Screen.text(x + 14, y, fg, string.format("%02d:%05.2f", floor(lap.split / 60), lap.split % 60), bg)
    Screen.text(x + 30, y, sel and C.accentText or C.dim, string.format("всего %02d:%05.2f", floor(lap.total / 60), lap.total % 60), bg)
  end
  list.selected = #watch.laps
  list:ensureVisible()
end

local function viewAlarm()
  view:add(GUI.label(4, 1, "Будильники звонят, пока открыто это окно.", "dim"))
  local list = view:add(GUI.list(4, 3, view.w - 8, view.h - 6, alarms))
  list.rowHeight = 2
  list.striped = true
  list.render = function(_, a, _, x, y, w, sel, bg)
    local fg = sel and C.accentText or C.text
    Screen.text(x + 1, y, fg, a.time, bg)
    Screen.text(x + 9, y, sel and C.accentText or (a.on and C.success or C.dim), a.on and "включён" or "выключен", bg)
    Screen.text(x + 1, y + 1, sel and C.accentText or C.dim, GUI.fit(a.label ~= "" and a.label or "Будильник", w - 4), bg)
  end
  list.selected = min(1, #alarms)
  view:add(GUI.button(4, view.h - 2, 14, 1, "Добавить", function()
    local t = GUI.prompt("Новый будильник", "Время (ЧЧ:ММ):", "07:30")
    if not t then return end
    local h, m = t:match("^%s*(%d%d?):(%d%d)%s*$")
    h, m = tonumber(h), tonumber(m)
    if not h or h > 23 or m > 59 then GUI.alert("Будильник", "Введите время вида 07:30.") return end
    local label = GUI.prompt("Новый будильник", "Название (можно пустое):", "") or ""
    alarms[#alarms + 1] = {time = string.format("%02d:%02d", h, m), label = label, on = true}
    saveAlarms()
    rebuild()
  end, "primary"))
  view:add(GUI.button(20, view.h - 2, 16, 1, "Вкл / выкл", function()
    local a = alarms[list.selected]
    if a then a.on = not a.on saveAlarms() end
  end))
  view:add(GUI.button(38, view.h - 2, 12, 1, "Удалить", function()
    if alarms[list.selected] then
      table.remove(alarms, list.selected)
      saveAlarms()
      rebuild()
    end
  end, "danger"))
  view:add(GUI.button(52, view.h - 2, 12, 1, "Стоп звонок", function() ring.until_ = 0 end))
end

local TABS = {{"clock", "Часы"}, {"timer", "Таймер"}, {"watch", "Секундомер"}, {"alarm", "Будильник"}}
local VIEWS = {clock = viewClock, timer = viewTimer, watch = viewWatch, alarm = viewAlarm}

rebuild = function()
  view:clear()
  if not c.tabs then c.tabs = c:add(GUI.panel(1, 1, win.w, 2, "panel")) end
  c.tabs:clear()
  local x = 2
  for _, t in ipairs(TABS) do
    local w = unicode.len(t[2]) + 4
    local b = GUI.button(x, 1, w, 1, t[2], function() current = t[1] rebuild() end)
    b.active = current == t[1]
    if not b.active then b.color, b.textColor = "panel", "text" end
    c.tabs:add(b)
    x = x + w + 1
  end
  VIEWS[current]()
end

-- ---------- фоновая работа
local function beep(freq, dur) pcall(computer.beep, freq, dur) end

win.tickInterval = 0.2
win.onTick = function()
  local now = computer.uptime()
  if timer.running then
    timer.left = timer.endsAt - now
    if timer.left <= 0 then
      timer.left, timer.running = 0, false
      Desktop.notify("Время вышло!", "Таймер")
      ring.until_, ring.label, ring.nextBeep = now + 6, "Таймер", 0
      rebuild()
    end
  end
  local minute = System.date("%H:%M")
  if minute ~= lastAlarmMinute then
    lastAlarmMinute = minute
    for _, a in ipairs(alarms) do
      if a.on and a.time == minute then
        Desktop.notify(a.label ~= "" and a.label or "Будильник", "Будильник " .. a.time)
        ring.until_, ring.label, ring.nextBeep = now + 12, a.label, 0
      end
    end
  end
  if now < ring.until_ and now >= ring.nextBeep then
    beep(880, 0.15)
    ring.nextBeep = now + 0.8
  end
  for _, ch in ipairs(view.children) do
    if ch.update then ch.update() end
  end
  return current ~= "alarm"
end

rebuild()
]]},
  {"/System/Store/Converter.app/Info.lua", [[
return {
  title = "Конвертер", short = "Конвертер", order = 26, category = "Утилиты", version = "1.0", author = "Команда CubeOS",
  desc = "Перевод величин: длина, масса, температура, площадь, объём, скорость, объём данных и время. Есть блоки и тики Minecraft. Результат пересчитывается сразу при вводе.",
  icon = {
    pal = {o = 0xF7630C, w = 0xFFFFFF},
    "........",
    ".oooooo.",
    "......o.",
    "..oo..o.",
    "..oo..o.",
    ".o......",
    ".oooooo.",
    "........",
  },
}
]]},
  {"/System/Store/Converter.app/Main.lua", [[
-- Конвертер величин
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local function factor(name, short, f)
  return {name = name, short = short, to = function(v) return v * f end, from = function(b) return b / f end}
end

local CATS = {
  {"Длина", {factor("миллиметр", "мм", 0.001), factor("сантиметр", "см", 0.01), factor("метр", "м", 1), factor("километр", "км", 1000),
    factor("дюйм", "дюйм", 0.0254), factor("фут", "фут", 0.3048), factor("ярд", "ярд", 0.9144), factor("миля", "миля", 1609.344),
    factor("блок Minecraft", "блок", 1)}},
  {"Масса", {factor("грамм", "г", 0.001), factor("килограмм", "кг", 1), factor("тонна", "т", 1000), factor("фунт", "фунт", 0.45359237),
    factor("унция", "унц", 0.0283495231), factor("стак (64 шт. по 1 кг)", "стак", 64)}},
  {"Температура", {
    {name = "градус Цельсия", short = "°C", to = function(v) return v end, from = function(b) return b end},
    {name = "градус Фаренгейта", short = "°F", to = function(v) return (v - 32) * 5 / 9 end, from = function(b) return b * 9 / 5 + 32 end},
    {name = "кельвин", short = "K", to = function(v) return v - 273.15 end, from = function(b) return b + 273.15 end},
  }},
  {"Площадь", {factor("мм²", "мм²", 1e-6), factor("см²", "см²", 1e-4), factor("м²", "м²", 1), factor("сотка", "сот", 100),
    factor("гектар", "га", 10000), factor("км²", "км²", 1e6), factor("акр", "акр", 4046.8564224)}},
  {"Объём", {factor("миллилитр", "мл", 0.001), factor("литр", "л", 1), factor("м³", "м³", 1000), factor("галлон (США)", "гал", 3.785411784),
    factor("пинта (США)", "пинта", 0.473176473), factor("ведро (Minecraft)", "ведро", 1)}},
  {"Скорость", {factor("метр в секунду", "м/с", 1), factor("километр в час", "км/ч", 1 / 3.6), factor("миля в час", "миля/ч", 0.44704),
    factor("узел", "уз", 0.514444), factor("блок в секунду", "бл/с", 1)}},
  {"Данные", {factor("бит", "бит", 0.125), factor("байт", "Б", 1), factor("килобайт", "КБ", 1024), factor("мегабайт", "МБ", 1048576),
    factor("гигабайт", "ГБ", 1073741824)}},
  {"Время", {factor("тик Minecraft", "тик", 0.05), factor("секунда", "с", 1), factor("минута", "мин", 60), factor("час", "ч", 3600),
    factor("сутки", "сут", 86400), factor("неделя", "нед", 604800), factor("игровой день", "игр.день", 1200)}},
}

local win = ctx.window(88, 26, "Конвертер")
local c = win.content
local S = {cat = 1, from = 3, to = 4}

local catList, fromList, toList, input, result, formula

local function trim(n)
  if n ~= n or n == math.huge or n == -math.huge then return "—" end
  local s
  if n ~= 0 and (math.abs(n) >= 1e12 or math.abs(n) < 1e-6) then
    s = string.format("%.6g", n)
  else
    s = string.format("%.8f", n):gsub("0+$", ""):gsub("%.$", "")
  end
  return s
end

local function update()
  local units = CATS[S.cat][2]
  local a, b = units[S.from], units[S.to]
  local v = tonumber((input.text:gsub(",", ".")))
  if not v or not a or not b then
    result:setText("—")
    formula:setText("Введите число")
    return
  end
  local out = b.from(a.to(v))
  result:setText(trim(out) .. " " .. b.short)
  formula:setText(trim(v) .. " " .. a.short .. " = " .. trim(out) .. " " .. b.short)
end

local function unitItems()
  local out = {}
  for i, u in ipairs(CATS[S.cat][2]) do out[i] = u.name .. "  (" .. u.short .. ")" end
  return out
end

local function setCategory(i)
  S.cat = i
  local n = #CATS[i][2]
  S.from, S.to = min(S.from, n), min(S.to, n)
  if S.from == S.to then S.to = S.from % n + 1 end
  fromList:setItems(unitItems())
  toList:setItems(unitItems())
  fromList.selected, toList.selected = S.from, S.to
  fromList:ensureVisible()
  toList:ensureVisible()
  update()
end

local names = {}
for i, cat in ipairs(CATS) do names[i] = cat[1] end
catList = c:add(GUI.list(1, 1, 18, c.h, names))
catList.bg = "panel"
catList.selected = 1
catList.onSelect = function(_, idx) setCategory(idx) end

c:add(GUI.label(21, 2, "Значение", "dim"))
input = c:add(GUI.input(21, 3, 30, "1"))
input.onChange = update
result = c:add(GUI.label(21, 5, "", "accent", nil, 60))
formula = c:add(GUI.label(21, 6, "", "dim", nil, 60))
c:add(GUI.label(21, 8, "Из", "dim"))
c:add(GUI.label(55, 8, "В", "dim"))
fromList = c:add(GUI.list(21, 9, 31, 14, {}))
toList = c:add(GUI.list(55, 9, 31, 14, {}))
fromList.onSelect = function(_, idx) S.from = idx update() end
toList.onSelect = function(_, idx) S.to = idx update() end
c:add(GUI.button(c.w - 37, 7, 5, 1, " ⇄ ", function()
  S.from, S.to = S.to, S.from
  fromList.selected, toList.selected = S.from, S.to
  update()
end))
c.focused = input
setCategory(1)
]]},
  {"/System/Store/Currency.app/Info.lua", [[
return {
  title = "Курсы валют", short = "Валюты", order = 24, category = "Финансы", version = "1.0", author = "Команда CubeOS", needsNet = true,
  desc = "Официальные курсы валют Банка России на сегодня и конвертер между любыми валютами. Показывает изменение курса к предыдущему дню. Данные загружаются через Internet Card и сохраняются на диске.",
  icon = {
    pal = {g = 0x10893E, y = 0xFFD84D, w = 0xFFFFFF},
    "gggggggg",
    "gyyyyyyg",
    "gyywwyyg",
    "gyywgyyg",
    "gyywwyyg",
    "gyywgyyg",
    "gyyyyyyg",
    "gggggggg",
  },
}
]]},
  {"/System/Store/Currency.app/Main.lua", [[
-- Курсы валют ЦБ РФ и конвертер
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local HTTP = require("HTTP")
local JSON = require("JSON")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local DIR = "/Users/Currency"
System.mkdirs(DIR)
local URL = "https://www.cbr-xml-daily.ru/daily_json.js"
local FAV = {USD = 1, EUR = 2, CNY = 3, GBP = 4, JPY = 5, KZT = 6, TRY = 7, BYN = 8, UAH = 9, CHF = 10}

local win = ctx.window(94, 28, "Курсы валют")
local c = win.content
local status = c:add(GUI.label(1, c.h, "", "dim", "panel", c.w))
local function setStatus(t) status:setText(" " .. t) end

local rates, dateText = {}, ""
local from, to = nil, nil
local list, amountInput, resultLabel, rateLabel, fromBtn, toBtn

local function findRate(code)
  for _, r in ipairs(rates) do
    if r.code == code then return r end
  end
end

local function build(valute)
  local out = {{code = "RUB", name = "Российский рубль", nominal = 1, value = 1, prev = 1}}
  for code, v in pairs(valute) do
    if type(v) == "table" and tonumber(v.Value) then
      out[#out + 1] = {code = code, name = tostring(v.Name), nominal = tonumber(v.Nominal) or 1, value = tonumber(v.Value), prev = tonumber(v.Previous) or tonumber(v.Value)}
    end
  end
  table.sort(out, function(a, b)
    if a.code == "RUB" then return true elseif b.code == "RUB" then return false end
    local fa, fb = FAV[a.code] or 100, FAV[b.code] or 100
    if fa ~= fb then return fa < fb end
    return a.code < b.code
  end)
  return out
end

local function fmt(n, dec)
  local s = string.format("%." .. (dec or 2) .. "f", n)
  local int, frac = s:match("^(-?%d+)(.*)$")
  int = int:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""):gsub("^%- ", "-")
  return int .. frac
end

local function load()
  setStatus("Загрузка курсов с cbr-xml-daily.ru…")
  Desktop.render()
  local body, err = HTTP.request(URL, nil, HTTP.browserHeaders(), "GET", {maxBytes = 40 * 1024, timeout = 25})
  if body then
    local d = JSON.decode(body)
    if type(d) == "table" and type(d.Valute) == "table" then
      rates = build(d.Valute)
      dateText = tostring(d.Date or ""):sub(1, 10)
      System.writeFile(DIR .. "/cache.lua", System.serialize({rates = rates, date = dateText, at = System.time()}))
      setStatus("Курсы ЦБ РФ на " .. dateText:sub(9, 10) .. "." .. dateText:sub(6, 7) .. "." .. dateText:sub(1, 4) .. ". Обновлено в " .. System.date("%H:%M"))
      return true
    end
    err = "некорректный ответ сервиса"
  end
  local cache = System.loadData(DIR .. "/cache.lua")
  if type(cache) == "table" and type(cache.rates) == "table" then
    rates, dateText = cache.rates, tostring(cache.date or "")
    setStatus("Нет связи (" .. tostring(err) .. ") — показаны сохранённые курсы от " .. System.date("%d.%m %H:%M", cache.at))
  else
    setStatus("Не удалось загрузить курсы: " .. tostring(err))
  end
  return false
end

local function convert()
  if not from or not to then return end
  local amount = tonumber((amountInput.text:gsub(",", "."):gsub("%s", "")))
  if not amount then
    resultLabel:setText("—")
    rateLabel:setText("Введите число")
    return
  end
  local value = amount * (from.value / from.nominal) / (to.value / to.nominal)
  resultLabel:setText(fmt(value, value < 10 and 4 or 2) .. " " .. to.code)
  local one = (from.value / from.nominal) / (to.value / to.nominal)
  rateLabel:setText("1 " .. from.code .. " = " .. fmt(one, one < 10 and 4 or 2) .. " " .. to.code)
end

local function pick(title, current)
  local names = {}
  for i, r in ipairs(rates) do names[i] = r.code .. "  —  " .. r.name end
  local idx = GUI.select(title, names)
  return idx and rates[idx] or current
end

local function refreshButtons()
  fromBtn.text = "Из: " .. (from and from.code or "—")
  toBtn.text = "В: " .. (to and to.code or "—")
  convert()
end

-- ---------- интерфейс
c:add(GUI.label(2, 1, "Курс ЦБ РФ", "text"))
c:add(GUI.button(c.w - 16, 1, 14, 1, "Обновить", function()
  load()
  list:setItems(rates)
  from, to = findRate(from and from.code) or findRate("USD"), findRate(to and to.code) or findRate("RUB")
  refreshButtons()
end, "primary"))

list = c:add(GUI.list(1, 3, 52, c.h - 3, rates))
list.striped = true
list.render = function(_, r, _, x, y, w, sel, bg)
  local fg = sel and C.accentText or C.text
  Screen.text(x + 1, y, sel and C.accentText or C.accent, r.code, bg)
  Screen.text(x + 6, y, fg, GUI.fit((r.nominal > 1 and (r.nominal .. " ") or "") .. r.name, w - 28), bg)
  local value = fmt(r.value, 4)
  Screen.text(x + w - 22 - unicode.len(value) + 10, y, fg, value, bg)
  local diff = r.value - r.prev
  local txt = (diff > 0 and "▲ " or (diff < 0 and "▼ " or "• ")) .. fmt(math.abs(diff), 2)
  local col = sel and C.accentText or (diff > 0 and C.danger or (diff < 0 and C.success or C.dim))
  Screen.text(x + w - unicode.len(txt) - 1, y, col, txt, bg)
end
list.onSelect = function(_, idx)
  local r = rates[idx]
  if r then
    from = r
    if to == from then to = findRate(r.code == "RUB" and "USD" or "RUB") end
    refreshButtons()
  end
end

local rx = 56
c:add(GUI.label(rx, 3, "Конвертер", "accent"))
c:add(GUI.label(rx, 5, "Сумма", "dim"))
amountInput = c:add(GUI.input(rx, 6, 26, "100"))
amountInput.onChange = function() convert() end
fromBtn = c:add(GUI.button(rx, 8, 17, 1, "", function() from = pick("Конвертировать из", from) refreshButtons() end))
c:add(GUI.button(rx + 18, 8, 5, 1, " ⇄ ", function() from, to = to, from refreshButtons() end))
toBtn = c:add(GUI.button(rx + 24, 8, 14, 1, "", function() to = pick("Конвертировать в", to) refreshButtons() end))
c:add(GUI.label(rx, 11, "Результат", "dim"))
resultLabel = c:add(GUI.label(rx, 12, "", "text", nil, 36))
rateLabel = c:add(GUI.label(rx, 14, "", "dim", nil, 36))
c:add(GUI.label(rx, 17, "Выберите валюту в списке слева —", "dim"))
c:add(GUI.label(rx, 18, "она станет исходной для конвертации.", "dim"))
c.focused = amountInput

win.onResize = function()
  list.h = c.h - 3
  status.y, status.w = c.h, c.w
end
win:resize(win.w, win.h)

load()
list:setItems(rates)
from, to = findRate("USD"), findRate("RUB")
list.selected = 2
refreshButtons()
]]},
  {"/System/Store/G2048.app/Info.lua", [[
return {
  title = "2048", short = "2048", order = 31, category = "Игры", version = "1.0", author = "Команда CubeOS",
  desc = "Сдвигайте плитки стрелками или WASD (а также мышью — проведите по полю), складывайте одинаковые числа и дойдите до 2048. Рекорд сохраняется на диске.",
  icon = {
    pal = {t = 0xEDC22E, b = 0xBBADA0, w = 0xFFFFFF},
    "bbbbbbbb",
    "bttttttb",
    "btwwwwtb",
    "btttwttb",
    "btwwtttb",
    "btwwwwtb",
    "bttttttb",
    "bbbbbbbb",
  },
}
]]},
  {"/System/Store/G2048.app/Main.lua", [=[
-- 2048
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local DIR = "/Users/Games"
System.mkdirs(DIR)
local stats = System.loadData(DIR .. "/2048.lua")
if type(stats) ~= "table" then stats = {best = 0} end

local TILE_W, TILE_H = 9, 4
local win = ctx.window(TILE_W * 4 + 7, TILE_H * 4 + 12, "2048")
local c = win.content

local grid, score, over, won
local scoreLabel, bestLabel, msg

-- Цвета подобраны точно под 256-цветную палитру экрана Tier 3 OpenComputers (иначе оттенки «плывут»)
local COLORS = {
  [0] = {0x696969, 0x696969}, [2] = {0xF0F0F0, 0x4B4B4B}, [4] = {0xFFFFBF, 0x4B4B4B}, [8] = {0xFFB680, 0xFFFFFF},
  [16] = {0xFF9280, 0xFFFFFF}, [32] = {0xFF6D40, 0xFFFFFF}, [64] = {0xFF4940, 0xFFFFFF}, [128] = {0xFFDB80, 0x4B4B4B},
  [256] = {0xFFDB40, 0x4B4B4B}, [512] = {0xFFB640, 0x4B4B4B}, [1024] = {0xCCDB40, 0x4B4B4B}, [2048] = {0xFFFF40, 0x4B4B4B},
}

local function spawn()
  local empty = {}
  for y = 1, 4 do
    for x = 1, 4 do
      if grid[y][x] == 0 then empty[#empty + 1] = {x, y} end
    end
  end
  if #empty == 0 then return end
  local p = empty[math.random(1, #empty)]
  grid[p[2]][p[1]] = math.random() < 0.9 and 2 or 4
end

local function newGame()
  grid = {}
  for y = 1, 4 do grid[y] = {0, 0, 0, 0} end
  score, over, won = 0, false, false
  spawn()
  spawn()
end

local function slide(line)
  local compact, out, gained = {}, {}, 0
  for _, v in ipairs(line) do
    if v ~= 0 then compact[#compact + 1] = v end
  end
  local i = 1
  while i <= #compact do
    if compact[i + 1] == compact[i] then
      out[#out + 1] = compact[i] * 2
      gained = gained + compact[i] * 2
      i = i + 2
    else
      out[#out + 1] = compact[i]
      i = i + 1
    end
  end
  while #out < 4 do out[#out + 1] = 0 end
  return out, gained
end

local function canMove()
  for y = 1, 4 do
    for x = 1, 4 do
      local v = grid[y][x]
      if v == 0 then return true end
      if x < 4 and grid[y][x + 1] == v then return true end
      if y < 4 and grid[y + 1][x] == v then return true end
    end
  end
  return false
end

--- dir: "left" | "right" | "up" | "down"
local function move(dir)
  if over then return end
  local moved = false
  for i = 1, 4 do
    local line = {}
    for j = 1, 4 do
      if dir == "left" then line[j] = grid[i][j]
      elseif dir == "right" then line[j] = grid[i][5 - j]
      elseif dir == "up" then line[j] = grid[j][i]
      else line[j] = grid[5 - j][i] end
    end
    local out, gained = slide(line)
    score = score + gained
    for j = 1, 4 do
      local x, y
      if dir == "left" then y, x = i, j
      elseif dir == "right" then y, x = i, 5 - j
      elseif dir == "up" then y, x = j, i
      else y, x = 5 - j, i end
      if grid[y][x] ~= out[j] then moved = true end
      grid[y][x] = out[j]
      if out[j] == 2048 and not won then
        won = true
        Desktop.notify("Вы собрали 2048! Можно играть дальше.", "2048")
      end
    end
  end
  if moved then spawn() end
  if score > stats.best then
    stats.best = score
    System.writeFile(DIR .. "/2048.lua", System.serialize(stats))
  end
  if not canMove() then over = true end
end

local Board = GUI.class()

function Board:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, 0x4B4B4B, nil, " ")
  for y = 1, 4 do
    for x = 1, 4 do
      local v = grid[y][x]
      local col = COLORS[v] or {0x996DBF, 0xFFFFFF}
      local px, py = ax + 1 + (x - 1) * (TILE_W + 1), ay + 1 + (y - 1) * (TILE_H + 1)
      Screen.rect(px, py, TILE_W, TILE_H, col[1], nil, " ")
      if v > 0 then
        local s = tostring(v)
        Screen.text(px + floor((TILE_W - #s) / 2), py + 1, col[2], s, col[1])
      end
    end
  end
  if over then
    Screen.rect(ax, ay + floor(self.h / 2) - 1, self.w, 3, 0x000000, nil, nil, 0.6)
    Screen.text(ax + floor((self.w - 14) / 2), ay + floor(self.h / 2), 0xFFFFFF, "Игра окончена!")
  end
end

function Board:onEvent(e)
  if e.type == "touch" then
    self:capture()
    self.sx, self.sy = e.fx or e.x, e.fy or e.y
    return true
  elseif e.type == "drop" and self.sx then
    local dx, dy = (e.fx or e.x) - self.sx, ((e.fy or e.y) - self.sy) * 2
    self.sx = nil
    if math.abs(dx) < 2 and math.abs(dy) < 2 then return true end
    if math.abs(dx) > math.abs(dy) then move(dx > 0 and "right" or "left") else move(dy > 0 and "down" or "up") end
    return true
  end
  return e.type == "drag"
end

local board = c:add(GUI.new(Board, 3, 4, TILE_W * 4 + 5, TILE_H * 4 + 5))

c:add(GUI.label(3, 1, "2048", "accent"))
scoreLabel = c:add(GUI.label(3, 2, "", "text"))
bestLabel = c:add(GUI.label(22, 2, "", "dim"))
c:add(GUI.button(c.w - 16, 1, 14, 1, "Новая игра", function() newGame() end, "primary"))
c:add(GUI.label(3, c.h - 1, "Стрелки, WASD или мышь", "dim"))

win.tickInterval = 0.2
win.onTick = function()
  scoreLabel:setText("Счёт: " .. score)
  bestLabel:setText("Рекорд: " .. stats.best)
  return true
end

local KEYS = {[200] = "up", [208] = "down", [203] = "left", [205] = "right", [17] = "up", [31] = "down", [30] = "left", [32] = "right"}
win.onKey = function(_, e)
  local dir = KEYS[e.code]
  if dir then move(dir) return true end
  return false
end

newGame()
]=]},
  {"/System/Store/Paint.app/Info.lua", [[
return {
  title = "Paint", short = "Paint", order = 20, category = "Графика", version = "1.0", author = "Команда CubeOS",
  desc = "Рисуйте на холсте: карандаш, ластик, заливка, линия, прямоугольник, эллипс и пипетка. Есть отмена и повтор, 20 цветов и свои цвета, толщина кисти. Рисунки сохраняются в папку «Изображения» (.cpaint) и открываются двойным щелчком в Проводнике. Чтобы рисовать точнее, холст использует половинки ячеек экрана.",
  icon = {
    pal = {r = 0xED4245, y = 0xFAA61A, b = 0x4C8DFF, g = 0x3BA55D, w = 0xFFFFFF},
    ".wwwwww.",
    "wrrwyyww",
    "wrrwyyww",
    "wwwwwwbb",
    "wggwwwbb",
    "wggwwwww",
    ".wwwwww.",
    "........",
  },
}
]]},
  {"/System/Store/Paint.app/Main.lua", [[
-- ----------
--  Paint для CubeOS
--  Холст из «пикселей»: каждый пиксель — половинка ячейки экрана (▀), поэтому по вертикали
--  разрешение вдвое выше. Мышь с точностью до половины ячейки работает в «точном режиме» экрана
--  (Tier 3); на обычном экране рисование идёт по верхним половинкам.
-- ----------
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min, abs, ceil = math.floor, math.max, math.min, math.abs, math.ceil

local PICS = "/Users/Pictures"
System.mkdirs(PICS)

-- Цвета подобраны под 256-цветную палитру экрана Tier 3, поэтому на экране выглядят так же, как в файле
local COLORS = {
  0x000000, 0x787878, 0x990000, 0xFF2400, 0xFF9200, 0xFFFF00, 0x33B640, 0x00B6FF, 0x3349BF, 0x9949BF, 0x3C3C3C, 0x664900,
  0xFFFFFF, 0xC3C3C3, 0xCC6D40, 0xFFB6BF, 0xFFDB00, 0xFFFFBF, 0x99DB40, 0x99DBFF,
  0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, -- 21..24: свои цвета
}
local WHITE = 13
local nextCustom = 21

local W0, H0 = Desktop.screenSize()
local win = ctx.window(min(104, W0), min(36, H0 - Desktop.taskbarHeight()), "Paint")
win.resizable, win.minW, win.minH = true, min(70, W0), 16
local c = win.content

-- ---------- изображение
local img = {w = 64, h = 40, px = {}}
local path, modified = nil, false
local undo, redo = {}, {}
local ov, setpx = {}, nil -- предпросмотр фигуры: ov[y * 256 + x] = цвет
local tool, size, filled = "pencil", 1, false
local color1, color2 = 1, WHITE

local function newImage(w, h)
  img.w, img.h, img.px = w, h, {}
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = WHITE end
    img.px[y] = row
  end
  undo, redo, ov = {}, {}, {}
  System.collect()
end

local function snapshot()
  local parts = {}
  for y = 1, img.h do parts[y] = string.char(table.unpack(img.px[y])) end
  return {w = img.w, h = img.h, data = table.concat(parts)}
end

local function restore(s)
  img.w, img.h, img.px = s.w, s.h, {}
  for y = 1, s.h do
    local row, base = {}, (y - 1) * s.w
    for x = 1, s.w do row[x] = s.data:byte(base + x) end
    img.px[y] = row
  end
end

local function pushUndo()
  undo[#undo + 1] = snapshot()
  if #undo > 12 then table.remove(undo, 1) end
  redo = {}
  modified = true
end

local function doUndo()
  if #undo == 0 then return end
  redo[#redo + 1] = snapshot()
  restore(table.remove(undo))
end

local function doRedo()
  if #redo == 0 then return end
  undo[#undo + 1] = snapshot()
  restore(table.remove(redo))
end

-- ---------- рисование
local function gridSet(x, y, ci)
  if x >= 1 and y >= 1 and x <= img.w and y <= img.h then img.px[y][x] = ci end
end
local function ovSet(x, y, ci)
  if x >= 1 and y >= 1 and x <= img.w and y <= img.h then ov[y * 256 + x] = ci end
end
setpx = gridSet

local curSize = 1
local function brush(x, y, ci)
  local r1 = (curSize - 1) // 2
  local r2 = curSize - 1 - r1
  for yy = y - r1, y + r2 do
    for xx = x - r1, x + r2 do setpx(xx, yy, ci) end
  end
end

local function line(x0, y0, x1, y1, ci)
  local dx, dy = abs(x1 - x0), abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx - dy
  while true do
    brush(x0, y0, ci)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 > -dy then err = err - dy x0 = x0 + sx end
    if e2 < dx then err = err + dx y0 = y0 + sy end
  end
end

local function rectShape(x0, y0, x1, y1, ci, fillCi)
  if x0 > x1 then x0, x1 = x1, x0 end
  if y0 > y1 then y0, y1 = y1, y0 end
  if fillCi then
    for y = y0, y1 do
      for x = x0, x1 do setpx(x, y, fillCi) end
    end
  end
  line(x0, y0, x1, y0, ci)
  line(x1, y0, x1, y1, ci)
  line(x1, y1, x0, y1, ci)
  line(x0, y1, x0, y0, ci)
end

local function ellipseShape(x0, y0, x1, y1, ci, fillCi)
  if x0 > x1 then x0, x1 = x1, x0 end
  if y0 > y1 then y0, y1 = y1, y0 end
  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
  local rx, ry = (x1 - x0) / 2, (y1 - y0) / 2
  if ry < 0.5 or rx < 0.5 then
    line(x0, y0, x1, y1, ci)
    return
  end
  if fillCi then
    for y = y0, y1 do
      local t = (y - cy) / ry
      local half = rx * math.sqrt(max(0, 1 - t * t))
      for x = floor(cx - half + 0.5), floor(cx + half + 0.5) do setpx(x, y, fillCi) end
    end
  end
  local steps = max(24, floor((rx + ry) * 6))
  for i = 0, steps - 1 do
    local a = i / steps * 2 * math.pi
    brush(floor(cx + rx * math.cos(a) + 0.5), floor(cy + ry * math.sin(a) + 0.5), ci)
  end
end

local function floodFill(x, y, ci)
  if x < 1 or y < 1 or x > img.w or y > img.h then return end
  local px, target = img.px, img.px[y][x]
  if target == ci then return end
  local stack = {x, y}
  while #stack > 0 do
    local cy = table.remove(stack)
    local cx = table.remove(stack)
    if px[cy][cx] == target then
      local l, r = cx, cx
      while l > 1 and px[cy][l - 1] == target do l = l - 1 end
      while r < img.w and px[cy][r + 1] == target do r = r + 1 end
      for i = l, r do px[cy][i] = ci end
      for _, ny in ipairs({cy - 1, cy + 1}) do
        if ny >= 1 and ny <= img.h then
          local i = l
          while i <= r do
            if px[ny][i] == target then
              stack[#stack + 1] = i
              stack[#stack + 1] = ny
              while i <= r and px[ny][i] == target do i = i + 1 end
            else
              i = i + 1
            end
          end
        end
      end
    end
  end
end

-- ---------- файлы
local function updateTitle()
  win.title = (path and System.basename(path) or "Без имени") .. (modified and " •" or "") .. " — Paint"
end

local function serialize()
  local cust = {}
  for i = 21, 24 do cust[#cust + 1] = string.format("%06X", COLORS[i]) end
  local lines = {"CPAINT1 " .. img.w .. " " .. img.h, table.concat(cust, " ")}
  for y = 1, img.h do
    local chars = {}
    for x = 1, img.w do chars[x] = string.char(48 + img.px[y][x]) end
    lines[#lines + 1] = table.concat(chars)
  end
  return table.concat(lines, "\n") .. "\n"
end

local function loadFile(p)
  local data = System.readFile(p)
  if not data then GUI.alert("Paint", "Не удалось открыть файл:\n" .. tostring(p)) return end
  local lines = {}
  for line in data:gmatch("([^\n]*)\n?") do lines[#lines + 1] = line end
  local w, h = lines[1]:match("^CPAINT1 (%d+) (%d+)")
  w, h = tonumber(w), tonumber(h)
  if not w or w < 1 or h < 1 or w > 200 or h > 140 then GUI.alert("Paint", "Это не рисунок Paint (.cpaint).") return end
  local i = 21
  for hex in (lines[2] or ""):gmatch("%x%x%x%x%x%x") do
    if i <= 24 then COLORS[i] = tonumber(hex, 16) i = i + 1 end
  end
  newImage(w, h)
  for y = 1, h do
    local row = lines[y + 2] or ""
    for x = 1, w do
      local ci = (row:byte(x) or (48 + WHITE)) - 48
      img.px[y][x] = (ci >= 1 and ci <= 24) and ci or WHITE
    end
  end
  path, modified = p, false
  updateTitle()
end

local function saveTo(p)
  local ok, err = System.writeFile(p, serialize())
  if not ok then GUI.alert("Не удалось сохранить", tostring(err)) return false end
  path, modified = p, false
  updateTitle()
  Desktop.notify("Сохранено: " .. System.basename(p), "Paint")
  return true
end

local function saveAs()
  local default = path and System.basename(path) or "Рисунок.cpaint"
  local name = GUI.prompt("Сохранить как", "Имя файла (сохранится в «Изображения»):", default)
  if not name or name == "" then return false end
  name = name:gsub("[/\\]", "_")
  if not name:match("%.cpaint$") then name = name .. ".cpaint" end
  return saveTo(PICS .. "/" .. name)
end

local function save()
  if path then return saveTo(path) end
  return saveAs()
end

local function confirmDiscard()
  if not modified then return true end
  return GUI.confirm("Paint", "Рисунок не сохранён. Продолжить без сохранения?", "Продолжить", "Отмена", true)
end

local canvas, status

local function fitCanvas()
  local avail = max(8, canvas.w - 2)
  if img.w > avail then
    Desktop.notify("Холст шире окна — часть не видна. Увеличьте окно.", "Paint")
  end
end

local function newDialog()
  if not confirmDiscard() then return end
  local def = floor(min(80, canvas.w - 3)) .. "x" .. floor(min(56, (canvas.h - 1) * 2))
  local text = GUI.prompt("Новый рисунок", "Размер холста в пикселях: ширина x высота (до 96x64).", def)
  if not text then return end
  local w, h = text:match("^%s*(%d+)%s*[xXхХ×*]%s*(%d+)%s*$")
  w, h = tonumber(w), tonumber(h)
  if not w or w < 4 or h < 4 or w > 96 or h > 64 then
    GUI.alert("Paint", "Введите размер вида 80x50 (от 4x4 до 96x64).")
    return
  end
  newImage(w, h)
  path, modified = nil, false
  updateTitle()
  fitCanvas()
end

local function openDialog()
  if not confirmDiscard() then return end
  local names = {}
  for _, n in ipairs(System.list(PICS)) do
    if n:match("%.cpaint$") then names[#names + 1] = n end
  end
  if #names == 0 then
    GUI.alert("Открыть", "В папке «Изображения» пока нет рисунков.")
    return
  end
  local idx = GUI.select("Открыть рисунок", names)
  if idx then loadFile(PICS .. "/" .. names[idx]) end
end

-- ---------- холст
local Canvas = GUI.class()
local stroke

function Canvas:drawSelf(ax, ay)
  local work = Screen.blend(C.text, C.panel, 0.22)
  Screen.rect(ax, ay, self.w, self.h, work, nil, " ")
  Screen.pushClip(ax, ay, self.w, self.h)
  local hasOv = next(ov) ~= nil
  local px = img.px
  local function at(x, y)
    if hasOv then
      local o = ov[y * 256 + x]
      if o then return o end
    end
    return px[y][x]
  end
  local rows = ceil(img.h / 2)
  for r = 1, rows do
    local y, jt, jb = ay + r - 1, 2 * r - 1, 2 * r
    local x = 1
    while x <= img.w do
      local top = at(x, jt)
      local bot = jb <= img.h and at(x, jb) or nil
      local x2 = x
      while x2 < img.w and at(x2 + 1, jt) == top and (bot == nil or at(x2 + 1, jb) == bot) do x2 = x2 + 1 end
      Screen.rect(ax + x, y, x2 - x + 1, 1, bot and COLORS[bot] or work, COLORS[top], "▀")
      x = x2 + 1
    end
  end
  Screen.popClip()
end

local function applyShape(kind, x0, y0, x1, y1, ci)
  local fillCi = filled and (stroke and stroke.other or color2) or nil
  if kind == "line" then line(x0, y0, x1, y1, ci)
  elseif kind == "rect" then rectShape(x0, y0, x1, y1, ci, fillCi)
  elseif kind == "ellipse" then ellipseShape(x0, y0, x1, y1, ci, fillCi) end
end

local function hex(ci) return string.format("#%06X", COLORS[ci]) end

function Canvas:onEvent(e, ax, ay)
  local t = e.type
  if t ~= "touch" and t ~= "drag" and t ~= "drop" then return false end
  local fx, fy = e.fx or e.x, e.fy or e.y
  local x = floor(fx) - ax
  local y = floor((fy - ay) * 2) + 1
  x, y = max(1, min(img.w, x)), max(1, min(img.h, y))
  if t == "touch" then
    self:capture()
    local primary = e.button == 1
    local ci, other = primary and color2 or color1, primary and color1 or color2
    stroke = {x = x, y = y, sx = x, sy = y, ci = ci, other = other}
    if tool == "picker" then
      local got = img.px[y][x]
      if primary then color2 = got else color1 = got end
      stroke = nil
    elseif tool == "fill" then
      pushUndo()
      floodFill(x, y, ci)
    elseif tool == "pencil" or tool == "eraser" then
      pushUndo()
      curSize = tool == "eraser" and size + 2 or size
      setpx = gridSet
      brush(x, y, tool == "eraser" and color2 or ci)
    end
  elseif stroke then
    if t == "drag" then
      -- В старых версиях OC событие drop бывает только после drag. Поэтому
      -- включаем точный режим здесь, а не при touch: одиночный щелчок не
      -- сможет оставить систему в режиме дробных координат.
      Desktop.setPrecise(true)
      if tool == "pencil" or tool == "eraser" then
        curSize = tool == "eraser" and size + 2 or size
        setpx = gridSet
        line(stroke.x, stroke.y, x, y, tool == "eraser" and color2 or stroke.ci)
        stroke.x, stroke.y = x, y
      elseif tool == "line" or tool == "rect" or tool == "ellipse" then
        ov, curSize, setpx = {}, size, ovSet
        applyShape(tool, stroke.sx, stroke.sy, x, y, stroke.ci)
        setpx = gridSet
      end
    else -- drop
      if tool == "line" or tool == "rect" or tool == "ellipse" then
        pushUndo()
        ov, curSize, setpx = {}, size, gridSet
        applyShape(tool, stroke.sx, stroke.sy, x, y, stroke.ci)
      end
      stroke = nil
      Desktop.setPrecise(false)
    end
  end
  status:setText(string.format(" %d, %d px   ·   %d × %d px   ·   цвет %s", x, y, img.w, img.h, hex(color1)))
  return true
end

-- ---------- палитра
local Palette = GUI.class()

function Palette:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, C.panel, nil, " ")
  Screen.rect(ax + 4, ay, 4, 2, COLORS[color2], nil, " ")
  Screen.rect(ax + 1, ay, 4, 2, COLORS[color1], nil, " ")
  Screen.text(ax + 1, ay, COLORS[color1] > 0x808080 and 0x000000 or 0xFFFFFF, "осн", COLORS[color1])
  for i = 1, 24 do
    local col, row = (i - 1) % 12, floor((i - 1) / 12)
    local x, y = ax + 10 + col * 4, ay + row
    Screen.rect(x, y, 4, 1, COLORS[i], nil, " ")
    local dark = COLORS[i] < 0x808080
    if i == color1 then Screen.text(x + 1, y, dark and 0xFFFFFF or 0x000000, "●●", COLORS[i])
    elseif i == color2 then Screen.text(x + 1, y, dark and 0xFFFFFF or 0x000000, "○○", COLORS[i]) end
  end
end

function Palette:onEvent(e, ax, ay)
  if e.type ~= "touch" then return false end
  local col, row = floor((e.x - ax - 10) / 4), e.y - ay
  if col >= 0 and col < 12 and row >= 0 and row < 2 then
    local i = row * 12 + col + 1
    if e.button == 1 then color2 = i else color1 = i end
  end
  return true
end

local function customColor()
  local text = GUI.prompt("Свой цвет", "Цвет в формате RRGGBB, например FF8800:", "FF8800")
  if not text then return end
  local v = text:match("^#?(%x%x%x%x%x%x)$")
  if not v then GUI.alert("Paint", "Нужно шесть шестнадцатеричных цифр: RRGGBB.") return end
  COLORS[nextCustom] = tonumber(v, 16)
  color1 = nextCustom
  nextCustom = nextCustom == 24 and 21 or nextCustom + 1
end

-- ---------- интерфейс
local toolbar = c:add(GUI.panel(1, 2, 14, 10, "panel"))
canvas = c:add(GUI.new(Canvas, 15, 2, c.w - 14, c.h - 4))
local palette = c:add(GUI.new(Palette, 1, c.h - 2, c.w, 2))
local colorBtn = c:add(GUI.button(c.w - 11, c.h - 2, 10, 1, "Цвет…", customColor))
status = c:add(GUI.label(1, c.h, "", "dim", "panel", c.w))
canvas.focusable = true
c.focused = canvas

local TOOLS = {
  {"pencil", "Карандаш"}, {"eraser", "Ластик"}, {"fill", "Заливка"}, {"line", "Линия"},
  {"rect", "Рамка"}, {"ellipse", "Эллипс"}, {"picker", "Пипетка"},
}

local function buildToolbar()
  toolbar:clear()
  toolbar.h = c.h - 4
  for i, t in ipairs(TOOLS) do
    local b = GUI.button(2, i, 12, 1, t[2], function() tool = t[1] buildToolbar() end)
    b.active = tool == t[1]
    toolbar:add(b)
  end
  toolbar:add(GUI.label(2, 9, "Толщина", "dim"))
  for i, s in ipairs({1, 2, 3, 5}) do
    local b = GUI.button(2 + (i - 1) * 3, 10, 3, 1, tostring(s), function() size = s buildToolbar() end)
    b.active = size == s
    toolbar:add(b)
  end
  toolbar:add(GUI.label(2, 12, "Фигуры:", "dim"))
  toolbar:add(GUI.button(2, 13, 12, 1, filled and "с заливкой" or "контур", function() filled = not filled buildToolbar() end))
  toolbar:add(GUI.button(2, 15, 12, 1, "Отменить", function() doUndo() end))
  toolbar:add(GUI.button(2, 16, 12, 1, "Повторить", function() doRedo() end))
end

local function layout()
  toolbar.h = c.h - 4
  canvas.x, canvas.y, canvas.w, canvas.h = 15, 2, c.w - 14, c.h - 4
  palette.y, palette.w = c.h - 2, c.w
  colorBtn.x, colorBtn.y = c.w - 11, c.h - 2
  status.y, status.w = c.h, c.w
  buildToolbar()
end

win.onResize = function() layout() end

win.menu = {
  {title = "Файл", items = function()
    return {
      {text = "Создать…", hint = "Ctrl+N", action = newDialog},
      {text = "Открыть…", hint = "Ctrl+O", action = openDialog},
      {text = "Сохранить", hint = "Ctrl+S", action = save},
      {text = "Сохранить как…", action = saveAs},
      {separator = true},
      {text = "Выход", action = function() win:close() end},
    }
  end},
  {title = "Правка", items = function()
    return {
      {text = "Отменить", hint = "Ctrl+Z", disabled = #undo == 0, action = doUndo},
      {text = "Повторить", hint = "Ctrl+Y", disabled = #redo == 0, action = doRedo},
      {separator = true},
      {text = "Очистить холст", action = function()
        pushUndo()
        for y = 1, img.h do
          for x = 1, img.w do img.px[y][x] = WHITE end
        end
      end},
    }
  end},
}

win.onKey = function(_, e)
  if not e.ctrl then return false end
  local code = e.code
  if code == 44 then doUndo()
  elseif code == 21 then doRedo()
  elseif code == 31 then save()
  elseif code == 24 then openDialog()
  elseif code == 49 then newDialog()
  else return false end
  return true
end

win.onClose = function()
  if modified then
    if not GUI.confirm("Закрыть Paint", "Рисунок не сохранён. Закрыть без сохранения?", "Закрыть", "Отмена", true) then return false end
  end
  Desktop.setPrecise(false)
end

newImage(max(8, min(80, canvas.w - 3)), max(8, min(56, (canvas.h - 1) * 2)))
layout()
if ctx.args.file then loadFile(ctx.args.file) else updateTitle() end
]]},
  {"/System/Store/Saper.app/Info.lua", [[
return {
  title = "Сапёр", short = "Сапёр", order = 30, category = "Игры", version = "1.0", author = "Команда CubeOS",
  desc = "Классический Сапёр. Левая кнопка мыши открывает клетку, правая ставит флажок, щелчок по открытой цифре открывает соседей. Три уровня сложности, первый ход всегда безопасен.",
  icon = {
    pal = {k = 0x222222, g = 0xBDBDBD, r = 0xED1C24},
    "gggggggg",
    "gg.kk.gg",
    "g.kkkk.g",
    "gkkrkkkg",
    "gkkkkkkg",
    "g.kkkk.g",
    "gg.kk.gg",
    "gggggggg",
  },
}
]]},
  {"/System/Store/Saper.app/Main.lua", [=[
-- Сапёр: открывайте клетки, отмечайте ловушки флажками
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local computer, unicode = computer, unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local LEVELS = {{9, 9, 10, "Новичок"}, {16, 16, 40, "Любитель"}, {30, 16, 99, "Эксперт"}}
local NUM = {0x0000FF, 0x008000, 0xFF0000, 0x000080, 0x800000, 0x008080, 0x000000, 0x808080}

local level = 1
local cols, rows, traps
local board, state, opened, flags, startTime, elapsed

local win = ctx.window(40, 22, "Сапёр")
local c = win.content
local board_w, face, minesLabel, timeLabel

local function neighbors(x, y)
  local out = {}
  for dy = -1, 1 do
    for dx = -1, 1 do
      if (dx ~= 0 or dy ~= 0) and x + dx >= 1 and x + dx <= cols and y + dy >= 1 and y + dy <= rows then
        out[#out + 1] = {x + dx, y + dy}
      end
    end
  end
  return out
end

local function reset()
  cols, rows, traps = LEVELS[level][1], LEVELS[level][2], LEVELS[level][3]
  board = {}
  for y = 1, rows do
    board[y] = {}
    for x = 1, cols do board[y][x] = {trap = false, open = false, flag = false, n = 0} end
  end
  state, opened, flags, startTime, elapsed = "ready", 0, 0, nil, 0
  local w, h = max(cols * 2 + 4, 36), rows + 6
  win:resize(w, h + 1)
  board_w.w, board_w.h = cols * 2, rows
  board_w.x = floor((c.w - cols * 2) / 2) + 1
  win.title = "Сапёр — " .. LEVELS[level][4]
  Desktop.dirty = true
end

local function plant(sx, sy)
  local safe = {[sy * 100 + sx] = true}
  for _, n in ipairs(neighbors(sx, sy)) do safe[n[2] * 100 + n[1]] = true end
  local placed = 0
  while placed < traps do
    local x, y = math.random(1, cols), math.random(1, rows)
    if not board[y][x].trap and not safe[y * 100 + x] then
      board[y][x].trap = true
      placed = placed + 1
    end
  end
  for y = 1, rows do
    for x = 1, cols do
      local n = 0
      for _, nb in ipairs(neighbors(x, y)) do
        if board[nb[2]][nb[1]].trap then n = n + 1 end
      end
      board[y][x].n = n
    end
  end
end

local function finishGame()
  state = "lost"
  elapsed = startTime and (computer.uptime() - startTime) or 0
  for y = 1, rows do
    for x = 1, cols do
      if board[y][x].trap then board[y][x].open = true end
    end
  end
end

local function reveal(x, y)
  local stack = {{x, y}}
  while #stack > 0 do
    local p = table.remove(stack)
    local cell = board[p[2]][p[1]]
    if not cell.open and not cell.flag then
      cell.open = true
      opened = opened + 1
      if cell.trap then finishGame() return end
      if cell.n == 0 then
        for _, nb in ipairs(neighbors(p[1], p[2])) do stack[#stack + 1] = nb end
      end
    end
  end
  if opened == cols * rows - traps then
    state = "won"
    elapsed = computer.uptime() - startTime
    Desktop.notify(string.format("Победа! Время: %.0f с", elapsed), "Сапёр")
  end
end

local function click(x, y)
  if state == "lost" or state == "won" then return end
  if state == "ready" then
    plant(x, y)
    state, startTime = "play", computer.uptime()
  end
  local cell = board[y][x]
  if cell.flag or cell.open then return end
  if cell.trap then cell.open = true finishGame() return end
  reveal(x, y)
end

local function chord(x, y)
  local cell = board[y][x]
  if not cell.open or cell.n == 0 then return end
  local f = 0
  for _, nb in ipairs(neighbors(x, y)) do
    if board[nb[2]][nb[1]].flag then f = f + 1 end
  end
  if f ~= cell.n then return end
  for _, nb in ipairs(neighbors(x, y)) do
    local o = board[nb[2]][nb[1]]
    if not o.open and not o.flag then
      if o.trap then o.open = true finishGame() return end
      reveal(nb[1], nb[2])
      if state ~= "play" then return end
    end
  end
end

local function flag(x, y)
  if state ~= "play" and state ~= "ready" then return end
  local cell = board[y][x]
  if cell.open then return end
  cell.flag = not cell.flag
  flags = flags + (cell.flag and 1 or -1)
end

-- ---------- поле
local Board = GUI.class()

function Board:drawSelf(ax, ay)
  for y = 1, rows do
    for x = 1, cols do
      local cell = board[y][x]
      local px, py = ax + (x - 1) * 2, ay + y - 1
      local odd = (x + y) % 2 == 0
      if cell.open then
        if cell.trap then
          Screen.rect(px, py, 2, 1, 0xFF2400, nil, " ")
          Screen.text(px, py, 0x000000, "✱", 0xFF2400)
        else
          local bg = odd and 0xF0F0F0 or 0xD2D2D2
          Screen.rect(px, py, 2, 1, bg, nil, " ")
          if cell.n > 0 then Screen.text(px, py, NUM[cell.n], tostring(cell.n), bg) end
        end
      else
        local bg = odd and 0xB4B4B4 or 0xA5A5A5
        Screen.rect(px, py, 2, 1, bg, nil, " ")
        Screen.set(px, py, nil, 0xFFFFFF, "▏")
        Screen.set(px + 1, py, nil, 0x5A5A5A, "▕")
        if cell.flag then Screen.text(px, py, 0xFF2400, "▶", bg) end
      end
    end
  end
end

function Board:onEvent(e, ax, ay)
  if e.type ~= "touch" then return false end
  local x, y = floor((e.x - ax) / 2) + 1, e.y - ay + 1
  if x < 1 or x > cols or y < 1 or y > rows then return true end
  if e.button == 1 then flag(x, y)
  elseif board[y][x].open then chord(x, y)
  else click(x, y) end
  return true
end

board_w = c:add(GUI.new(Board, 3, 4, 18, 9))

local function faceChar()
  if state == "lost" then return " ☹ " elseif state == "won" then return " ☻ " end
  return " ☺ "
end

face = c:add(GUI.button(1, 2, 5, 1, " ☺ ", function() reset() end, "primary"))
minesLabel = c:add(GUI.label(2, 2, "", "text"))
timeLabel = c:add(GUI.label(2, 2, "", "text"))
c:add(GUI.button(2, 1, 14, 1, "Уровень", function()
  local names = {}
  for i, l in ipairs(LEVELS) do names[i] = l[4] .. "  (" .. l[1] .. "×" .. l[2] .. ", мин: " .. l[3] .. ")" end
  local idx = GUI.select("Уровень сложности", names)
  if idx then level = idx reset() end
end))

local function relayout()
  face.x = floor((c.w - 5) / 2) + 1
  minesLabel.x = 3
  timeLabel.x = c.w - 8
  board_w.x = floor((c.w - cols * 2) / 2) + 1
end

win.tickInterval = 0.3
win.onTick = function()
  local t = elapsed
  if state == "play" then t = computer.uptime() - startTime end
  minesLabel:setText(string.format("Ловушек: %03d", traps - flags))
  timeLabel:setText(string.format("%03d с", floor(t)))
  face.text = faceChar()
  relayout()
  return true
end

reset()
relayout()
]=]},
  {"/System/Store/Snake.app/Info.lua", [[
return {
  title = "Змейка", short = "Змейка", order = 32, category = "Игры", version = "1.0", author = "Команда CubeOS",
  desc = "Классическая «Змейка»: стрелки или WASD — движение, P — пауза, пробел — заново. Собирайте красные яблоки, не врезайтесь в стены и в себя. Рекорд показывается в окне.",
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
  {"/System/Store/Snake.app/Main.lua", [[
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
  {"/System/Store/Todo.app/Info.lua", [[
return {
  title = "Задачи", short = "Задачи", order = 25, category = "Продуктивность", version = "1.0", author = "Команда CubeOS",
  desc = "Простой список дел: добавляйте задачи, отмечайте выполненные двойным щелчком или пробелом, удаляйте и очищайте список. Всё сохраняется на диске автоматически.",
  icon = {
    pal = {b = 0x0078D7, w = 0xFFFFFF, g = 0x10893E},
    "bbbbbbbb",
    "bwwwwwwb",
    "bwgwwwwb",
    "bwwgwgwb",
    "bwwwgwwb",
    "bwwwwwwb",
    "bwwwwwwb",
    "bbbbbbbb",
  },
}
]]},
  {"/System/Store/Todo.app/Main.lua", [[
-- Задачи
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop

local DIR = "/Users/Todo"
System.mkdirs(DIR)
local tasks = System.loadData(DIR .. "/tasks.lua")
if type(tasks) ~= "table" then tasks = {} end
local function save() System.writeFile(DIR .. "/tasks.lua", System.serialize(tasks)) end

local win = ctx.window(60, 26, "Задачи")
local c = win.content
local list, counter, input

local function left()
  local n = 0
  for _, t in ipairs(tasks) do
    if not t.done then n = n + 1 end
  end
  return n
end

local function refresh()
  list:setItems(tasks)
  counter:setText("Осталось: " .. left() .. " из " .. #tasks)
end

local function toggle()
  local t = tasks[list.selected]
  if t then
    t.done = not t.done
    save()
    refresh()
  end
end

local function add()
  local text = input.text:match("^%s*(.-)%s*$")
  if text == "" then return end
  tasks[#tasks + 1] = {text = text, done = false}
  input:setText("")
  save()
  refresh()
  list.selected = #tasks
  list:ensureVisible()
end

c:add(GUI.label(3, 1, "Список дел", "accent"))
counter = c:add(GUI.label(c.w - 24, 1, "", "dim", nil, 22, "right"))
list = c:add(GUI.list(2, 3, c.w - 2, c.h - 8, tasks))
list.rowHeight = 1
list.striped = true
list.selected = math.min(1, #tasks)
list.render = function(_, t, _, x, y, w, sel, bg)
  local mark = t.done and "[×] " or "[ ] "
  local fg = sel and C.accentText or (t.done and C.dim or C.text)
  Screen.text(x + 1, y, sel and C.accentText or (t.done and C.success or C.accent), mark, bg)
  Screen.text(x + 5, y, fg, GUI.fit(t.text, w - 7), bg)
end
list.onActivate = function() toggle() end

input = c:add(GUI.input(3, c.h - 4, c.w - 18, "", "Новая задача — Enter"))
input.onSubmit = add
c:add(GUI.button(c.w - 13, c.h - 4, 11, 1, "Добавить", add, "primary"))
c:add(GUI.button(3, c.h - 2, 14, 1, "Готово", toggle))
c:add(GUI.button(19, c.h - 2, 12, 1, "Удалить", function()
  if tasks[list.selected] then
    table.remove(tasks, list.selected)
    save()
    refresh()
  end
end, "danger"))
c:add(GUI.button(33, c.h - 2, 24, 1, "Убрать выполненные", function()
  for i = #tasks, 1, -1 do
    if tasks[i].done then table.remove(tasks, i) end
  end
  save()
  refresh()
end))

win.onKey = function(_, e)
  if e.code == 57 and list:isFocused() then toggle() return true end
  return false
end
c.focused = input
refresh()
]]},
  {"/System/Store/Weather.app/Info.lua", [[
return {
  title = "Погода", short = "Погода", order = 23, category = "Утилиты", version = "1.0", author = "Команда CubeOS", needsNet = true,
  desc = "Текущая погода и прогноз на 7 дней для любого города мира. Данные берутся с открытого сервиса Open-Meteo через Internet Card. Последний прогноз сохраняется на диске и виден без сети.",
  icon = {
    pal = {y = 0xFFC83D, l = 0xE6E9EE, b = 0x2F9BFF},
    "...y....",
    "y..yy..y",
    ".yyyyyy.",
    "..lllll.",
    ".lllllll",
    "llllllll",
    ".llllll.",
    "..b.b.b.",
  },
}
]]},
  {"/System/Store/Weather.app/Main.lua", [[
-- Погода (Open-Meteo)
local ctx = ...
local GUI = require("GUI")
local System = require("System")
local Screen = require("Screen")
local HTTP = require("HTTP")
local JSON = require("JSON")
local unicode = unicode
local C = GUI.color
local Desktop = ctx.Desktop
local floor, max, min = math.floor, math.max, math.min

local DIR = "/Users/Weather"
System.mkdirs(DIR)
local city = System.loadData(DIR .. "/city.lua")
if type(city) ~= "table" or not city.lat then city = {name = "Москва", lat = 55.7558, lon = 37.6173} end
local data
local cache = System.loadData(DIR .. "/cache.lua")
if type(cache) == "table" and type(cache.data) == "table" and cache.city and cache.city.name == city.name then data = cache.data end

local ICONS = {
  sun = {pal = {y = 0xFFC83D}, "...yy...", "y..yy..y", ".yyyyyy.", "yyyyyyyy", "yyyyyyyy", ".yyyyyy.", "y..yy..y", "...yy..."},
  cloud = {pal = {l = 0xCBD2DC}, "........", "...ll...", "..llll..", ".lllllll", "llllllll", "llllllll", ".llllll.", "........"},
  rain = {pal = {l = 0xB5BECB, b = 0x2F9BFF}, "........", "..llll..", ".llllll.", "llllllll", "llllllll", ".b.b.b..", "..b.b.b.", ".b.b.b.."},
  snow = {pal = {l = 0xB5BECB, w = 0xFFFFFF}, "........", "..llll..", ".llllll.", "llllllll", "llllllll", ".w.w.w..", "..w.w.w.", ".w.w.w.."},
  storm = {pal = {l = 0x8C96A6, y = 0xFFC83D}, "..llll..", ".llllll.", "llllllll", "llllllll", "...yy...", "..yy....", "...yy...", "..y....."},
  fog = {pal = {l = 0xB5BECB}, "........", "llllllll", "........", ".lllllll", "........", "llllllll", "........", ".lllllll"},
}

--- Код погоды WMO → название, значок
local function condition(code)
  code = tonumber(code) or 0
  if code == 0 then return "Ясно", "sun"
  elseif code == 1 then return "Преимущественно ясно", "sun"
  elseif code == 2 then return "Переменная облачность", "cloud"
  elseif code == 3 then return "Пасмурно", "cloud"
  elseif code == 45 or code == 48 then return "Туман", "fog"
  elseif code >= 51 and code <= 55 then return "Морось", "rain"
  elseif code == 56 or code == 57 then return "Ледяная морось", "rain"
  elseif code == 61 then return "Небольшой дождь", "rain"
  elseif code == 63 then return "Дождь", "rain"
  elseif code == 65 then return "Сильный дождь", "rain"
  elseif code == 66 or code == 67 then return "Ледяной дождь", "rain"
  elseif code == 71 then return "Небольшой снег", "snow"
  elseif code == 73 then return "Снег", "snow"
  elseif code == 75 then return "Сильный снег", "snow"
  elseif code == 77 then return "Снежная крупа", "snow"
  elseif code >= 80 and code <= 82 then return "Ливень", "rain"
  elseif code == 85 or code == 86 then return "Снегопад", "snow"
  elseif code == 95 then return "Гроза", "storm"
  elseif code == 96 or code == 99 then return "Гроза с градом", "storm"
  end
  return "Неизвестно", "cloud"
end

local DAYS = {"Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"}
local win = ctx.window(84, 28, "Погода")
local c = win.content
local status = c:add(GUI.label(1, c.h, "", "dim", "panel", c.w))
local function setStatus(t) status:setText(" " .. t) end

local function round(v) return floor((tonumber(v) or 0) + 0.5) end
local function signed(v)
  local r = round(v)
  return (r > 0 and "+" or "") .. r
end

local function fetch()
  setStatus("Загрузка прогноза для «" .. city.name .. "»…")
  Desktop.render()
  local url = string.format(
    "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m,relative_humidity_2m,apparent_temperature,wind_speed_10m,weather_code,pressure_msl&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=auto&forecast_days=7&wind_speed_unit=ms",
    city.lat, city.lon)
  local body, err = HTTP.request(url, nil, HTTP.browserHeaders(), "GET", {maxBytes = 40 * 1024, timeout = 25})
  if not body then
    setStatus("Нет связи: " .. tostring(err) .. (data and " — показан сохранённый прогноз" or ""))
    return false
  end
  local d = JSON.decode(body)
  if type(d) ~= "table" or type(d.current) ~= "table" or type(d.daily) ~= "table" then
    setStatus("Сервис вернул непонятный ответ")
    return false
  end
  data = {at = System.time(), current = d.current, daily = d.daily}
  System.writeFile(DIR .. "/cache.lua", System.serialize({city = city, data = data}))
  setStatus("Обновлено в " .. System.date("%H:%M", data.at))
  return true
end

-- ---------- окно с прогнозом
local Report = GUI.class()

function Report:drawSelf(ax, ay)
  Screen.rect(ax, ay, self.w, self.h, C.win, nil, " ")
  Screen.text(ax + 3, ay + 1, C.accent, city.name, C.win)
  if not data then
    Screen.text(ax + 3, ay + 3, C.dim, "Нет данных. Нажмите «Обновить» (нужна Internet Card).", C.win)
    return
  end
  local cur = data.current
  local name, icon = condition(cur.weather_code)
  local dom = GUI.iconColor(ICONS[icon])
  Screen.rect(ax + 3, ay + 3, 14, 7, Screen.blend(0x000000, dom, 0.45), nil, " ")
  GUI.drawIconBig(ax + 4, ay + 3, ICONS[icon])
  local temp = tostring(round(cur.temperature_2m))
  local tw = GUI.bigText(ax + 21, ay + 3, temp, C.text)
  Screen.text(ax + 21 + tw + 2, ay + 3, C.text, "°C", C.win)
  Screen.text(ax + 21, ay + 9, C.text, name, C.win)
  local lines = {
    {"Ощущается как", signed(cur.apparent_temperature) .. " °C"},
    {"Влажность", round(cur.relative_humidity_2m) .. " %"},
    {"Ветер", string.format("%.1f м/с", tonumber(cur.wind_speed_10m) or 0)},
    {"Давление", round((tonumber(cur.pressure_msl) or 0) * 0.750062) .. " мм рт. ст."},
  }
  for i, l in ipairs(lines) do
    Screen.text(ax + 48, ay + 3 + (i - 1) * 2, C.dim, l[1], C.win)
    Screen.text(ax + 66, ay + 3 + (i - 1) * 2, C.text, l[2], C.win)
  end
  Screen.text(ax + 3, ay + 12, C.text, "Прогноз на 7 дней", C.win)
  local daily = data.daily
  for i = 1, min(7, #(daily.time or {})) do
    local y = ay + 13 + i
    local date = daily.time[i]
    local yy, mm, dd = date:match("^(%d+)-(%d+)-(%d+)")
    local wd = DAYS[System.weekday(tonumber(yy), tonumber(mm), tonumber(dd)) + 1]
    local dname, dicon = condition(daily.weather_code[i])
    local bg = i % 2 == 0 and C.winAlt or C.win
    Screen.rect(ax + 2, y, self.w - 4, 1, bg, nil, " ")
    Screen.text(ax + 3, y, i == 1 and C.accent or C.text, (i == 1 and "Сегодня" or (wd .. " " .. dd .. "." .. mm)), bg)
    Screen.rect(ax + 15, y, 2, 1, GUI.iconColor(ICONS[dicon]), nil, " ")
    Screen.text(ax + 19, y, C.text, GUI.fit(dname, 24), bg)
    Screen.text(ax + 46, y, C.dim, signed(daily.temperature_2m_min[i]) .. "°", bg)
    Screen.text(ax + 54, y, C.text, signed(daily.temperature_2m_max[i]) .. "°", bg)
    local rain = tonumber(daily.precipitation_sum[i]) or 0
    Screen.text(ax + 62, y, rain > 0 and C.accent or C.dim, rain > 0 and string.format("осадки %.1f мм", rain) or "без осадков", bg)
  end
end

local report = c:add(GUI.new(Report, 1, 3, c.w, c.h - 3))

local input = c:add(GUI.input(2, 1, 32, "", "Город, например: Санкт-Петербург"))

local function search()
  local q = input.text:match("^%s*(.-)%s*$")
  if q == "" then return end
  setStatus("Поиск города…")
  Desktop.render()
  local url = "https://geocoding-api.open-meteo.com/v1/search?name=" .. HTTP.urlencode(q) .. "&count=6&language=ru&format=json"
  local body, err = HTTP.request(url, nil, HTTP.browserHeaders(), "GET", {maxBytes = 24 * 1024, timeout = 20})
  if not body then GUI.alert("Погода", "Не удалось найти город:\n" .. tostring(err)) return end
  local d = JSON.decode(body)
  local results = d and d.results
  if type(results) ~= "table" or #results == 0 then GUI.alert("Погода", "Город «" .. q .. "» не найден.") return end
  local names = {}
  for i, r in ipairs(results) do
    names[i] = tostring(r.name) .. (r.admin1 and (", " .. r.admin1) or "") .. (r.country and (", " .. r.country) or "")
  end
  local idx = #results == 1 and 1 or GUI.select("Выберите город", names)
  if not idx then return end
  local r = results[idx]
  city = {name = tostring(r.name), lat = r.latitude, lon = r.longitude}
  System.writeFile(DIR .. "/city.lua", System.serialize(city))
  data = nil
  fetch()
end

input.onSubmit = search
c:add(GUI.button(36, 1, 10, 1, "Найти", search, "primary"))
c:add(GUI.button(48, 1, 14, 1, "Обновить", fetch))
c.focused = input

win.onResize = function()
  status.y, status.w = c.h, c.w
  report.w, report.h = c.w, c.h - 3
end
win:resize(win.w, win.h)

fetch()
]]},
  {"/Users/Desktop/Заметка.txt", [[
Добро пожаловать в CubeOS!

Правый клик по рабочему столу, по иконке в доке и по файлам
открывает контекстное меню.
]]},
  {"/Users/Documents/hello.html", [[
<!doctype html>
<html lang="ru">
<head><meta charset="utf-8"><title>Привет из файла</title></head>
<body>
<h1>Локальная страница</h1>
<p>Эту страницу браузер CubeOS открыл прямо с диска компьютера через <code>file://</code>.</p>
<h2>Что здесь есть</h2>
<ul>
  <li>Заголовки, <b>жирный</b> и <i>курсивный</i> текст</li>
  <li>Ссылки: <a href="https://example.com/">example.com</a>, <a href="cube://start">домашняя страница браузера</a></li>
  <li>Вложенные списки
    <ul><li>Первый уровень</li><li>Ещё один</li></ul>
  </li>
</ul>
<h2>Форма поиска</h2>
<form action="cube://search" method="get">
  <input name="q" size="30" placeholder="Введите запрос">
  <input type="submit" value="Найти">
</form>
<blockquote>Цитата: «Единственный способ сделать великую работу — любить то, что ты делаешь».</blockquote>
<pre>print("Привет, мир!")
for i = 1, 3 do print(i) end</pre>
<table>
  <tr><th>Предмет</th><th>Цена</th></tr>
  <tr><td>Стол</td><td>1 200</td></tr>
  <tr><td>Лампа</td><td>350</td></tr>
</table>
<hr>
<p><small>Страница лежит в /Users/Documents/hello.html — отредактируйте её в Редакторе и обновите (F5).</small></p>
</body>
</html>
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

Горячие клавиши Редактора:  Ctrl+S — сохранить,  Ctrl+O — открыть,
Ctrl+N — новый файл,  F5 — выполнить как Lua.

Приложение RYKEA (магазин мебели) использует Internet Card и базу
Supabase. Настройки подключения: /Applications/RYKEA.app/Config.lua
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

local function cooperate(i)
  -- 52 файла записываются быстро, но уступаем управление,
  -- чтобы OpenComputers не посчитал программу зависшей
  if i % 8 == 0 and os and type(os.sleep) == "function" then os.sleep(0) end
end

local total = 0
for _, f in ipairs(FILES) do total = total + #f[2] end
print("=== Установка CubeOS ===")
print(string.format("Файлов: %d, объём: %d КБ.", #FILES, floor(total / 1024)))
print("")

local disks = {}
for address in component.list("filesystem") do
  local proxy = component.proxy(address)
  if address ~= computer.tmpAddress() and not proxy.isReadOnly() and proxy.spaceTotal() >= total + 32768 then
    disks[#disks + 1] = {address = address, proxy = proxy, label = proxy.getLabel() or "(без имени)"}
  end
end
if #disks == 0 then print("Не найдено подходящих дисков: нужен записываемый диск с запасом места.") return end
for i, d in ipairs(disks) do
  print(string.format("  %d) %-12s %-16s свободно %d КБ", i, d.address:sub(1, 8), d.label,
    floor((d.proxy.spaceTotal() - d.proxy.spaceUsed()) / 1024)))
end
print("")
local disk = disks[tonumber(ask("Номер диска для установки (Enter — отмена): ")) or 0]
if not disk then print("Отменено.") return end
if (ask("Записать CubeOS на диск " .. disk.address:sub(1, 8) .. "? [y/N] ") or ""):lower() ~= "y" then print("Отменено.") return end

for i, file in ipairs(FILES) do
  local path, data = file[1], file[2]
  local dir = path:match("^(.*)/[^/]*$")
  if dir and dir ~= "" then disk.proxy.makeDirectory(dir) end
  local handle, reason = disk.proxy.open(path, "w")
  if not handle then error("Не удалось создать " .. path .. ": " .. tostring(reason)) end
  disk.proxy.write(handle, data)
  disk.proxy.close(handle)
  io.write(string.format("\r[%d/%d] %s", i, #FILES, path:sub(1, 48)))
  FILES[i] = nil
  cooperate(i)
end
disk.proxy.makeDirectory("/Users/Logs")
computer.setBootAddress(disk.address)
print("\nГотово. Файлы записаны, загрузка настроена.")
print("Перезагрузите компьютер: computer.shutdown(true)")
