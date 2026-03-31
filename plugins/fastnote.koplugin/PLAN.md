# fastnote.koplugin — Development Plan

A KOReader plugin that provides a full-screen pen drawing canvas, built in four
phases of increasing sophistication.

---

## Phase A — Minimal working drawing app

**Goal:** Get a pen stroke on screen. Nothing else matters yet.

### Files to create

```
plugins/fastnote.koplugin/
├── _meta.lua
├── main.lua
└── drawingcanvas.lua
```

### `_meta.lua`

Standard plugin metadata. No logic.

```lua
local _ = require("gettext")
return {
    name        = "fastnote",
    fullname    = _("Ink Canvas"),
    description = _([[Full-screen pen drawing canvas.]]),
}
```

### `main.lua` — plugin skeleton

- Extend `WidgetContainer`.
- Register a `Dispatcher` action `open_ink_canvas` so it appears in KOReader's
  gesture-assignment settings (Menu → Gesture Manager → assign to any swipe).
- `addToMainMenu` adds an entry under **More tools** as a fallback activation method.
- The action handler calls `UIManager:show(DrawingCanvas:new{})`.

Key imports:
```lua
local Dispatcher      = require("dispatcher")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DrawingCanvas   = require("plugins/fastnote.koplugin/drawingcanvas")
```

### `drawingcanvas.lua` — the canvas widget

Extend `InputContainer` (gives us touch zone registration and key events for free).

**`init()`**

1. Allocate full-screen `BlitBuffer`:
   ```lua
   local Screen = require("device").screen
   self.dimen = Screen:getSize()
   self.bb = Blitbuffer.new(self.dimen.w, self.dimen.h, Blitbuffer.TYPE_BB8)
   self.bb:fill(Blitbuffer.COLOR_WHITE)
   ```
2. Register touch zones (see below).

**`paintTo(bb, x, y)`**

Blit the canvas onto whatever the UIManager passes in:
```lua
bb:blitFrom(self.bb, x, y, 0, 0, self.dimen.w, self.dimen.h)
```

**Touch zone: drawing**

```lua
{
    id = "canvas_pan",
    ges = "pan",
    screen_zone = { ratio_x=0, ratio_y=0, ratio_w=1, ratio_h=1 },
    handler = function(ges) self:onStroke(ges) end,
}
```

`pan` events carry:
- `ges.pos`      — current `Geom` point
- `ges.relative` — delta from last point (so prev point = `ges.pos - ges.relative`)

**Drawing a segment**

```lua
function DrawingCanvas:onStroke(ges)
    local px = ges.pos.x - ges.relative.x
    local py = ges.pos.y - ges.relative.y
    local cx, cy = ges.pos.x, ges.pos.y

    self.bb:paintLine(px, py, cx, cy, self.line_width, self.ink_color)

    local margin = self.line_width + 1
    UIManager:setDirty(self, "fast", Geom:new{
        x = math.min(px, cx) - margin,
        y = math.min(py, cy) - margin,
        w = math.abs(cx - px) + 2*margin,
        h = math.abs(cy - py) + 2*margin,
    })
end
```

**Touch zone: exit**

Small hold zone in the top-left corner (60×60 px). On `hold`:
```lua
UIManager:close(self)
```
This pops the canvas off the widget stack and returns to whatever was open before
(book, file browser, etc.) with no special cleanup needed.

**Screen update modes (eink)**

| Event               | setDirty mode | Reason                              |
|---------------------|---------------|-------------------------------------|
| Canvas open/close   | `"full"`      | Full refresh, no ghosting           |
| Every stroke segment| `"fast"`      | Low-latency, accepts ghosting       |
| Pen lift            | `"ui"`        | Light partial refresh               |

### What to test at the end of Phase A

- [ ] Plugin appears in More tools menu
- [ ] Swipe gesture opens a white screen
- [ ] Finger/pen draw leaves black lines
- [ ] Hold top-left corner closes canvas and returns to previous screen
- [ ] No crash on open/close cycle

---

## Phase B — Save to SVG

**Goal:** Persist drawings as `.svg` files in a sensible location.

### New file: `strokebuffer.lua`

Maintains an in-memory list of strokes. A stroke is a sequence of `{x, y}` points
(pressure data can be kept here too for future use).

```lua
StrokeBuffer = {}
StrokeBuffer.__index = StrokeBuffer

function StrokeBuffer.new()
    return setmetatable({ strokes = {}, current = nil }, StrokeBuffer)
end

function StrokeBuffer:penDown(x, y)
    self.current = { {x=x, y=y} }
end

function StrokeBuffer:penMove(x, y)
    if self.current then
        table.insert(self.current, {x=x, y=y})
    end
end

function StrokeBuffer:penUp()
    if self.current and #self.current > 1 then
        table.insert(self.strokes, self.current)
    end
    self.current = nil
end

function StrokeBuffer:toSVG(width, height, color, stroke_width)
    color = color or "#000000"
    stroke_width = stroke_width or 2
    local lines = {
        string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', width, height),
        string.format('<rect width="%d" height="%d" fill="white"/>', width, height),
    }
    for _, stroke in ipairs(self.strokes) do
        local pts = {}
        for i, p in ipairs(stroke) do
            pts[i] = string.format("%d,%d", math.floor(p.x), math.floor(p.y))
        end
        table.insert(lines, string.format(
            '<polyline points="%s" fill="none" stroke="%s" stroke-width="%d" stroke-linecap="round" stroke-linejoin="round"/>',
            table.concat(pts, " "), color, stroke_width
        ))
    end
    table.insert(lines, "</svg>")
    return table.concat(lines, "\n")
end
```

### Wiring saving into `drawingcanvas.lua`

- Instantiate `StrokeBuffer` on canvas init.
- On each `pan` event feed `penMove`. On `pan_release` or pen-up, call `penUp`.
- Add a second exit zone (or a long hold in a different corner) that triggers save
  before closing.

**Save path:**
```lua
local DataStorage = require("datastorage")
local save_dir = DataStorage:getDataDir() .. "/fastnote/"
-- filename: fastnote_YYYY-MM-DD_HH-MM-SS.svg
local filename = os.date("fastnote_%Y-%m-%d_%H-%M-%S") .. ".svg"
```

**Write:**
```lua
local f = io.open(save_dir .. filename, "w")
f:write(self.stroke_buf:toSVG(self.dimen.w, self.dimen.h, "#000000", self.line_width))
f:close()
UIManager:show(InfoMessage:new{ text = "Saved: " .. filename, timeout = 2 })
```

**`pan_release` zone** — needed to reliably detect pen-up via the gesture path:
```lua
{
    id = "canvas_pan_release",
    ges = "pan_release",
    screen_zone = { ratio_x=0, ratio_y=0, ratio_w=1, ratio_h=1 },
    handler = function(ges)
        self.stroke_buf:penUp()
    end,
}
```

### What to test at the end of Phase B

- [ ] Each completed stroke is captured in the buffer
- [ ] Save produces a valid `.svg` file
- [ ] SVG opened in a desktop browser shows the same drawing
- [ ] File is written to `<koreader_data>/fastnote/`
- [ ] Save+close gesture is distinct from just-close gesture

---

## Phase C — Raw evdev input (educational)

**Goal:** Bypass `GestureDetector` entirely. Read `struct input_event` directly from
`/dev/input/eventX`, parse the Linux input protocol, and drive the canvas from that.

This replicates what `frontend/device/input.lua` does internally, but under your
direct control.

### Finding the pen device

Parse `/proc/bus/input/devices` at canvas open time:

```lua
local function find_pen_device()
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    local current_name, current_handlers
    for line in content:gmatch("[^\n]+") do
        local name = line:match('^N: Name="(.*)"')
        if name then current_name = name end

        local handlers = line:match("^H: Handlers=(.*)")
        if handlers then current_handlers = handlers end

        -- Kobo Elipsa/Sage: "Wacom I2C Digitizer"
        -- Other Kobos: look for "Pen" in name
        if current_name and current_handlers
        and (current_name:match("[Pp]en") or current_name:match("Wacom")) then
            local event_node = current_handlers:match("(event%d+)")
            if event_node then
                return "/dev/input/" .. event_node
            end
        end
    end
    return nil
end
```

### FFI setup

`ffi/linux_input_h` (already required by KOReader's `input.lua`) defines
`struct input_event` and the `EV_*`, `ABS_*`, `BTN_*` constants. Reuse them:

```lua
local ffi = require("ffi")
local C   = ffi.C
require("ffi/posix_h")
require("ffi/linux_input_h")
```

constants you'll use:
```
EV_SYN = 0   EV_KEY = 1   EV_ABS = 3
ABS_X = 0    ABS_Y = 1    ABS_PRESSURE = 24
BTN_TOUCH = 330    BTN_TOOL_PEN = 320
SYN_REPORT = 0
```

### Opening the device and querying range

```lua
function DrawingCanvas:openPenDevice(path)
    self.pen_fd = C.open(path, C.O_RDONLY + C.O_NONBLOCK)
    if self.pen_fd < 0 then
        logger.err("fastnote: cannot open pen device", path)
        return false
    end

    -- Query the digitizer's absolute axis ranges via EVIOCGABS ioctl
    local absinfo = ffi.new("struct input_absinfo")
    if C.ioctl(self.pen_fd, C.EVIOCGABS(C.ABS_X), absinfo) >= 0 then
        self.digi_x_min = absinfo.minimum
        self.digi_x_max = absinfo.maximum
    else
        -- Safe fallback values (Kobo Elipsa is 0–4095)
        self.digi_x_min, self.digi_x_max = 0, 4095
    end
    if C.ioctl(self.pen_fd, C.EVIOCGABS(C.ABS_Y), absinfo) >= 0 then
        self.digi_y_min = absinfo.minimum
        self.digi_y_max = absinfo.maximum
    else
        self.digi_y_min, self.digi_y_max = 0, 4095
    end
    if C.ioctl(self.pen_fd, C.EVIOCGABS(C.ABS_PRESSURE), absinfo) >= 0 then
        self.digi_p_min = absinfo.minimum
        self.digi_p_max = absinfo.maximum
    else
        self.digi_p_min, self.digi_p_max = 0, 1024
    end

    logger.dbg("fastnote: pen device opened:", path)
    logger.dbg("  X range [%d, %d]", self.digi_x_min, self.digi_x_max)
    logger.dbg("  Y range [%d, %d]", self.digi_y_min, self.digi_y_max)
    logger.dbg("  P range [%d, %d]", self.digi_p_min, self.digi_p_max)
    return true
end
```

### Polling loop

Schedule at ~120 Hz from UIManager's tick queue. Drains the entire kernel buffer
each tick.

```lua
function DrawingCanvas:startRawLoop()
    self._raw_active = true
    UIManager:scheduleIn(0, function() self:rawTick() end)
end

function DrawingCanvas:rawTick()
    if not self._raw_active then return end

    local ev = ffi.new("struct input_event")
    local ev_size = ffi.sizeof(ev)

    while true do
        local n = C.read(self.pen_fd, ev, ev_size)
        if n < 0 then break end   -- EAGAIN: buffer empty
        if n == ev_size then
            self:processRawEvent(ev.type, ev.code, ev.value)
        end
    end

    UIManager:scheduleIn(0.008, function() self:rawTick() end)
end

function DrawingCanvas:stopRawLoop()
    self._raw_active = false
    if self.pen_fd and self.pen_fd >= 0 then
        C.close(self.pen_fd)
        self.pen_fd = -1
    end
end
```

### Raw event state machine

```lua
function DrawingCanvas:processRawEvent(ev_type, code, value)
    if ev_type == C.EV_ABS then
        if code == C.ABS_X then
            self._raw_x = value
        elseif code == C.ABS_Y then
            self._raw_y = value
        elseif code == C.ABS_PRESSURE then
            self._raw_p = value
            -- drop hover events (pressure == 0 while pen not touching)
            if value == 0 and self._pen_down then
                self:onRawPenUp()
            end
        end

    elseif ev_type == C.EV_KEY then
        if code == C.BTN_TOUCH then
            if value == 1 then
                self:onRawPenDown(self._raw_x, self._raw_y, self._raw_p)
            else
                self:onRawPenUp()
            end
        end

    elseif ev_type == C.EV_SYN then
        if code == C.SYN_REPORT and self._pen_down then
            self:onRawPenMove(self._raw_x, self._raw_y, self._raw_p)
        end
    end
end
```

### Coordinate translation

```lua
-- Maps raw digitizer integers → screen pixels, respecting rotation.
function DrawingCanvas:digToScreen(raw_x, raw_y)
    local Screen = require("device").screen
    local w = Screen:getWidth()
    local h = Screen:getHeight()

    local sx = (raw_x - self.digi_x_min) / (self.digi_x_max - self.digi_x_min) * w
    local sy = (raw_y - self.digi_y_min) / (self.digi_y_max - self.digi_y_min) * h

    -- TODO: account for screen rotation (Screen:getRotationMode())
    return math.floor(sx), math.floor(sy)
end
```

### Pen callbacks

Replace Phase A's `onStroke(ges)` with these:

```lua
function DrawingCanvas:onRawPenDown(rx, ry, rp)
    self._pen_down = true
    local sx, sy = self:digToScreen(rx, ry)
    self._last_sx, self._last_sy = sx, sy
    self.stroke_buf:penDown(sx, sy)
end

function DrawingCanvas:onRawPenMove(rx, ry, rp)
    local sx, sy = self:digToScreen(rx, ry)
    local lx, ly = self._last_sx or sx, self._last_sy or sy

    -- Pressure → line width
    local norm = (rp - self.digi_p_min) / (self.digi_p_max - self.digi_p_min)
    local width = math.floor(1 + norm^1.5 * 7)  -- 1–8 px

    self.bb:paintLine(lx, ly, sx, sy, width, self.ink_color)
    self.stroke_buf:penMove(sx, sy)

    self._last_sx, self._last_sy = sx, sy

    local m = width + 1
    UIManager:setDirty(self, "fast", Geom:new{
        x = math.min(lx, sx) - m, y = math.min(ly, sy) - m,
        w = math.abs(sx - lx) + 2*m, h = math.abs(sy - ly) + 2*m,
    })
end

function DrawingCanvas:onRawPenUp()
    self._pen_down = false
    self.stroke_buf:penUp()
    self._last_sx, self._last_sy = nil, nil
    UIManager:setDirty(self, "ui")
end
```

### Replacing Phase A input without breaking the plugin structure

Keep Phase A's touch-zone drawing active as a fallback flag:

```lua
self.use_raw_input = true  -- flip to false to revert to gesture path
```

In `init()`, branch on this flag to either call `self:openPenDevice(...)` +
`self:startRawLoop()` or just use the `registerTouchZones` path from Phase A.

### What to test at the end of Phase C

- [ ] `/proc/bus/input/devices` parsing finds the correct `eventX` node
- [ ] `EVIOCGABS` returns sane range values (log them at startup)
- [ ] Strokes appear at the correct screen position (no offset or mirroring)
- [ ] Pressure variation visibly changes line width
- [ ] Hover (pen near screen, not touching) does not draw
- [ ] Canvas still closes cleanly (fd is closed, rawTick loop exits)
- [ ] Switching `use_raw_input = false` restores Phase A gesture behaviour

---

## Phase D — Color picker

**Goal:** Let the user choose ink color before or during drawing.

### Where to add UI

Two sensible trigger spots:
1. **Bottom-right corner hold** — opens a small color picker overlay on top of
   the canvas. Non-destructive (canvas stays underneath, strokes continue on dismiss).
2. **Menu entry** — for users who added the plugin to the main menu; set a
   persistent default color in `G_reader_settings`.

### Color representation

KOReader's BlitBuffer operates in grayscale (TYPE_BB8) on most eink devices.
On a grayscale display, "color" means gray level. On devices with color eink
(Kobo Libra Colour etc.), you can use Blitbuffer.TYPE_BBRGB32 and full RGB.

#### Grayscale-only path (safe everywhere)

```lua
local shade_list = {
    { label = "Black",    color = Blitbuffer.COLOR_BLACK      },
    { label = "Dark gray",color = Blitbuffer.gray(0.25)       },
    { label = "Gray",     color = Blitbuffer.gray(0.5)        },
    { label = "Light",    color = Blitbuffer.gray(0.75)       },
}
```

#### Color eink path (Kobo Libra Colour, etc.)

```lua
local color_list = {
    { label = "Black",  color = Blitbuffer.colorRGB(0,   0,   0  ) },
    { label = "Red",    color = Blitbuffer.colorRGB(220, 20,  20 ) },
    { label = "Blue",   color = Blitbuffer.colorRGB(30,  80,  200) },
    { label = "Green",  color = Blitbuffer.colorRGB(20,  160, 20 ) },
}
```

Detect at runtime:
```lua
local Screen = require("device").screen
self.use_color = Screen:isColorEnabled()
local palette = self.use_color and color_list or shade_list
```

### Color picker overlay widget

A simple `ButtonDialog` or custom `OverlapGroup` — show it on top of the canvas
without closing the canvas:

```lua
local ButtonDialog = require("ui/widget/buttondialog")

function DrawingCanvas:showColorPicker()
    local buttons = {}
    for _, entry in ipairs(self.palette) do
        table.insert(buttons, {{
            text = entry.label,
            callback = function()
                self.ink_color = entry.color
                UIManager:close(self._color_picker)
                self._color_picker = nil
            end,
        }})
    end
    self._color_picker = ButtonDialog:new{
        title    = "Ink color",
        buttons  = buttons,
    }
    UIManager:show(self._color_picker)
end
```

Register the trigger zone:

```lua
{
    id = "canvas_color_picker",
    ges = "hold",
    screen_zone = {
        ratio_x = 1 - (60/self.dimen.w),
        ratio_y = 0,
        ratio_w = 60/self.dimen.w,
        ratio_h = 60/self.dimen.h,
    },
    handler = function() self:showColorPicker() end,
}
```

### SVG color output update (links back to Phase B)

`StrokeBuffer` needs to track per-stroke color. Add `color` as a field on each
stroke entry, set at `penDown` time. In `toSVG`, use each stroke's `.color` field
instead of the global parameter.

### What to test at the end of Phase D

- [ ] Hold bottom-right opens color picker without closing canvas
- [ ] Selecting a new color affects only new strokes (old ones unchanged)
- [ ] Saved SVG has correct per-stroke color values
- [ ] On a grayscale device, all "colors" display as distinct visible shades
- [ ] On a color device (if available), strokes render in the chosen color

---

## Summary of files and their phases

| File                     | Created in | Modified in  |
|--------------------------|------------|--------------|
| `_meta.lua`              | A          | —            |
| `main.lua`               | A          | —            |
| `drawingcanvas.lua`      | A          | B, C, D      |
| `strokebuffer.lua`       | B          | C (pressure), D (color) |

---

## Suggested test device: Kobo Elipsa 2E or Sage

Both use the Wacom EMR pen via `wacom_protocol = true` in KOReader's Kobo device
layer. The pen device is typically `/dev/input/event1` or `/dev/input/event2`.
Cross-check with:

```sh
cat /proc/bus/input/devices | grep -A6 -i "wacom\|pen"
```

To watch raw events live from the shell (useful during Phase C debugging):

```sh
evtest /dev/input/event2
```
