--[[--
This is a registry for document providers
]]--

local DocSettings = require("docsettings")
local logger = require("logger")
local util = require("util")

local DocumentRegistry = {
    registry = {},
    providers = {},
    known_providers = {}, -- hash table of registered providers { provider_key = provider }
    filetype_provider = {},
    mimetype_ext = {},
    image_ext = {
        gif  = true,
        jpeg = true,
        jpg  = true,
        png  = true,
        svg  = true,
        tif  = true,
        tiff = true,
        webp = true,
    },
}

local function getSuffix(file)
    return util.getFileNameSuffix(file):lower()
end

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
    -- Provided we order the calls to addProvider() correctly,
    -- that means epub instead of epub3, etc.
    self.mimetype_ext[mimetype] = self.mimetype_ext[mimetype] or extension
    if self.known_providers[provider.provider] == nil then
        self.known_providers[provider.provider] = provider
    end
end

-- Register an auxiliary (non-document) provider.
-- Aux providers are modules (eg TextViewer) or plugins (eg TextEditor).
-- It does not implement the Document API.
-- For plugins the hash table value does not contain file handler,
-- but only a provider_key (provider.provider) to call the corresponding
-- plugin in FileManager:openFile().
function DocumentRegistry:addAuxProvider(provider)
    self.known_providers[provider.provider] = provider
end

--- Returns true if file has provider.
-- @string file
-- @bool include_aux include auxiliary (non-document) providers
-- @treturn boolean
function DocumentRegistry:hasProvider(file, mimetype, include_aux)
    if mimetype and self.mimetype_ext[mimetype] then
        return true
    end
    if not file then return false end

    -- registered document provider
    local filename_suffix = getSuffix(file)
    if self.filetype_provider[filename_suffix] then
        return true
    end
    -- associated document or auxiliary provider for file type
    local filetype_provider_key = G_reader_settings:readSetting("provider", {})[filename_suffix]
    local provider = filetype_provider_key and self.known_providers[filetype_provider_key]
    if provider and (not provider.order or include_aux) then -- excluding auxiliary by default
        return true
    end
    -- associated document provider for this file
    if DocSettings:hasSidecarFile(file) then
        return DocSettings:open(file):has("provider")
    end
    return false
end

--- Returns the preferred registered document handler or fallback provider.
-- @string file
-- @bool include_aux include auxiliary (non-document) providers
-- @treturn table provider
function DocumentRegistry:getProvider(file, include_aux)
    local providers = self:getProviders(file)
    if providers or include_aux then
        -- associated provider
        local provider_key = DocumentRegistry:getAssociatedProviderKey(file)
        local provider = provider_key and self.known_providers[provider_key]
        if provider and (not provider.order or include_aux) then -- excluding auxiliary by default
            return provider
        end
        -- highest weighted provider
        return providers and providers[1].provider
    end
    return self:getFallbackProvider()
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

function DocumentRegistry:getProviderFromKey(provider_key)
    return self.known_providers[provider_key]
end

function DocumentRegistry:getFallbackProvider()
    for _, provider in ipairs(self.providers) do
        if provider.extension == "txt" then
            return provider.provider
        end
    end
end

function DocumentRegistry:getAssociatedProviderKey(file, all)
    -- all: nil - first not empty, false - this file, true - file type

    if not file then -- get the full list of associated providers
        return G_reader_settings:readSetting("provider")
    end

    -- provider for this file
    local provider_key
    if all ~= true then
        if DocSettings:hasSidecarFile(file) then
            provider_key = DocSettings:open(file):readSetting("provider")
            if provider_key or all == false then
                return provider_key
            end
        end
        if all == false then return end
    end

    -- provider for file type
    local providers = G_reader_settings:readSetting("provider")
    provider_key = providers and providers[getSuffix(file)]
    if provider_key and self.known_providers[provider_key] then
        return provider_key
    end
end

-- Returns array: registered auxiliary providers sorted by order.
function DocumentRegistry:getAuxProviders()
    local providers = {}
    for _, provider in pairs(self.known_providers) do
        if provider.order then -- aux
            table.insert(providers, provider)
        end
    end
    if #providers >= 1 then
        table.sort(providers, function(a, b) return a.order < b.order end)
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
    provider = provider or {} -- call with nil to reset
    -- per-document
    if not all then
        local doc_settings = DocSettings:open(file)
        doc_settings:saveSetting("provider", provider.provider)
        doc_settings:flush()
    -- global
    else
        local filetype_provider = G_reader_settings:readSetting("provider", {})
        filetype_provider[getSuffix(file)] = provider.provider
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

function DocumentRegistry:isImageFile(file)
    return self.image_ext[getSuffix(file)] and true or false
end

-- load implementations:
require("document/credocument"):register(DocumentRegistry)
require("document/pdfdocument"):register(DocumentRegistry)
require("document/djvudocument"):register(DocumentRegistry)
require("document/picdocument"):register(DocumentRegistry)
-- auxiliary built-in
require("ui/widget/imageviewer"):register(DocumentRegistry)
require("ui/widget/textviewer"):register(DocumentRegistry)
-- auxiliary from plugins

return DocumentRegistry
