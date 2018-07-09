describe("Version module", function()
    local Version
    setup(function()
        require("commonrequire")
        Version = require("version")
    end)
    it("should get current revision", function()
        local rev = Version:getCurrentRevision()
        local year, month, revision = rev:match("v(%d%d%d%d)%.(%d%d)-?(%d*)")
        local commit = rev:match("-%d*-g(%x*)[%d_%-]*")
        assert.is_truthy(year)
        assert.is_truthy(month)
        assert.is_truthy(revision)
        assert.is_truthy(commit)
        assert.is_true(4 == year:len())
        assert.is_true(2 == month:len())
        assert.is_true(1 <= revision:len())
        assert.is_true(7 <= commit:len())
    end)
    it("should get normalized current version", function()
        assert.is_true(10 == tostring(Version:getNormalizedCurrentVersion()):len())
    end)
    it("should get normalized version", function()
        local rev = "v2015.11-982-g704d4238"
        local version, commit = Version:getNormalizedVersion(rev)
        local expected_version = 2015110982
        local expected_commit = "704d4238"
        assert.are.same(expected_version, version)
        assert.are.same(expected_commit, commit)
    end)
    it("should also get normalized version", function()
        local rev = "v2015.11-1755-gecd7b5b_2018-07-02"
        local version, commit = Version:getNormalizedVersion(rev)
        local expected_version = 2015111755
        local expected_commit = "ecd7b5b"
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
