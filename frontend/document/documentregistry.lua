--[[--
This is a registry for document providers
]]--

local logger = require("logger")

local DocumentRegistry = {
    registry = {},
    providers = {},
}

function DocumentRegistry:addProvider(extension, mimetype, provider, weight)
    table.insert(self.providers, {
        extension = extension,
        mimetype = mimetype,
        provider = provider,
        weight = weight or 100,
    })
end

--- Returns the preferred registered document handler.
-- @string file
-- @treturn string provider, or nil
function DocumentRegistry:getProvider(file)
    local providers = self:getProviders(file)

    if providers then
        return providers[1].provider
    end
end

--- Returns the registered document handlers.
-- @string file
-- @treturn table providers, or nil
function DocumentRegistry:getProviders(file)
    local providers = {}

    -- TODO: some implementation based on mime types?
    for _, provider in ipairs(self.providers) do
        local suffix = string.sub(file, -string.len(provider.extension) - 1)
        if string.lower(suffix) == "."..provider.extension then
        -- if extension == provider.extension then
            -- stick highest weighted provider at the front
            if #providers >= 1 and provider.weight > providers[1].weight then
                table.insert(providers, 1, provider)
            else
                table.insert(providers, provider)
            end
        end
    end

    if #providers >= 1 then
        return providers
    end
end

function DocumentRegistry:openDocument(file)
    -- force a GC, so that any previous document used memory can be reused
    -- immediately by this new document without having to wait for the
    -- next regular gc. The second call may help reclaming more memory.
    collectgarbage()
    collectgarbage()
    if not self.registry[file] then
        local provider = self:getProvider(file)
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
    end
    if self.registry[file] then
        return self.registry[file].doc
    end
end

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
        error("Try to close unregistered file.")
    end
end

-- load implementations:

require("document/credocument"):register(DocumentRegistry)
require("document/pdfdocument"):register(DocumentRegistry)
require("document/djvudocument"):register(DocumentRegistry)
require("document/picdocument"):register(DocumentRegistry)

return DocumentRegistry
