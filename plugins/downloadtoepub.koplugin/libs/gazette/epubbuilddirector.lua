local Epub32Writer = require("libs/gazette/epub32writer")

local EpubBuildDirector = {
    writer = nil,
    epub = nil,
}

function EpubBuildDirector:new(writer)
    if not writer then
        local defaultWriter, err = Epub32Writer:new{}
        if not defaultWriter then
            return false, err
        end
        self.writer = defaultWriter
    else
        self.writer = writer
    end
    return self
end

function EpubBuildDirector:setDestination(path)
    return self.writer:setPath(path)
end

function EpubBuildDirector:construct(epub)
    local ok, err = self.writer:build(epub)
    if ok then
        return self.writer.path
    else
        return false, err
    end
end

return EpubBuildDirector
