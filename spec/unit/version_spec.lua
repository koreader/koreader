describe("Version module", function()
    local Version
    setup(function()
        require("commonrequire")
        Version = require("version")
    end)
    it("should get current revision", function()
        assert.is_true(22 >= (Version:getCurrentRevision()):len())
    end)
    it("should get normalized current version", function()
        assert.is_true(9 >= tostring(Version:getNormalizedCurrentVersion()):len())
    end)
    it("should get normalized version", function()
        local rev = "v2015.11-982-g704d4238"
        local version, commit = Version:getNormalizedVersion(rev)
        local expected_version = 201511982
        local expected_commit = "704d4238"
        assert.are.same(expected_version, version)
        assert.are.same(expected_commit, commit)
    end)
    it("should fail gracefully", function()
        local version, commit = Version:getNormalizedVersion()
        local expected_version = nil
        local expected_commit = nil
        assert.are.same(expected_version, version)
        assert.are.same(expected_commit, commit)
    end)
end)
