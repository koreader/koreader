describe("Version module", function()
    local Version
    setup(function()
        require("commonrequire")
        Version = require("version")
    end)
    it("should get current revision", function()
        local rev = Version:getCurrentRevision()
        local year, month, point, revision = rev:match("v(%d%d%d%d)%.(%d%d)%.?(%d?)-?(%d*)") -- luacheck: ignore 211
        local commit = rev:match("-%d*-g(%x*)[%d_%-]*") -- luacheck: ignore 211
        assert.is_truthy(year)
        assert.is_truthy(month)
        assert.is_true(4 == year:len())
        assert.is_true(2 == month:len())
    end)
    describe("normalized", function()
        it("should get current version", function()
            assert.is_true(12 == tostring(Version:getNormalizedCurrentVersion()):len())
        end)
        it("should get version with 7-character hash", function()
            local rev = "v2015.11-982-g704d4238"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201511000982
            local expected_commit = "704d4238"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get version with 8-character hash", function()
            local rev = "v2021.05-70-gae544b74"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 202105000070
            local expected_commit = "ae544b74"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get version with four number revision", function()
            local rev = "v2015.11-1755-gecd7b5b_2018-07-02"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201511001755
            local expected_commit = "ecd7b5b"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get stable version", function()
            local rev = "v2018.11"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201811000000
            local expected_commit = nil
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get stable point release version", function()
            local rev = "v2018.11.1"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201811010000
            local expected_commit = nil
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
        it("should get point release nightly version", function()
            local rev = "v2018.11.1-1755-gecd7b5b_2018-07-02"
            local version, commit = Version:getNormalizedVersion(rev)
            local expected_version = 201811011755
            local expected_commit = "ecd7b5b"
            assert.are.same(expected_version, version)
            assert.are.same(expected_commit, commit)
        end)
    end)
    it("should fail gracefully", function()
        local version, commit = Version:getNormalizedVersion()
        local expected_version = nil
        local expected_commit = nil
        assert.are.same(expected_version, version)
        assert.are.same(expected_commit, commit)
    end)
end)
