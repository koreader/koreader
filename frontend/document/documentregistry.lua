--[[--
This is a registry for document providers
]]--

local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local DocumentRegistry = {
    registry = {},
    providers = {},
    filetype_provider = {},
    mimetype_ext = {},
}

function DocumentRegistry:addProvider(extension, mimetype, provider, weight)
    extension = string.lower(extension)
    table.insert(self.providers, {
        extension = extension,
        mimetype = mimetype,
        provider = provider,
        weight = weight or 100,
    })
    self.filetype_provider[extension] = true
    -- We regard the first extension registered for a mimetype as canonical.
    -- Provided we order the calls to addProvider() correctly, that means
    -- epub instead of epub3, etc.
    self.mimetype_ext[mimetype] = self.mimetype_ext[mimetype] or extension
end

function DocumentRegistry:getRandomFile(dir, opened, extension)
    local DocSettings = require("docsettings")
    if string.sub(dir, string.len(dir)) ~= "/" then
        dir = dir .. "/"
    end
    local files = {}
    local i = 0
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if ok then
        for entry in iter, dir_obj do
            if lfs.attributes(dir .. entry, "mode") == "file" and self:hasProvider(dir .. entry)
                and (opened == nil or DocSettings:hasSidecarFile(dir .. entry) == opened)
                and (extension == nil or extension[util.getFileNameSuffix(entry)]) then
                i = i + 1
                files[i] = entry
            end
        end
        if i == 0 then
            return nil
        end
    else
        return nil
    end
    math.randomseed(os.time())
    return dir .. files[math.random(i)]
end

--- Returns true if file has provider.
-- @string file
-- @treturn boolean
function DocumentRegistry:hasProvider(file, mimetype)
    if mimetype and self.mimetype_ext[mimetype] then
        return true
    end
    if not file then return false end

    local filename_suffix = string.lower(util.getFileNameSuffix(file))

    local filetype_provider = G_reader_settings:readSetting("provider") or {}
    if self.filetype_provider[filename_suffix] or filetype_provider[filename_suffix] then
        return true
    end
    local DocSettings = require("docsettings")
    if DocSettings:hasSidecarFile(file) then
        return DocSettings:open(file):has("provider")
    end
    return false
end

--- Returns the preferred registered document handler.
-- @string file
-- @treturn table provider, or nil
function DocumentRegistry:getProvider(file)
    local providers = self:getProviders(file)

    if providers then
        -- provider for document
        local DocSettings = require("docsettings")
        if DocSettings:hasSidecarFile(file) then
            local doc_settings_provider = DocSettings:open(file):readSetting("provider")
            if doc_settings_provider then
                for _, provider in ipairs(providers) do
                    if provider.provider.provider == doc_settings_provider then
                        return provider.provider
                    end
                end
            end
        end

        -- global provider for filetype
        local filename_suffix = util.getFileNameSuffix(file)
        local g_settings_provider = G_reader_settings:readSetting("provider")

        if g_settings_provider and g_settings_provider[filename_suffix] then
            for _, provider in ipairs(providers) do
                if provider.provider.provider == g_settings_provider[filename_suffix] then
                    return provider.provider
                end
            end
        end

        -- highest weighted provider
        return providers[1].provider
    else
        for _, provider in ipairs(self.providers) do
            if provider.extension == "txt" then
                return provider.provider
            end
        end
    end
end

--- Returns the registered document handlers.
-- @string file
-- @treturn table providers, or nil
function DocumentRegistry:getProviders(file)
    local providers = {}

    --- @todo some implementation based on mime types?
    for _, provider in ipairs(self.providers) do
        local added = false
        local suffix = string.sub(file, -string.len(provider.extension) - 1)
        if string.lower(suffix) == "."..provider.extension then
            for i = #providers, 1, -1 do
                local prov_prev = providers[i]
                if prov_prev.provider == provider.provider then
                    if prov_prev.weight >= provider.weight then
                        added = true
                    else
                        table.remove(providers, i)
                    end
                end
            end
            -- if extension == provider.extension then
            -- stick highest weighted provider at the front
            if not added and #providers >= 1 and provider.weight > providers[1].weight then
                table.insert(providers, 1, provider)
            elseif not added then
                table.insert(providers, provider)
            end
        end
    end

    if #providers >= 1 then
        return providers
    end
end

--- Get mapping of file extensions to providers
-- @treturn table mapping file extensions to a list of providers
function DocumentRegistry:getExtensions()
    local t = {}
    for _, provider in ipairs(self.providers) do
        local ext = provider.extension
        t[ext] = t[ext] or {}
        table.insert(t[ext], provider)
    end
    return t
end

--- Sets the preferred registered document handler.
-- @string file
-- @bool all
function DocumentRegistry:setProvider(file, provider, all)
    local _, filename_suffix = util.splitFileNameSuffix(file)

    -- per-document
    if not all then
        local DocSettings = require("docsettings"):open(file)
        DocSettings:saveSetting("provider", provider.provider)
        DocSettings:flush()
    -- global
    else
        local filetype_provider = G_reader_settings:readSetting("provider") or {}
        filetype_provider[filename_suffix] = provider.provider
        G_reader_settings:saveSetting("provider", filetype_provider)
    end
end

function DocumentRegistry:mimeToExt(mimetype)
    return self.mimetype_ext[mimetype]
end

--- Returns a new Document instance on success
function DocumentRegistry:openDocument(file, provider)
    -- force a GC, so that any previous document used memory can be reused
    -- immediately by this new document without having to wait for the
    -- next regular gc. The second call may help reclaming more memory.
    collectgarbage()
    collectgarbage()
    if not self.registry[file] then
        provider = provider or self:getProvider(file)

        if provider ~= nil then
            local ok, doc = pcall(provider.new, provider, {file = file})
            if ok then
                self.registry[file] = {
                    doc = doc,
                    refs = 1,
                }
            else
                logger.warn("cannot open document", file, doc)
            end
        end
    else
        self.registry[file].refs = self.registry[file].refs + 1
        logger.dbg("DocumentRegistry: Increased refcount to", self.registry[file].refs, "for", file)
    end
    if self.registry[file] then
        return self.registry[file].doc
    end
end

--- Does *NOT* finalize a Document instance, call its :close() instead if that's what you're looking for!
--- (i.e., nothing but Document:close should call this!)
function DocumentRegistry:closeDocument(file)
    if self.registry[file] then
        self.registry[file].refs = self.registry[file].refs - 1
        if self.registry[file].refs == 0 then
            self.registry[file] = nil
            return 0
        else
            return self.registry[file].refs
        end
    else
        error("Tried to close an unregistered file.")
    end
end

--- Queries the current refcount for a given file
function DocumentRegistry:getReferenceCount(file)
    if self.registry[file] then
        return self.registry[file].refs
    else
        return nil
    end
end

-- load implementations:
require("document/credocument"):register(DocumentRegistry)
require("document/pdfdocument"):register(DocumentRegistry)
require("document/djvudocument"):register(DocumentRegistry)
require("document/picdocument"):register(DocumentRegistry)

return DocumentRegistry
