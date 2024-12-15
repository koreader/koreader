local dutch_wikipedia_text = "Wikipedia is een meertalige encyclopedie, waarvan de inhoud vrij beschikbaar is. Iedereen kan hier kennis toevoegen!"
local chinese_wikipedia_text = "維基百科是维基媒体基金会运营的一个多语言的線上百科全書，并以创建和维护作为开放式协同合作项目，特点是自由內容、自由编辑、自由版权。"
local Translator

describe("Translator module", function()
    setup(function()
        require("commonrequire")
        Translator = require("ui/translator")
    end)

    local function getRomanizations(translation_result)
        local translations = translation_result[1]
        local romanizations = {}
        for _, translation in ipairs(translations) do
           if type(translation[4]) == "string" then
              table.insert(romanizations, translation[4])
           end
        end
        return romanizations
    end

    it("should return server", function()
        assert.is.same("https://translate.googleapis.com/", Translator:getTransServer())
        G_reader_settings:saveSetting("trans_server", "http://translate.google.nl")
        G_reader_settings:flush()
        assert.is.same("http://translate.google.nl", Translator:getTransServer())
        G_reader_settings:delSetting("trans_server")
        G_reader_settings:flush()
    end)
    -- add " #notest" to the it("description string") when it does not work anymore
    it("should return translation #internet", function()
        local translation_result = Translator:translate(dutch_wikipedia_text, "en")
        assert.is.truthy(translation_result)
        -- while some minor variation in the translation is possible it should
        -- be between about 100 and 130 characters
        assert.is_true(#translation_result > 50 and #translation_result < 200)
    end)
    it("should include romanization results when configured to be shown #internet", function()
        G_reader_settings:saveSetting("translator_with_romanizations", true)
        local translation_result = Translator:loadPage(chinese_wikipedia_text, "en", "auto")
        local romanizations = getRomanizations(translation_result)
        assert.is.same(1, #romanizations)
        -- The word free (zìyóu) appears 3 times in the romanization
        local free_index = string.find(romanizations[1], "zìyóu")
        assert.is.truthy(free_index)
        free_index = string.find(romanizations[1], "zìyóu", free_index + 1)
        assert.is.truthy(free_index)
        free_index = string.find(romanizations[1], "zìyóu", free_index + 1)
        assert.is.truthy(free_index)
    end)
    it("should not include romanization results when not configured to be shown #internet", function()
        G_reader_settings:saveSetting("translator_with_romanizations", false)
        assert.is_false(G_reader_settings:isTrue("translator_with_romanizations"))
        local translation_result = Translator:loadPage(chinese_wikipedia_text, "en", "auto")
        local romanizations = getRomanizations(translation_result)
        assert.is.same(0, #romanizations)
    end)
    it("should autodetect language #internet", function()
        local detect_result = Translator:detect(dutch_wikipedia_text)
        assert.is.same("nl", detect_result)
    end)
end)
