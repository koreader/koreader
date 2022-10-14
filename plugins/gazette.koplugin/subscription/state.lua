local DataStorage = require("datastorage")
local LuaSettings = require("frontend/luasettings")

local State  = {
   id = nil,
   lua_settings = nil,
}

State.STATE_FILE = "gazette_subscription_config.lua"
State.ID_PREFIX = "subscription_"
State.DATA_STORAGE_DIR = DataStorage:getSettingsDir()

function State:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self
   o:init()
   return o
end

function State:init()
   self.lua_settings = LuaSettings:open(("%s/%s"):format(self.DATA_STORAGE_DIR, self.STATE_FILE))

   if not self.lua_settings
   then
      return false
   end
end

function State:load()
   local state = self.lua_settings:child(self.id)

   local state_has_data = false
   for key, value in pairs(state.data) do
      state_has_data = true
      self[key] = value
   end

   if not state_has_data and
      self.id ~= nil
   then
      return false
   end

   return self
end

function State:save()
   if not self.id
   then
      self.id = self:generateUniqueId()
   end

   self.lua_settings:saveSetting(self.id, self)
   self.lua_settings:flush()
end

function State:delete()
   self.lua_settings:delSetting(self.id)
   self.lua_settings:flush()
end

function State:generateUniqueId(maybe_id)
   maybe_id = maybe_id or 1
   local maybe_key = self.ID_PREFIX .. tostring(maybe_id)

   if not self.lua_settings:has(maybe_key)
   then
      return maybe_key
   end

   return self:generateUniqueId(maybe_id + 1)
end

function State:deleteConfig(dir, filename)
   os.remove(("%s/%s"):format(dir, filename))
   os.remove(("%s/%s.old"):format(dir, filename))
end

return State
