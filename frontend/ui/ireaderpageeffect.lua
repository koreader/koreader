local Device = require("device")
local ffiutil = require("ffi/util")

local KEY = "ireader_page_effect"
local MAP_KEY = "ireader_page_effect_files"
local FACTORY = "ripple_standard"

local IReaderPageEffect = {}

function IReaderPageEffect.enabled()
    return Device.isIReaderEink and Device:isIReaderEink()
end

function IReaderPageEffect.normalize(file)
    if not file or file == "" then
        return nil
    end
    local ok, real = pcall(ffiutil.realpath, file)
    if ok and real then
        return real
    end
    return file
end

function IReaderPageEffect.default()
    return G_reader_settings:readSetting(KEY) or FACTORY
end

function IReaderPageEffect.fromDoc(doc_settings)
    return doc_settings and doc_settings:readSetting(KEY)
end

function IReaderPageEffect.fileMapGet(file)
    file = IReaderPageEffect.normalize(file)
    local map = G_reader_settings:readSetting(MAP_KEY)
    if not file or not map then
        return nil
    end
    if map[file] then
        return map[file]
    end
    for k, v in pairs(map) do
        if IReaderPageEffect.normalize(k) == file then
            return v
        end
    end
end

function IReaderPageEffect.fileMapSet(file, id)
    file = IReaderPageEffect.normalize(file)
    if not file or not id then
        return
    end
    local map = G_reader_settings:readSetting(MAP_KEY) or {}
    local changed = map[file] ~= id
    for k in pairs(map) do
        if k ~= file and IReaderPageEffect.normalize(k) == file then
            map[k] = nil
            changed = true
        end
    end
    map[file] = id
    if changed then
        G_reader_settings:saveSetting(MAP_KEY, map)
    end
end

function IReaderPageEffect.currentFile(ui, doc_settings)
    if ui and ui.document and ui.document.file then
        return ui.document.file
    end
    if doc_settings then
        local doc_path = doc_settings:readSetting("doc_path")
        if doc_path then
            return doc_path
        end
    end
    return G_reader_settings and G_reader_settings:readSetting("lastfile")
end

function IReaderPageEffect.resolve(ui, doc_settings)
    doc_settings = doc_settings or (ui and ui.doc_settings)
    local value = IReaderPageEffect.fromDoc(doc_settings)
    if value then
        return value
    end
    value = IReaderPageEffect.fileMapGet(IReaderPageEffect.currentFile(ui, doc_settings))
    if value then
        return value
    end
    return IReaderPageEffect.default()
end

function IReaderPageEffect.persist(ui, id, doc_settings)
    doc_settings = doc_settings or (ui and ui.doc_settings)
    if doc_settings then
        doc_settings:saveSetting(KEY, id)
        doc_settings:flush()
    end
    IReaderPageEffect.fileMapSet(IReaderPageEffect.currentFile(ui, doc_settings), id)
    G_reader_settings:flush()
end

function IReaderPageEffect.pinCurrent(ui, doc_settings, flush_doc)
    if not IReaderPageEffect.enabled() then
        return
    end
    doc_settings = doc_settings or (ui and ui.doc_settings)
    if not doc_settings then
        return
    end
    local value = IReaderPageEffect.fromDoc(doc_settings)
    if not value then
        value = IReaderPageEffect.resolve(ui, doc_settings)
        doc_settings:saveSetting(KEY, value)
        if flush_doc then
            doc_settings:flush()
        end
    end
    IReaderPageEffect.fileMapSet(IReaderPageEffect.currentFile(ui, doc_settings), value)
end

function IReaderPageEffect.saveAsDefault(ui)
    if not IReaderPageEffect.enabled() then
        return
    end
    local effect = IReaderPageEffect.resolve(ui)
    G_reader_settings:saveSetting(KEY, effect)
    G_reader_settings:flush()
end

-- Called after sidecar keys are wiped by “Reset document settings to default”.
-- Write the current global default into this book and drop any leftover override.
function IReaderPageEffect.onDocumentReset(file, doc_settings)
    if not IReaderPageEffect.enabled() then
        return
    end
    local effect = IReaderPageEffect.default()
    if doc_settings then
        doc_settings:saveSetting(KEY, effect)
    end
    IReaderPageEffect.fileMapSet(file, effect)
    G_reader_settings:flush()
end

return IReaderPageEffect
