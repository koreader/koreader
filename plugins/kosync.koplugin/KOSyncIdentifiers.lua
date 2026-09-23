--[[--
Extra identifiers a document can be known by, for servers that match a record
against more than one digest.

The list is ordered strongest first: the server walks it in that order, stops at
the first entry that resolves, and reports which one did.
]]

local Archiver = require("ffi/archiver")
local ffi = require("ffi")
local luxl = require("luxl")
local md5 = require("ffi/sha2").md5

local TYPE_ORDER = { "content", "structure", "filename" }

-- Identifier types that guarantee the file the position was written against has
-- this one's internal structure, so its xpointer resolves here.
local FOLLOWABLE = {
    content = true,
    structure = true,
}

local MAX_IDENTIFIERS = 8
local CONTAINER_PATH = "META-INF/container.xml"

local KOSyncIdentifiers = {}

-- Stops at the wanted member instead of walking the whole archive.
local function readEntry(arc, path)
    for entry in arc:iterate() do
        if entry.path == path then
            return arc:extractToMemory(path)
        end
    end
end

local function lexer(xml)
    -- luxl has no notion of comments
    xml = xml:gsub("<!%-%-.-%-%->", "")
    return luxl.new(xml, #xml)
end

--- Path of the OPF package document, from the container's first rootfile.
local function rootfilePath(container)
    local xlex = lexer(container)
    local tag, attr
    for event, offset, size in xlex:Lexemes() do
        local text = ffi.string(xlex.buf + offset, size)
        if event == luxl.EVENT_START then
            tag = text
        elseif event == luxl.EVENT_ATTR_NAME then
            attr = text
        elseif event == luxl.EVENT_ATTR_VAL and tag == "rootfile" and attr == "full-path" then
            return text
        end
    end
end

--- Digest of the spine, as the kosync identifier registry defines `structure`:
--- the package's own `dc:identifier` when it has one, then every spine item's
--- manifest href in spine order, joined with newlines.
local function spineDigest(opf)
    local xlex = lexer(opf)
    local tag, attr, attrs
    local unique_id, identifiers = nil, {}
    local manifest, spine, in_spine = {}, {}, false

    for event, offset, size in xlex:Lexemes() do
        local text = ffi.string(xlex.buf + offset, size)
        if event == luxl.EVENT_START then
            tag, attrs = text, {}
            if tag == "spine" then
                in_spine = true
            end
        elseif event == luxl.EVENT_END then
            if text == "/spine" then
                in_spine = false
            end
            tag = nil
        elseif event == luxl.EVENT_ATTR_NAME then
            attr = text
        elseif event == luxl.EVENT_ATTR_VAL then
            attrs[attr] = text
            if tag == "package" and attr == "unique-identifier" then
                unique_id = text
            elseif tag == "item" and (attr == "id" or attr == "href") then
                if attrs.id and attrs.href then
                    manifest[attrs.id] = attrs.href
                end
            elseif tag == "itemref" and attr == "idref" and in_spine then
                spine[#spine + 1] = text
            end
        elseif event == luxl.EVENT_TEXT and tag == "dc:identifier" then
            identifiers[#identifiers + 1] = { id = attrs.id, value = text }
        end
    end

    local lines = {}
    for _, idref in ipairs(spine) do
        local href = manifest[idref]
        if href then
            -- the href exactly as written, minus any fragment
            lines[#lines + 1] = (href:gsub("#.*", ""))
        end
    end
    if #lines == 0 then return end

    local identifier = identifiers[1]
    for _, candidate in ipairs(identifiers) do
        if candidate.id and candidate.id == unique_id then
            identifier = candidate
            break
        end
    end
    identifier = identifier and identifier.value:match("^%s*(.-)%s*$")
    if identifier and identifier ~= "" then
        table.insert(lines, 1, identifier)
    end

    return md5(table.concat(lines, "\n"))
end

--- Digest of an EPUB's spine. Repacking, recompressing and rewriting the
--- contents of every chapter and image all leave it alone; adding, removing or
--- reordering a chapter changes it.
function KOSyncIdentifiers.structureDigest(filepath)
    if not filepath then return end
    local file = io.open(filepath, "rb")
    if not file then return end
    local magic = file:read(4)
    file:close()
    if magic ~= "PK\3\4" then return end

    local arc = Archiver.Reader:new()
    if not arc:open(filepath) then return end
    local container = readEntry(arc, CONTAINER_PATH)
    local rootfile = container and rootfilePath(container)
    local opf = rootfile and readEntry(arc, rootfile)
    arc:close()
    if not opf then return end

    return spineDigest(opf)
end

--- Build the list to send, strongest first. The server requires the document
--- digest to be among the entries, and takes its position as preference rather
--- than identity, so the digest this document happens to be addressed by does
--- not have to lead.
-- @param document the digest the document is addressed by
-- @param parts table of content and filename digests, and the file path
function KOSyncIdentifiers.build(document, parts)
    if not document then return end
    local values = {
        content = parts.content,
        filename = parts.filename,
        structure = KOSyncIdentifiers.structureDigest(parts.file),
    }

    local list, has_document = {}, false
    for _, id_type in ipairs(TYPE_ORDER) do
        local value = values[id_type]
        if value and #list < MAX_IDENTIFIERS then
            list[#list + 1] = { type = id_type, value = value }
            has_document = has_document or value == document
        end
    end
    if not has_document then return end

    return list
end

--- Flatten the list into the `ids` query parameter of a progress read.
function KOSyncIdentifiers.query(identifiers)
    if not identifiers then return end
    local parts = {}
    for i, identifier in ipairs(identifiers) do
        parts[i] = identifier.type .. ":" .. identifier.value
    end
    return table.concat(parts, ",")
end

--- Whether a stored position can be followed to the letter.
-- `progress_match` names the strongest identifier this device shares with the
-- device that wrote the position. Anything weaker than the document's own
-- structure means it was written against a file that need not lay out the same
-- way, so its xpointer or page number does not carry over. A server that does
-- not match on identifiers sends no such field, and its records are addressed by
-- the document digest alone.
function KOSyncIdentifiers.canFollowProgress(progress_match)
    if progress_match == nil then return true end
    return FOLLOWABLE[progress_match] == true
end

return KOSyncIdentifiers
