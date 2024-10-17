--[[ 

A "provider" provides an implementation of a feature set.
A "consumer" consumes implementation details from providers.

Each consumer is tied to a feature set, which has a spec (functions that must be implemented)
The duty of a provider is to implement a spec and register itself for that particular feature.

All providers must be implemented as plugins, prefixed with "provider-"

]]--

local function aTable(t)
    if type(t) ~= "table" then
        return {}
    end
    return t
end

-- Provider is a singleton that holds add-on implementations for features
local Provider = {
    features = {
        ["cloud-storage"] = {},
        ["exporter"] = {},
        ["sync"] = {},
    },
}

function Provider:_isValidFeature(s)
    for k, _ in pairs(self.features) do
        if s == k then
            return true
        end
    end
    return false
end

--[[--
Registers an implementation of a feature.

@param name string that identifies the provider
@param feature string that identifies the feature
@param impl table with implementation details
@treturn bool registered
]]
function Provider:register(name, feature, impl)
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

@param name string provider identifier
@param feature string feature identifier
@treturn bool unregistered
]]
function Provider:unregister(name, feature)
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
    if type(feature) ~= "string" then
        return -1
    end
    if self:_isValidFeature(feature) then
        local t = aTable(self.features[feature])
        local count = 0
        for k, v in pairs(t) do
            count = count + 1
        end
        return count
    end
end

--[[--
Get providers for a given feature

@param feature string feature identifier
@treturn table provider/implementation k/v pairs.
]]
function Provider:getProvidersTable(feature)
    if type(feature) ~= "string" then
        return aTable()
    end
    if self:_isValidFeature(feature) then
	return aTable(self.features[feature])
    end
    return aTable()
end

return Provider
