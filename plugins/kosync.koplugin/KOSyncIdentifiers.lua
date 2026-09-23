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
local util = require("util")

local TYPE_ORDER = { "content", "structure", "filename" }

-- Identifier types that guarantee the file the position was written against has
-- this one's internal structure, so its xpointer resolves here.
local FOLLOWABLE = {
    content = true,
    structure = true,
}

local MAX_IDENTIFIERS = 8
local CONTAINER_PATH = "META-INF/container.xml"
local OPF_MEDIA_TYPE = "application/oebps-package+xml"

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

--- The name an element is matched by, with any namespace prefix and the end
--- tag's slash dropped.
local function localName(tag)
    return tag:match("([^:/]+)$")
end

-- luxl hands out the source text of an attribute or a text node; every value
-- the digest takes is the one a parser yields.
local function expand(text)
    if not text:find("&", 1, true) then return text end
    return util.htmlEntitiesToUtf8(text)
end

local function trim(text)
    return text:match("^[ \t\r\n]*(.-)[ \t\r\n]*$")
end

--- Path of the OPF package document, from the container's declared rootfile.
local function rootfilePath(container)
    local xlex = lexer(container)
    local tag, attr, attrs
    local declared, first
    for event, offset, size in xlex:Lexemes() do
        local text = ffi.string(xlex.buf + offset, size)
        if event == luxl.EVENT_START then
            tag, attrs = localName(text), {}
        elseif event == luxl.EVENT_ATTR_NAME then
            attr = text
        elseif event == luxl.EVENT_ATTR_VAL and tag == "rootfile" then
            attrs[attr] = expand(text)
            local path = attrs["full-path"]
            if path then
                first = first or path
                if attrs["media-type"] == OPF_MEDIA_TYPE then
                    declared = declared or path
                end
            end
        end
    end
    return declared or first
end

--- Digest of the spine, as the kosync identifier registry defines `structure`:
--- the package's own `dc:identifier` when it has one, then every spine item's
--- manifest href in spine order, joined with newlines.
local function spineDigest(opf)
    local xlex = lexer(opf)
    local tag, attr, attrs, scope
    local unique_id, identifiers = nil, {}
    local manifest, spine = {}, {}

    for event, offset, size in xlex:Lexemes() do
        local text = ffi.string(xlex.buf + offset, size)
        if event == luxl.EVENT_START then
            tag, attrs = localName(text), {}
            if tag == "metadata" or tag == "manifest" or tag == "spine" then
                scope = tag
            end
        elseif event == luxl.EVENT_END then
            if localName(text) == scope then
                scope = nil
            end
            tag = nil
        elseif event == luxl.EVENT_ATTR_NAME then
            attr = text
        elseif event == luxl.EVENT_ATTR_VAL then
            local value = expand(text)
            attrs[attr] = value
            if tag == "package" and attr == "unique-identifier" then
                unique_id = value
            elseif tag == "item" and scope == "manifest" and (attr == "id" or attr == "href") then
                if attrs.id and attrs.href then
                    manifest[attrs.id] = attrs.href
                end
            elseif tag == "itemref" and scope == "spine" and attr == "idref" then
                spine[#spine + 1] = value
            end
        elseif event == luxl.EVENT_TEXT and tag == "identifier" and scope == "metadata" then
            identifiers[#identifiers + 1] = { id = attrs.id, value = expand(text) }
        end
    end

    local lines = {}
    for _, idref in ipairs(spine) do
        local href = manifest[idref]
        if href then
            lines[#lines + 1] = (href:gsub("#.*", ""))
        end
    end
    if #lines == 0 then return end

    local identifier
    for _, candidate in ipairs(identifiers) do
        if candidate.id and candidate.id == unique_id then
            identifier = trim(candidate.value)
            break
        end
    end
    if not identifier or identifier == "" then
        identifier = nil
        for _, candidate in ipairs(identifiers) do
            local value = trim(candidate.value)
            if value ~= "" then
                identifier = value
                break
            end
        end
    end
    if identifier then
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
