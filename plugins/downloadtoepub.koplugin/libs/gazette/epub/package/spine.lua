local Spine = {
    items = nil,
}

function Spine:new(o)
    o = o or {}
    self.__index = self
    setmetatable(o, self)

    o.items = {}

    return o
end

function Spine:addItem(item)
    table.insert(self.items, item)
end

function Spine:build()
    local xml = ""
    for _, item in ipairs(self.items) do
        local part, err = item:getSpinePart()
        if not part
        then
            return false, EpubError.SPINE_BUILD_ERROR
        end
        xml = xml .. part
    end
    return xml
end

return Spine
