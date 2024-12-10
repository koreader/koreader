--[[

Provider is a singleton that holds thirdparty implementations for features.

To be used on plugins, prefixed with "provider-", that implement specific feature APIs.

]]--

local util = require("util")

local function aTable(t)
    if type(t) ~= "table" then
        return {}
    end
    return t
end

local Provider = {
    features = {
        ["exporter"] = {},
    },
}

function Provider:_isValidFeature(s)
    return self.features[s] ~= nil
end

--[[--
Registers an implementation of a feature.

@param feature string that identifies the feature
@param name string that identifies the provider
@param impl table with implementation details
@treturn bool registered
]]
function Provider:register(feature, name, impl)
    if type(name) ~= "string" or type(feature) ~= "string" or type(impl) ~= "table" then
        return false
    end
    if self:_isValidFeature(feature) then
        self.features[feature][name] = impl
        return true
    end
    return false
end

--[[--
Unregisters an implementation of a feature.

@param feature string feature identifier
@param name string provider identifier
@treturn bool unregistered
]]
function Provider:unregister(feature, name)
    if type(name) ~= "string" or type(feature) ~= "string" then
        return false
    end
    if self:_isValidFeature(feature) then
        self.features[feature][name] = nil
        return true
    end
    return false
end

--[[--
Counts providers for a given feature

@param feature string feature identifier
@treturn int number
]]
function Provider:size(feature)
    local count = 0
    if self:_isValidFeature(feature) then
        count = util.tableSize(aTable(self.features[feature]))
    end
    return count
end

--[[--
Get providers for a given feature

@param feature string feature identifier
@treturn table provider/implementation k/v pairs.
]]
function Provider:getProvidersTable(feature)
    if self:_isValidFeature(feature) then
        return aTable(self.features[feature])
    end
    return aTable()
end

return Provider
