local Package = require("libs/gazette/epub/package")

local Epub = Package:new{

}

function Epub:new(o)
    o = Package:new()

    self.__index = self
    setmetatable(o, self)

    return o
end

function Epub:addFromList(iterator)
    while true do
        local item = iterator()
        if type(item) == "table"
        then
            self:addItem(item)
        elseif item == nil
        then
            break
        end
    end
end

-- Need a way to add a Webpage, which is an XHtmlItem and possibly images, scripts, and styles.
-- Would this be a Epub method, or would it be elsewhere? The method would basically take the
-- content returned by a HTTP request and then do the following:
--- 1) Extract images, rewrite the URLs, and download the images
--- 2) Get the content, filter it
--- 3) Get styles (?)

return Epub
