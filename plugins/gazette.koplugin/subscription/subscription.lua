local _ = require("gettext")

local State = require("subscription/state")

local Subscription = State:extend{
    url = nil
}

function Subscription:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self

   o = o:load()

   return o
end

function Subscription:onSuccessfulSync()
   self.last_fetch = os.date()
end

return Subscription
