local logger = require("logger")
local userpatch = require("userpatch")

logger.info("Applying vocabulary builder button removal patch")

userpatch.registerPatchPluginFunc("vocabulary_builder", function(VocabBuilder)
    function VocabBuilder:onDictButtonsReady(dict_popup, buttons)
        return
    end
    logger.info("VocabBuilder onDictButtonsReady patched to remove button")
end)

logger.info("Vocabulary builder button removal patch registered")
