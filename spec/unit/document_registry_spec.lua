describe("document registry module", function()
    local DocSettings, DocumentRegistry

    setup(function()
        require("commonrequire")
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
    end)

    it("should get preferred rendering engine", function()
        assert.is_equal("crengine",
                        DocumentRegistry:getProvider("bla.epub").provider)
        assert.is_equal("mupdf",
                        DocumentRegistry:getProvider("bla.pdf").provider)
    end)

    it("should return all supported rendering engines", function()
        local providers = DocumentRegistry:getProviders("bla.epub")
        assert.is_equal("crengine",
                        providers[1].provider.provider)
        assert.is_equal("mupdf",
                        providers[2].provider.provider)
    end)

    it("should set per-document setting for rendering engine", function()
        local path = "../../foo.epub"
        local pdf_provider = DocumentRegistry:getProvider("bla.pdf")
        DocumentRegistry:setProvider(path, pdf_provider, false)

        local provider = DocumentRegistry:getProvider(path)

        assert.is_equal("mupdf", provider.provider)

        local docsettings = DocSettings:open(path)
        docsettings:purge()
    end)
    it("should set global setting for rendering engine", function()
        local path = "../../foo.fb2"
        local pdf_provider = DocumentRegistry:getProvider("bla.pdf")
        DocumentRegistry:setProvider(path, pdf_provider, true)

        local provider = DocumentRegistry:getProvider(path)

        assert.is_equal("mupdf", provider.provider)

        G_reader_settings:delSetting("provider")
    end)

    it("should return per-document setting for rendering engine", function()
        local path = "../../foofoo.epub"
        local docsettings = DocSettings:open(path)
        docsettings:saveSetting("provider", "mupdf")
        docsettings:flush()

        local provider = DocumentRegistry:getProvider(path)

        assert.is_equal("mupdf", provider.provider)

        docsettings:purge()
    end)
    it("should return global setting for rendering engine", function()
        local path = "../../foofoo.fb2"
        local provider_setting = {}
        provider_setting.fb2 = "mupdf"
        G_reader_settings:saveSetting("provider", provider_setting)

        local provider = DocumentRegistry:getProvider(path)

        assert.is_equal("mupdf", provider.provider)

        G_reader_settings:delSetting("provider")
    end)
end)
