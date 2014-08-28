--[[
This is a registry for document providers
]]--
local DocumentRegistry = {
    registry = {},
    providers = {},
}

function DocumentRegistry:addProvider(extension, mimetype, provider)
    table.insert(self.providers, { extension = extension, mimetype = mimetype, provider = provider })
end

function DocumentRegistry:getProvider(file)
    -- TODO: some implementation based on mime types?
    local extension = string.lower(string.match(file, ".+%.([^.]+)") or "")
    for _, provider in ipairs(self.providers) do
        if extension == provider.extension then
            return provider.provider
        end
    end
end

function DocumentRegistry:openDocument(file)
    if not self.registry[file] then
        local provider = self:getProvider(file)
        if provider ~= nil then
            self.registry[file] = {
                doc = provider:new{file = file},
                refs = 1,
            }
        end
    else
        self.registry[file].refs = self.registry[file].refs + 1
    end
    return self.registry[file].doc
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

require("document/pdfdocument"):register(DocumentRegistry)
require("document/djvudocument"):register(DocumentRegistry)
require("document/credocument"):register(DocumentRegistry)
require("document/picdocument"):register(DocumentRegistry)

return DocumentRegistry
