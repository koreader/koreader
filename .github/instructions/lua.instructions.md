---
applyTo: "plugins/fastnote.koplugin/**/*.lua"
paths:
  - "plugins/fastnote.koplugin/**/*.lua"
description: "Lua 5.1/LuaJIT conventions and gotchas for fastnote.koplugin code."
---

# Lua conventions — fastnote.koplugin

Lua 5.1 / LuaJIT rules for this codebase. Read before writing any Lua here.
Bugs caused by ignoring these have already been filed and fixed — don't repeat them.

---

## CRITICAL: `_` is the gettext function, not a throwaway

KOReader modules begin with:

```lua
local _ = require("gettext")
```

This means **`_` is callable** (`_("some string")` returns the translated string).

### The bug this causes

```lua
-- WRONG — the loop variable _ shadows gettext
for _, item in ipairs(list) do
    local label = _("Name")   -- runtime crash: _ is now a number (the ipairs index)
end
```

### The fix

Use `__` (double underscore) for every throwaway loop variable:

```lua
-- RIGHT
for __, item in ipairs(list) do
    local label = _("Name")   -- _ is still gettext; safe
end
```

The project `.luacheckrc` suppresses `211/__*` (unused) and `231/__*` (undefined-as-global)
warnings, so `__` is always the correct convention here. There is no other acceptable
throwaway name.

---

## Variable naming — no cryptic abbreviations

Single-letter or two-letter names are almost always wrong outside of tight math loops.
These were real bugs in this codebase:

| Was | Now | Why the old name was wrong |
|-----|-----|---------------------------|
| `local t = p / max_p` | `local pressure_ratio = ...` | `t` is opaque |
| `local s = 2*r + 1` | `local brush_side = ...` | `s` is opaque |
| `local pd = slots[i]` | `local pen_data = ...` | abbreviation leaks intent |
| `local s = self._mt_cur` | `local slot = ...` | shadowed MT slot tracking |
| `local e` (event loop) | `local event` | single letter in a 400-line function |

**Acceptable exceptions:**

| Name | Context |
|------|---------|
| `x`, `y` | 2D coordinates — unambiguous in this codebase |
| `i`, `j` | Integer loop counters in tight numerical code |
| `k`, `v` | Short `for k, v in pairs(t)` iterations, obvious types |
| `n` | Explicit array length: `local n = #t` |
| `r` | Radius in a geometry function, when documented |

---

## For-loop closure capture

In Lua's **generic for**, each iteration creates new locals for the loop variables.
Closures inside the loop correctly capture the per-iteration value — no alias needed:

```lua
-- WRONG: unnecessary alias (leftover from incorrect mental model)
for __, item in ipairs(list) do
    local item_ref = item         -- delete this
    table.insert(result, {
        callback = function() use(item_ref) end
    })
end

-- RIGHT: item is already per-iteration
for __, item in ipairs(list) do
    table.insert(result, {
        callback = function() use(item) end   -- correct
    })
end
```

This holds for numeric `for i = 1, n do` as well — `i` is a new local each iteration.

---

## `require()` caching — module-level state is a singleton

`require("lib/foo")` returns the same table on every call (cached after the first load).
Module-level variables are shared across all callers for the lifetime of the process.

```lua
-- lib/foo.lua
local M = {}
local _shared_counter = 0      -- ONE instance process-wide; mutation is visible everywhere

function M:new()
    return setmetatable({       -- per-instance state goes here, not in M
        _count = 0,
    }, M)
end

return M
```

Use module-level variables only for **constants** and **pure lookup tables**.
Per-instance mutable state always goes in the object returned by `new()`.

---

## Named constants for magic numbers

Any literal that has a name in the domain belongs in a `local UPPER_CASE` constant
at the top of the file. Numbers scattered through poll loops and callbacks become
invisible:

```lua
-- Bad
UIManager:scheduleIn(0.008, ...)
UIManager:scheduleIn(0.016, ...)
UIManager:scheduleIn(30, ...)

-- Good
local PEN_POLL_INTERVAL   = 0.008   -- ~120 Hz pen sampling
local TOUCH_POLL_INTERVAL = 0.016   -- ~60 Hz touch sampling
local IDLE_SAVE_DELAY     = 30      -- seconds before auto-save fires
```

Put constants at the file top (after `require` calls), not inside functions.

---

## Method syntax: `:` vs `.`

```lua
function M:method(a)   -- M.method = function(self, a) — self is implicit
function M.func(a)     -- no self; called as M.func(a)
```

Rule: if the function accesses or mutates `self` (or the table it belongs to), use `:`.
Pure helpers that take no object state use `.`.

When calling: `obj:method()` passes `obj` as first arg; `obj.method()` does not.
Mixing these up produces "attempt to index a nil value (local 'self')" errors that
are hard to diagnose.

---

## The `and`/`or` ternary pitfall

```lua
local val = condition and a or b    -- ternary-like, but has a hole
```

If `condition` is true but `a` is `false` or `nil`, `b` is returned instead of `a`.

Safe only when you know `a` can never be `false` or `nil`. When in doubt:

```lua
local val
if condition then val = a else val = b end
```

---

## Falsy values: only `nil` and `false`

Unlike Python or JavaScript, **`0`, `""`, and `{}` are all truthy** in Lua:

```lua
if 0    then print("yes") end   -- prints "yes"
if ""   then print("yes") end   -- prints "yes"
if {}   then print("yes") end   -- prints "yes"
```

Guard for existence (`if x then`) only tests for nil/false, not for empty.
Use `if x ~= nil then` if you want to accept `false` as a valid value.

---

## `#` only works on sequences

`#t` returns the length of the sequence portion (consecutive integer keys 1..n).
A sparse table gives undefined results:

```lua
local t = {1, 2, nil, 4}   -- #t is undefined (may return 2 or 4)
```

Never store `nil` as an array element. To remove, shift elements or use a sentinel.

---

## `pcall` for all external I/O

File reads, JSON decoding, and `loadfile` calls can fail. Always use `pcall`:

```lua
local ok, data = pcall(json.decode, raw_string)
if not ok then
    logger.warn("fastnote: parse error:", data)
    return {}
end
```

A corrupt page file must degrade gracefully — never propagate an uncaught error
into the KOReader UI event loop.

---

## `ffi.cdef` — never define the same struct twice

LuaJIT throws "attempt to redefine" if `ffi.cdef` is called with a previously
declared struct. Always guard with `pcall`:

```lua
pcall(ffi.cdef, [[struct input_event { ... };]])
```

Never put `ffi.cdef` inside a function that may be called more than once.

---

## GC pressure in hot paths

The pen poll loop runs at ~120 Hz. Avoid creating new tables or closures per tick:

```lua
-- Avoid inside the poll callback body:
local dirty = {x = x0, y = y0, w = w, h = h}   -- allocates every 8 ms

-- OK: closures for UIManager:scheduleIn are unavoidable, but don't add more
```

Persistent scratch tables (allocated once at `init` and reused) are preferred
over per-call allocations in tight loops.

---

## Integer division

Lua 5.1 has no `//` operator. Use `math.floor`:

```lua
local half = math.floor(n / 2)
```

---

## Naming conventions in this codebase

| Pattern | Usage |
|---------|-------|
| `_foo` function or var | Module-private (convention only — Lua doesn't enforce it) |
| `M` | The module table returned at end of a library file |
| `UPPER_CASE` | Module-level constants |
| `__` | Throwaway loop variable (safe with gettext `_`) |
| `self._field` | Per-instance private state in OO-style classes |
| `camelCase` | Methods on KOReader widget classes (inherited from KOReader) |
| `snake_case` | Functions in pure-Lua `lib/` modules |

---

## Extract helpers when a pattern repeats

Three copies of the same code means it needs a name. Recent examples from this plugin:

```lua
-- Extracted from three identical call sites:
function DrawingCanvas:_doEraseAt(x, y)
    local removed = self._stroke_buf:eraseAt(x, y, ERASER_RADIUS)
    if #removed > 0 then
        self._page_dirty = true
        self:_repaintAll()
    end
end

-- Extracted from three identical call sites:
function DrawingCanvas:_refreshRect(rect)
    UIManager:setDirty(self, function() return "a2", Geom:new(rect) end)
end
```

The threshold is: if you find yourself copy-pasting a block a second time, name it.

---

## Checklist before committing

- [ ] No `_` used as a loop throwaway — changed to `__`
- [ ] No single-letter or two-letter names in non-trivial scope
- [ ] New magic numbers named as `local UPPER_CASE = ...` at file top
- [ ] No `ffi.cdef` inside a callable function
- [ ] All file I/O and JSON decode wrapped in `pcall`
- [ ] `busted spec/` passes (run from `plugins/fastnote.koplugin/`)
