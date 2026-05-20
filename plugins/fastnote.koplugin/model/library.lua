--[[--
model/library.lua — all notebooks, plus app-wide state.

Storage layout (under <koreader_data>/fastnote/):
  state.lua           -- last_notebook_uuid, last_page_index
  notebooks/
    <uuid>/           -- one dir per notebook
      notebook.lua
      page_001.svg
      ...

Directory scanning uses io.popen("ls") — works on Kobo Linux.
--]]--

local Notebook = require("model/notebook")

local Library = {}
Library.__index = Library

--- Open the library rooted at base_dir (e.g. <datadir>/fastnote).
-- Creates the notebooks sub-directory if missing.
-- @string base_dir  Absolute path (no trailing slash).
function Library.new(base_dir)
    os.execute("mkdir -p " .. base_dir .. "/notebooks")
    local self = setmetatable({
        base_dir  = base_dir,
        _nbs      = {},   -- uuid -> Notebook
        _order    = {},   -- ordered list of uuids (insertion / mtime order)
    }, Library)
    self:_scan()
    return self
end

-- ---------------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------------

function Library:_nb_dir()
    return self.base_dir .. "/notebooks"
end

function Library:_scan()
    local handle = io.popen("ls -1 " .. self:_nb_dir() .. " 2>/dev/null")
    if not handle then return end
    for entry in handle:lines() do
        -- Each entry should be a UUID dir containing notebook.lua
        local meta = self:_nb_dir() .. "/" .. entry .. "/notebook.lua"
        local f    = io.open(meta, "r")
        if f then
            f:close()
            local nb, err = Notebook.load(entry, self:_nb_dir())
            if nb then
                self._nbs[entry]           = nb
                self._order[#self._order + 1] = entry
            end
        end
    end
    handle:close()
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

function Library:notebookCount()
    return #self._order
end

--- Return notebook by UUID, or nil.
function Library:byUUID(uuid)
    return self._nbs[uuid]
end

--- Return notebook by position (1-indexed), or nil.
function Library:byIndex(idx)
    local uuid = self._order[idx]
    return uuid and self._nbs[uuid]
end

--- Ordered list of all notebooks.
function Library:all()
    local out = {}
    for _, uuid in ipairs(self._order) do
        out[#out + 1] = self._nbs[uuid]
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Mutations
-- ---------------------------------------------------------------------------

--- Create a new notebook, add it to the library, and return it.
-- @string name  User-visible name (optional, defaults to "Untitled").
function Library:createNotebook(name)
    local nb = Notebook.create(name or "Untitled", self:_nb_dir())
    self._nbs[nb.uuid]             = nb
    self._order[#self._order + 1]  = nb.uuid
    return nb
end

--- Remove a notebook from the library and delete its directory.
-- @string uuid
function Library:deleteNotebook(uuid)
    local nb = self._nbs[uuid]
    if not nb then return end
    os.execute("rm -rf " .. nb.dir)
    self._nbs[uuid] = nil
    for i, u in ipairs(self._order) do
        if u == uuid then table.remove(self._order, i); break end
    end
end

-- ---------------------------------------------------------------------------
-- App-wide state (last_notebook_uuid, last_page_index)
-- ---------------------------------------------------------------------------

local function _state_path(base_dir)
    return base_dir .. "/state.lua"
end

--- Read persisted state. Returns {} on missing/corrupt file.
function Library:readState()
    local chunk = loadfile(_state_path(self.base_dir))
    if chunk then
        local ok, t = pcall(chunk)
        if ok and type(t) == "table" then return t end
    end
    return {}
end

--- Write state table to disk.
-- Only string and number values are persisted.
function Library:writeState(t)
    local f = io.open(_state_path(self.base_dir), "w")
    if not f then return end
    f:write("return {\n")
    for k, v in pairs(t) do
        local vt = type(v)
        if vt == "string" then
            f:write(string.format("  %s = %q,\n", k, v))
        elseif vt == "number" then
            f:write(string.format("  %s = %d,\n", k, v))
        end
    end
    f:write("}\n")
    f:close()
end

return Library
