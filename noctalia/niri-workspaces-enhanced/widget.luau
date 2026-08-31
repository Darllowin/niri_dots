--!nonstrict
-- Niri workspace switcher with per-workspace app icons.
-- Port of waybar-niri-workspaces-enhanced. Reads workspace/window state from
-- `niri msg --json` and renders one clickable pill per workspace, colored by
-- state and listing the app glyphs open on it.
--
-- Live updates come from `niri msg event-stream` (instant), with a slow
-- polling fallback in case the stream dies (e.g. niri restarted). Refreshes
-- are coalesced: an event that arrives while a refresh is still running
-- schedules exactly one follow-up, so event bursts never lose their tail.

local workspaces = nil
local windows = nil
-- Output (connector name) of the workspace that currently has keyboard focus.
-- Niri resolves a workspace *index* against the focused output, so clicks on
-- workspaces of other monitors need a focus-monitor detour (see focus()).
local focusedOutput = nil

-- Guards for the refresh coalescing (see refresh()).
local refreshInFlight = false
local refreshPending = false

local function lower(s)
  if s == nil then
    return ""
  end
  return string.lower(s)
end

-- Normalizes the configured app-id -> glyph map. The docs promise an
-- associative table, but we also tolerate a list of {key, value} rows and
-- skip empty values, so a half-broken save from the settings GUI degrades
-- to the default icon instead of wiping every glyph off the bar.
local function normalizeIconMap(cfg)
  local icons = {}
  if type(cfg) ~= "table" then
    return icons
  end
  for k, v in pairs(cfg) do
    if type(k) == "string" and type(v) == "string" and v ~= "" then
      icons[lower(k)] = v
    elseif type(v) == "table" then
      local kk = v.key or v.app_id or v[1]
      local vv = v.value or v.glyph or v[2]
      if type(kk) == "string" and type(vv) == "string" and vv ~= "" then
        icons[lower(kk)] = vv
      end
    end
  end
  return icons
end

local function cmpPos(a, b)
  local pa = a.layout and a.layout.pos_in_scrolling_layout or {}
  local pb = b.layout and b.layout.pos_in_scrolling_layout or {}
  local n = math.max(#pa, #pb)
  for i = 1, n do
    local xa = pa[i] or 0
    local xb = pb[i] or 0
    if xa ~= xb then
      return xa < xb
    end
  end
  return false
end

local function focus(ws)
  -- Just send the command. The event stream (or the fallback poll) refreshes
  -- the state afterwards; refreshing here races niri's focus processing and
  -- can capture the pre-switch state, inverting the highlight.
  --
  -- `focus-workspace <idx>` resolves the index against the *currently
  -- focused* output, so for a workspace living on another monitor we first
  -- focus its monitor. The nested runAsync guarantees the ordering (the
  -- second command is only sent after the first one exited).
  if ws.output ~= nil and focusedOutput ~= nil and ws.output ~= focusedOutput then
    noctalia.runAsync("niri msg action focus-monitor " .. ws.output, function()
      noctalia.runAsync("niri msg action focus-workspace " .. tostring(ws.idx))
    end)
  else
    noctalia.runAsync("niri msg action focus-workspace " .. tostring(ws.idx))
  end
end

-- Expands the `format` template (same placeholders as the original module):
-- {index}, {name}, {index-and-name}, {value}, {separator}, {window-icons}.
-- Unknown placeholders are left untouched.
local function formatLabel(fmt, ws, separator, windowIcons)
  local index = tostring(ws.idx)
  local name = ws.name or ""
  local indexAndName = index
  if name ~= "" then
    indexAndName = index .. " " .. name
  end
  local value = name ~= "" and name or index
  local sep = windowIcons ~= "" and separator or ""

  return (string.gsub(fmt, "{([a-z-]+)}", function(key)
    if key == "index" then
      return index
    elseif key == "name" then
      return name
    elseif key == "index-and-name" then
      return indexAndName
    elseif key == "value" then
      return value
    elseif key == "separator" then
      return sep
    elseif key == "window-icons" then
      return windowIcons
    end
    return nil
  end))
end

local function render()
  local iconDefault = noctalia.getConfig("icon_default") or "*"
  local separator = noctalia.getConfig("separator") or ": "
  local format = noctalia.getConfig("format") or "| {index-and-name}{separator}{window-icons} |"
  local focusedColor = noctalia.getConfig("focused_color") or "secondary"
  local activeColor = noctalia.getConfig("active_color") or "secondary"
  local occupiedColor = noctalia.getConfig("occupied_color") or "on_surface"
  local emptyColor = noctalia.getConfig("empty_color") or "on_surface_variant"
  local urgentColor = noctalia.getConfig("urgent_color") or "error"
  local gap = noctalia.getConfig("gap") or 0
  local paddingH = noctalia.getConfig("padding_h") or 4

  -- The whole icon map lives in the user's saved settings: the GUI replaces
  -- the map wholesale on every save, so nothing may live in code or in the
  -- manifest default. Apps without a configured glyph get icon_default.
  local icons = normalizeIconMap(noctalia.getConfig("window_icons"))

  -- Sort workspaces by output first, then by their displayed index: the
  -- index is per-output in niri, so a global idx-only sort would interleave
  -- duplicate numbers on multi-monitor setups.
  local sorted = {}
  for _, ws in ipairs(workspaces or {}) do
    table.insert(sorted, ws)
  end
  table.sort(sorted, function(a, b)
    local oa = a.output or ""
    local ob = b.output or ""
    if oa ~= ob then
      return oa < ob
    end
    return (a.idx or 0) < (b.idx or 0)
  end)

  -- Group windows by workspace id.
  local byWs = {}
  for _, w in ipairs(windows or {}) do
    if w.workspace_id ~= nil then
      local list = byWs[w.workspace_id]
      if list == nil then
        list = {}
        byWs[w.workspace_id] = list
      end
      table.insert(list, w)
    end
  end

  local rows = {}
  for _, ws in ipairs(sorted) do
    local list = byWs[ws.id] or {}
    table.sort(list, cmpPos)

    local glyphs = {}
    for _, w in ipairs(list) do
      if w.app_id == nil or w.app_id == "" then
        table.insert(glyphs, iconDefault)
      else
        table.insert(glyphs, icons[lower(w.app_id)] or iconDefault)
      end
    end

    local label = formatLabel(format, ws, separator, table.concat(glyphs, " "))

    local color
    if ws.is_urgent then
      color = urgentColor
    elseif ws.is_focused then
      color = focusedColor
    elseif ws.is_active then
      color = activeColor
    elseif #glyphs > 0 then
      color = occupiedColor
    else
      color = emptyColor
    end

    table.insert(rows, ui.row({
      key = "ws-" .. tostring(ws.id),
      paddingH = paddingH,
      align = "center",
      onClick = function()
        focus(ws)
      end,
    }, {
      ui.label({ text = label, color = color }),
    }))
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = gap, align = "center" }, rows))
end

local function maybeRender()
  if workspaces ~= nil and windows ~= nil then
    render()
  end
end

local function refresh()
  -- Trailing-edge coalescing: only one refresh (a pair of `niri msg`
  -- processes) runs at a time; events that arrive meanwhile schedule exactly
  -- one follow-up. Event bursts therefore collapse to at most two refreshes
  -- and, unlike a fixed debounce window, the final state is never dropped.
  if refreshInFlight then
    refreshPending = true
    return
  end
  refreshInFlight = true

  local remaining = 2
  local function done()
    remaining = remaining - 1
    if remaining > 0 then
      return
    end
    refreshInFlight = false
    if refreshPending then
      refreshPending = false
      refresh()
      return
    end
    maybeRender()
  end

  noctalia.runAsync("niri msg --json workspaces", function(res)
    if res.exitCode == 0 then
      local data = noctalia.json.decode(res.stdout)
      if data ~= nil then
        workspaces = data
        focusedOutput = nil
        for _, ws in ipairs(data) do
          if ws.is_focused then
            focusedOutput = ws.output
            break
          end
        end
      end
    end
    done()
  end)
  noctalia.runAsync("niri msg --json windows", function(res)
    if res.exitCode == 0 then
      local data = noctalia.json.decode(res.stdout)
      if data ~= nil then
        windows = data
      end
    end
    done()
  end)
end

function update()
  -- Slow fallback poll in case the event stream dies (e.g. niri restarted).
  noctalia.setUpdateInterval(noctalia.getConfig("refresh_ms") or 5000)
  -- Watchdog: if the callbacks of a previous refresh were dropped entirely
  -- (e.g. niri died mid-request), don't stay wedged on refreshInFlight.
  refreshInFlight = false
  refreshPending = false
  refresh()
end

function onScroll(axis, steps)
  if axis ~= "vertical" then
    return
  end
  if steps < 0 then
    noctalia.runAsync("niri msg action focus-workspace-up")
  elseif steps > 0 then
    noctalia.runAsync("niri msg action focus-workspace-down")
  end
end

-- Instant updates: niri event-stream prints a line whenever workspaces or
-- windows change. Any line triggers a (coalesced) refresh.
noctalia.runStream("niri msg event-stream", function(_line)
  refresh()
end)
