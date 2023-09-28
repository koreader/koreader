local dutch_wikipedia_text = "Wikipedia is een meertalige encyclopedie, waarvan de inhoud vrij beschikbaar is. Iedereen kan hier kennis toevoegen!"
local Translator

describe("Translator module", function()
    setup(function()
        require("commonrequire")
        Translator = require("ui/translator")
    end)
    it("should return server", function()
        assert.is.same("https://translate.googleapis.com/", Translator:getTransServer())
        G_reader_settings:saveSetting("trans_server", "http://translate.google.nl")
        G_reader_settings:flush()
        assert.is.same("http://translate.google.nl", Translator:getTransServer())
        G_reader_settings:delSetting("trans_server")
        G_reader_settings:flush()
    end)
    -- add " #notest #nocov" to the it("description string") when it does not work anymore
    it("should return translation #internet", function()
        local translation_result = Translator:translate(dutch_wikipedia_text, "en")
        assert.is.truthy(translation_result)
        -- while some minor variation in the translation is possible it should
        -- be between about 100 and 130 characters
        assert.is_true(#translation_result > 50 and #translation_result < 200)
    end)
    it("should autodetect language #internet", function()
        local detect_result = Translator:detect(dutch_wikipedia_text)
        assert.is.same("nl", detect_result)
    end)
end)
