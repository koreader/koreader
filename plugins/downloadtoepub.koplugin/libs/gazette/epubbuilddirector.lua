local Epub32Writer = require("libs/gazette/epub32writer")

local EpubBuildDirector = {
    writer = nil,
    epub = nil,
    result = nil,
}

function EpubBuildDirector:new(writer)
    if not writer
    then
        local defaultWriter, err = Epub32Writer:new{}
        if not defaultWriter
        then
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
    if ok
    then
        -- Use case for returning path as result could be: if writer
        -- adjusts path to account for existing file.
        -- E.g.: my_new_epub_didnot_overwrite_anything(1).epub
        -- Or maybe we want to get the filesize of the doc. Etc!
        -- Best to build the bones for the routine. A gift for the future!
        self.result = self.writer.path
        return true
    else
        return false, err
    end
end

function EpubBuildDirector:getResult()
    return self.result
end

return EpubBuildDirector
