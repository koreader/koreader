--[[
This is a registry for document providers
]]--
local DocumentRegistry = {
    providers = { }
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
    local provider = self:getProvider(file)
    if provider ~= nil then
        return provider:new{file = file}
    end
end

-- load implementations:

require("document/pdfdocument"):register(DocumentRegistry)
require("document/djvudocument"):register(DocumentRegistry)
require("document/credocument"):register(DocumentRegistry)
require("document/picdocument"):register(DocumentRegistry)

return DocumentRegistry
