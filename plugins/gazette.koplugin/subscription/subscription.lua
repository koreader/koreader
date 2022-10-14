local State = require("subscription/state")

local Subscription = State:new{
   last_fetch = nil
}

function Subscription:new(o)
   o = o or {}
   setmetatable(o, self)
   self.__index = self

   o:_init(o)
   o = o:load()

   return o
end

function Subscription:sync()
   return true
end

function Subscription:_init(o)
   self.id = o.id
   self.last_updated = o.last_updated
   self.last_fetch = o.last_fetch
   self.subscription_type = o.subscription_type
end

function Subscription:onSuccessfulSync()
   self.last_fetch = os.date()
end

function Subscription:getTitle()
   return "Untitled"
end

function Subscription:getDescription()
   return ""
end

return Subscription
