describe("KOSyncIdentifiers module", function()
    local KOSyncIdentifiers

    setup(function()
        require("commonrequire")
        package.path = "plugins/kosync.koplugin/?.lua;" .. package.path
        KOSyncIdentifiers = require("KOSyncIdentifiers")
    end)

    describe("structureDigest()", function()
        it("should digest a zip container", function()
            local digest = KOSyncIdentifiers.structureDigest("spec/front/unit/data/leaves.epub")
            assert.is_truthy(digest:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$"))
            assert.are.equal(digest, KOSyncIdentifiers.structureDigest("spec/front/unit/data/leaves.epub"))
        end)

        it("should tell two containers apart", function()
            assert.are_not.equal(KOSyncIdentifiers.structureDigest("spec/front/unit/data/leaves.epub"),
                                 KOSyncIdentifiers.structureDigest("spec/front/unit/data/juliet.epub"))
        end)

        it("should return nothing for a file that is not a zip", function()
            assert.is_nil(KOSyncIdentifiers.structureDigest("spec/front/unit/data/tall.pdf"))
            assert.is_nil(KOSyncIdentifiers.structureDigest("spec/front/unit/data/no-such-file.epub"))
            assert.is_nil(KOSyncIdentifiers.structureDigest(nil))
        end)
    end)

    describe("metadataDigest()", function()
        local props = { title = "The Dispossessed", authors = "Ursula K. Le Guin" }

        it("should ignore case, padding and author order", function()
            assert.are.equal(KOSyncIdentifiers.metadataDigest(props),
                             KOSyncIdentifiers.metadataDigest({ title = "  the   dispossessed ",
                                                                authors = "ursula k. le guin" }))
            assert.are.equal(KOSyncIdentifiers.metadataDigest({ title = "Good Omens",
                                                                authors = "Neil Gaiman\nTerry Pratchett" }),
                             KOSyncIdentifiers.metadataDigest({ title = "Good Omens",
                                                                authors = "Terry Pratchett\nNeil Gaiman" }))
        end)

        it("should tell two works apart", function()
            assert.are_not.equal(KOSyncIdentifiers.metadataDigest(props),
                                 KOSyncIdentifiers.metadataDigest({ title = "The Dispossessed",
                                                                    authors = "Someone Else" }))
        end)

        it("should require both a title and an author", function()
            assert.is_nil(KOSyncIdentifiers.metadataDigest({ title = "The Dispossessed" }))
            assert.is_nil(KOSyncIdentifiers.metadataDigest({ authors = "Ursula K. Le Guin" }))
            assert.is_nil(KOSyncIdentifiers.metadataDigest({ title = "  ", authors = "  " }))
            assert.is_nil(KOSyncIdentifiers.metadataDigest(nil))
        end)
    end)

    describe("build()", function()
        local parts = {
            content = "1234567890abcdef1234567890abcdef",
            filename = "fedcba0987654321fedcba0987654321",
            file = "spec/front/unit/data/leaves.epub",
            props = { title = "The Dispossessed", authors = "Ursula K. Le Guin" },
        }

        it("should order strongest first whichever digest addresses the document", function()
            local order = { "content", "structure", "metadata", "filename" }

            local list = KOSyncIdentifiers.build(parts.content, parts)
            assert.are.same(order, { list[1].type, list[2].type, list[3].type, list[4].type })

            -- Matching by filename does not demote the rest: the server takes
            -- position as preference, and only requires the document among them.
            list = KOSyncIdentifiers.build(parts.filename, parts)
            assert.are.same(order, { list[1].type, list[2].type, list[3].type, list[4].type })
            assert.are.equal(parts.filename, list[4].value)
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
