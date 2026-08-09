local lfs = require("libs/libkoreader-lfs")

local OCR = {}

-- Returns a sorted array of detected Tesseract language codes.
function OCR.getOCRLangs()
    local langs = {}
    local seen = {}
    local candidates = {}
    local ki = require("document/koptinterface").tessocr_data
    if ki then table.insert(candidates, ki) end
    local env = os.getenv("TESSDATA_PREFIX")
    if env then
        table.insert(candidates, env)
        table.insert(candidates, env .. "/tessdata")
    end
    for _, dir in ipairs(candidates) do
        if dir and lfs.attributes(dir, "mode") == "directory" then
            for file in lfs.dir(dir) do
                if file and file ~= "." and file ~= ".." and file:sub(-12) == ".traineddata" then
                    local code = file:sub(1, -13)
                    if not seen[code] then seen[code] = true; table.insert(langs, code) end
                end
            end
        end
    end
    table.sort(langs)
    return langs
end

return OCR
