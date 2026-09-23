--[[--
Extra identifiers a document can be known by, for servers that match a record
against more than one digest.

The list is ordered strongest first: the server walks it in that order, stops at
the first entry that resolves, and reports which one did.
]]

local md5 = require("ffi/sha2").md5

local TYPE_ORDER = { "content", "structure", "filename" }

-- Identifier types that guarantee the file the position was written against has
-- this one's internal structure, so its xpointer resolves here.
local FOLLOWABLE = {
    content = true,
    structure = true,
}

local MAX_IDENTIFIERS = 8
local MAX_CENTRAL_DIRECTORY = 4 * 1024 * 1024

local KOSyncIdentifiers = {}

local function le(str, pos, bytes)
    local n = 0
    for i = bytes - 1, 0, -1 do
        n = n * 256 + str:byte(pos + i)
    end
    return n
end

-- Locate and read the zip central directory, which lists every member with the
-- CRC-32 and size of its *uncompressed* bytes.
local function readCentralDirectory(file)
    local size = file:seek("end")
    local tail_len = math.min(size, 66000) -- end of central directory record, plus its maximum comment
    file:seek("set", size - tail_len)
    local tail = file:read(tail_len)
    if not tail then return end

    local eocd
    for i = #tail - 21, 1, -1 do
        if le(tail, i, 4) == 0x06054b50 then
            eocd = i
            break
        end
    end
    if not eocd then return end

    local count = le(tail, eocd + 10, 2)
    local cd_size = le(tail, eocd + 12, 4)
    local cd_offset = le(tail, eocd + 16, 4)
    if count == 0xFFFF or cd_size == 0xFFFFFFFF or cd_offset == 0xFFFFFFFF then
        return -- zip64, whose real values live in an extra record
    end
    if cd_size == 0 or cd_size > MAX_CENTRAL_DIRECTORY or cd_offset + cd_size > size then return end

    file:seek("set", cd_offset)
    return file:read(cd_size), count
end

--- Digest of a zip container's members: name, CRC-32 and uncompressed size of
--- each, sorted by name. Unpacking and repacking an EPUB changes every byte of
--- the file and none of these.
function KOSyncIdentifiers.structureDigest(filepath)
    if not filepath then return end
    local file = io.open(filepath, "rb")
    if not file then return end
    if file:read(4) ~= "PK\3\4" then
        file:close()
        return
    end
    local cd, count = readCentralDirectory(file)
    file:close()
    if not cd then return end

    local entries, pos = {}, 1
    for _ = 1, count do
        if pos + 45 > #cd or le(cd, pos, 4) ~= 0x02014b50 then return end
        local crc = le(cd, pos + 16, 4)
        local uncompressed = le(cd, pos + 24, 4)
        local name_len = le(cd, pos + 28, 2)
        local extra_len = le(cd, pos + 30, 2)
        local comment_len = le(cd, pos + 32, 2)
        if pos + 45 + name_len > #cd then return end
        local name = cd:sub(pos + 46, pos + 45 + name_len)
        -- Repackers disagree about storing directory entries
        if name:sub(-1) ~= "/" then
            entries[#entries + 1] = string.format("%s\0%08x\0%d\n", name, crc, uncompressed)
        end
        pos = pos + 46 + name_len + extra_len + comment_len
    end
    if #entries == 0 then return end
    table.sort(entries)
    return md5(table.concat(entries))
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
