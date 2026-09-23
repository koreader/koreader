describe("KOSyncIdentifiers module", function()
    local Archiver, DataStorage, KOSyncIdentifiers
    local leaves = "spec/front/unit/data/leaves.epub"
    local juliet = "spec/front/unit/data/juliet.epub"

    setup(function()
        require("commonrequire")
        package.path = "plugins/kosync.koplugin/?.lua;" .. package.path
        Archiver = require("ffi/archiver")
        DataStorage = require("datastorage")
        KOSyncIdentifiers = require("KOSyncIdentifiers")
    end)

    local function writeEpub(dest, members)
        local writer = Archiver.Writer:new()
        assert(writer:open(dest, "epub"))
        writer:setZipCompression("store")
        for _, member in ipairs(members) do
            writer:addFileFromMemory(member.path, member.content)
        end
        writer:close()
    end

    -- Repack an EPUB storing its members in reverse order, passing each through
    -- `rewrite`, as an optimizer that re-encodes images and injects a stylesheet
    -- into every chapter does.
    local function repack(source, dest, rewrite)
        local members = {}
        local arc = Archiver.Reader:new()
        assert(arc:open(source))
        for entry in arc:iterate() do
            if entry.mode == "file" then
                table.insert(members, 1, { path = entry.path,
                                           content = rewrite(entry.path, arc:extractToMemory(entry.path)) })
            end
        end
        arc:close()
        writeEpub(dest, members)
    end

    local function writePackage(dest, opf_path, opf)
        writeEpub(dest, {
            { path = "mimetype", content = "application/epub+zip" },
            { path = "META-INF/container.xml", content = [[<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
 <rootfiles><rootfile full-path="]] .. opf_path:gsub("&", "&amp;") .. [[" media-type="application/oebps-package+xml"/></rootfiles>
</container>]] },
            { path = opf_path, content = opf },
        })
    end

    describe("structureDigest()", function()
        it("should digest an EPUB", function()
            assert.are.equal("3d550f5e63e45c11087f7548bd4bc37c", KOSyncIdentifiers.structureDigest(leaves))
        end)

        it("should tell two books apart", function()
            assert.are_not.equal(KOSyncIdentifiers.structureDigest(leaves),
                                 KOSyncIdentifiers.structureDigest(juliet))
        end)

        it("should survive a repack that rewrites every image and chapter", function()
            local repacked = DataStorage:getDataDir() .. "/kosync-repacked.tests.epub"
            repack(leaves, repacked, function(path, content)
                if path:match("%.jpe?g$") or path:match("%.png$") then
                    return content .. "JPEG re-encoded by the optimizer"
                elseif path:match("%.x?html?$") then
                    return (content:gsub("<head>", '<head><link rel="stylesheet" href="optimized.css"/>', 1))
                end
                return content
            end)
            assert.are.equal(KOSyncIdentifiers.structureDigest(leaves),
                             KOSyncIdentifiers.structureDigest(repacked))
            os.remove(repacked)
        end)

        it("should notice a spine entry going away", function()
            local shortened = DataStorage:getDataDir() .. "/kosync-shortened.tests.epub"
            repack(leaves, shortened, function(path, content)
                if path == "content.opf" then
                    return (content:gsub("<itemref[^>]*/>", "", 1))
                end
                return content
            end)
            assert.are_not.equal(KOSyncIdentifiers.structureDigest(leaves),
                                 KOSyncIdentifiers.structureDigest(shortened))
            os.remove(shortened)
        end)

        it("should expand entity references in the href, the identifier and the rootfile path", function()
            local entities = DataStorage:getDataDir() .. "/kosync-entities.tests.epub"
            writePackage(entities, "a&b.opf", [[<?xml version="1.0"?>
<package xmlns:opf="http://www.idpf.org/2007/opf" unique-identifier="pid" version="3.0">
 <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:identifier id="pid">urn:uuid:a&amp;b&#45;&#x63;</dc:identifier>
 </metadata>
 <manifest>
  <item id="c1" href="a&amp;b/ch1.xhtml" media-type="application/xhtml+xml"/>
  <item id="c2" href="q&quot;&apos;&lt;&gt;.xhtml" media-type="application/xhtml+xml"/>
  <item id="c3" href="caf&#233;.xhtml#frag" media-type="application/xhtml+xml"/>
 </manifest>
 <spine>
  <itemref idref="c1"/>
  <itemref idref="c2"/>
  <itemref idref="c3"/>
 </spine>
</package>]])
            -- md5 of urn:uuid:a&b-c\na&b/ch1.xhtml\nq"'<>.xhtml\ncaf\u{00E9}.xhtml
            assert.are.equal("6feb75d3d45bfa712496e43b4335f26d", KOSyncIdentifiers.structureDigest(entities))
            os.remove(entities)
        end)

        it("should match elements on the local name", function()
            local plain = DataStorage:getDataDir() .. "/kosync-plain.tests.epub"
            writePackage(plain, "x.opf", [[<?xml version="1.0"?>
<package xmlns:opf="http://www.idpf.org/2007/opf" unique-identifier="pid" version="3.0">
 <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
  <identifier id="pid">local-name-match</identifier>
 </metadata>
 <manifest>
  <item id="a" href="a.xhtml"/>
 </manifest>
 <spine>
  <itemref idref="a"/>
 </spine>
</package>]])

            local prefixed = DataStorage:getDataDir() .. "/kosync-prefixed.tests.epub"
            writePackage(prefixed, "x.opf", [[<?xml version="1.0"?>
<opf:package xmlns:opf="http://www.idpf.org/2007/opf" unique-identifier="pid" version="3.0">
 <opf:metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:identifier id="pid">local-name-match</dc:identifier>
 </opf:metadata>
 <opf:manifest>
  <opf:item id="a" href="a.xhtml"/>
 </opf:manifest>
 <opf:spine>
  <opf:itemref idref="a"/>
 </opf:spine>
</opf:package>]])

            -- md5 of local-name-match\na.xhtml
            assert.are.equal("71b57c6f13f1912eadb56e0791799540", KOSyncIdentifiers.structureDigest(plain))
            assert.are.equal(KOSyncIdentifiers.structureDigest(plain), KOSyncIdentifiers.structureDigest(prefixed))
            os.remove(plain)
            os.remove(prefixed)
        end)

        it("should return nothing for a file that is not an EPUB", function()
            assert.is_nil(KOSyncIdentifiers.structureDigest("spec/front/unit/data/tall.pdf"))
            assert.is_nil(KOSyncIdentifiers.structureDigest("spec/front/unit/data/no-such-file.epub"))
            assert.is_nil(KOSyncIdentifiers.structureDigest(nil))
        end)
    end)

    describe("build()", function()
        local parts = {
            content = "1234567890abcdef1234567890abcdef",
            filename = "fedcba0987654321fedcba0987654321",
            file = leaves,
        }

        it("should order strongest first whichever digest addresses the document", function()
            local order = { "content", "structure", "filename" }

            local list = KOSyncIdentifiers.build(parts.content, parts)
            assert.are.same(order, { list[1].type, list[2].type, list[3].type })

            -- Matching by filename does not demote the rest: the server takes
            -- position as preference, and only requires the document among them.
            list = KOSyncIdentifiers.build(parts.filename, parts)
            assert.are.same(order, { list[1].type, list[2].type, list[3].type })
            assert.are.equal(parts.filename, list[3].value)
        end)

        it("should skip identifiers it cannot derive", function()
            local list = KOSyncIdentifiers.build(parts.content, { content = parts.content })
            assert.are.equal(1, #list)
            assert.are.equal("content", list[1].type)
        end)

        it("should return nothing when no identifier is the document", function()
            assert.is_nil(KOSyncIdentifiers.build("0000000000000000000000000000abcd", parts))
            assert.is_nil(KOSyncIdentifiers.build(nil, parts))
        end)
    end)

    describe("query()", function()
        it("should flatten a list", function()
            assert.are.equal("content:C1,structure:S1",
                             KOSyncIdentifiers.query({ { type = "content", value = "C1" },
                                                       { type = "structure", value = "S1" } }))
            assert.is_nil(KOSyncIdentifiers.query(nil))
        end)
    end)

    describe("canFollowProgress()", function()
        it("should follow a position written against this file's structure", function()
            assert.is_true(KOSyncIdentifiers.canFollowProgress("content"))
            assert.is_true(KOSyncIdentifiers.canFollowProgress("structure"))
        end)

        it("should not follow a position written against a related copy", function()
            assert.is_false(KOSyncIdentifiers.canFollowProgress("metadata"))
            assert.is_false(KOSyncIdentifiers.canFollowProgress("filename"))
            assert.is_false(KOSyncIdentifiers.canFollowProgress("none"))
        end)

        it("should follow a position from a server that does not match identifiers", function()
            assert.is_true(KOSyncIdentifiers.canFollowProgress(nil))
        end)
    end)
end)
