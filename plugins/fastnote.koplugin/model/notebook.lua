--[[--
model/notebook.lua — one notebook: an ordered list of pages in a UUID directory.

Storage layout:
  <base_dir>/<uuid>/
    notebook.lua      -- metadata: name, created_at, pages list
    page_001.svg
    page_002.svg
    ...

notebook.lua is a plain Lua table returned by a Lua chunk (loadfile-compatible).
--]]--

local Notebook = {}
Notebook.__index = Notebook

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function _uuid()
    -- Compact unique ID: timestamp + random suffix (single-user app, no collision risk).
    return string.format("nb_%d_%06d", os.time(), math.random(0, 999999))
end

local function _write_meta(nb)
    local f = io.open(nb.dir .. "/notebook.lua", "w")
    if not f then return false end
    f:write("return {\n")
    f:write(string.format("  name = %q,\n", nb.name))
    f:write(string.format("  created_at = %d,\n", nb.created_at))
    f:write("  pages = {\n")
    for _, fname in ipairs(nb._pages) do
        f:write(string.format("    %q,\n", fname))
    end
    f:write("  },\n")
    f:write("}\n")
    f:close()
    return true
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

--- Create a brand-new notebook directory with one blank page.
-- @string name      User-visible name.
-- @string base_dir  Parent directory (the notebooks/ folder).
-- @return Notebook
function Notebook.create(name, base_dir)
    math.randomseed(os.time())
    local uuid = _uuid()
    local dir  = base_dir .. "/" .. uuid
    os.execute("mkdir -p " .. dir)

    local nb = setmetatable({
        uuid       = uuid,
        dir        = dir,
        name       = name or "Untitled",
        created_at = os.time(),
        _pages     = {"page_001.svg"},
    }, Notebook)

    _write_meta(nb)
    return nb
end

--- Load a notebook from an existing directory.
-- @string uuid      The directory name (UUID).
-- @string base_dir  Parent directory (the notebooks/ folder).
-- @return Notebook|nil, string?
function Notebook.load(uuid, base_dir)
    local dir   = base_dir .. "/" .. uuid
    local chunk, err = loadfile(dir .. "/notebook.lua")
    if not chunk then
        return nil, "cannot load notebook " .. uuid .. ": " .. (err or "?")
    end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= "table" then
        return nil, "corrupt notebook metadata: " .. dir
    end

    return setmetatable({
        uuid       = uuid,
        dir        = dir,
        name       = t.name or "Untitled",
        created_at = t.created_at or 0,
        _pages     = t.pages or {"page_001.svg"},
    }, Notebook)
end

-- ---------------------------------------------------------------------------
-- Page management
-- ---------------------------------------------------------------------------

--- Number of pages in this notebook.
function Notebook:pageCount()
    return #self._pages
end

--- Absolute path to page N (1-indexed).
-- @number idx  Page index (1..pageCount()).
-- @return string|nil
function Notebook:pagePath(idx)
    local fname = self._pages[idx]
    if not fname then return nil end
    return self.dir .. "/" .. fname
end

--- Append a new blank page and return its index and path.
-- @return number, string  (new_index, absolute_path)
function Notebook:addPage()
    local n     = #self._pages + 1
    local fname = string.format("page_%03d.svg", n)
    self._pages[n] = fname
    _write_meta(self)
    return n, self.dir .. "/" .. fname
end

--- Remove the page at index idx (1-indexed).
-- Does not delete the SVG file — caller is responsible if needed.
function Notebook:deletePage(idx)
    if idx >= 1 and idx <= #self._pages then
        table.remove(self._pages, idx)
        _write_meta(self)
    end
end

--- Rename this notebook.
function Notebook:rename(new_name)
    self.name = new_name
    _write_meta(self)
end

--- Flush metadata to disk (call after any external mutation).
function Notebook:save()
    _write_meta(self)
end

return Notebook
