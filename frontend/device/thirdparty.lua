-- module for integration with thirdparty applications
local logger = require("logger")

local roles = {
    "dict",
    "translator",
}

local M = {}

function M:new(o)
    -- platform specific function to check availability of apps at runtime.
    if not o.check or type(o.check) ~= "function" then
        o.check = function(app) return false end
    end
    setmetatable(o, self)
    self.__index = self

    -- one-time availability check
    for _, role in pairs(roles) do
        -- user override, if available
        local user_file = role == "dict" and "dictionaries.lua" or role .. "s.lua"
        local user = require("datastorage"):getDataDir() .. "/" .. user_file
        local ok, user_dicts = pcall(dofile, user)
        if ok then
            o[role.."s"] = user_dicts
            o.is_user_list = true
        end
        for i, value in ipairs(o[role.."s"] or {}) do
            local app = value[4]
            if app and o:check(app) then
                value[3] = true
            end
        end
    end
    if o.is_user_list then
        logger.info(o:dump())
    end
    return o
end

function M:checkMethod(role, method)
    local tool, action = nil
    for i, v in ipairs(self[role.."s"] or {}) do
        if v[1] == method then
            tool = v[4]
            action = v[5]
            break
        end
    end
    if not tool and not action then
        return false
    else
        return true, tool, action
    end
end

function M:dump()
    local str = "user defined thirdparty apps\n"
    for i, role in ipairs(roles) do
        local apps = self[role.."s"]
        for index, _ in ipairs(apps or {}) do
            str = str .. string.format("-> %s (%s), role: %s, available: %s\n",
                apps[index][1], apps[index][4], role, tostring(apps[index][3]))
        end
    end
    return str
end

return M
