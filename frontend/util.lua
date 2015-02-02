
local util = {}

function util.stripePunctuations(word)
    if not word then return end
    -- strip ASCII punctuation characters around word
    -- and strip any generic punctuation (U+2000 - U+206F) in the word
    return word:gsub("\226[\128-\131][\128-\191]",''):gsub("^%p+",''):gsub("%p+$",'')
end

return util
