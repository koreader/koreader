local CreOptions = require("ui/data/creoptions")
local logger = require("logger")

OptionsCatalog = {}

function OptionsCatalog:generateOptionText()
    self.option_text_table = {}
    for i=1,#CreOptions do
        for y=1,#CreOptions[i].options do
            local option = CreOptions[i].options[y]
            if option.event then
                print("xxxxxxxxxxxxxxxxx " .. option.event)
                if option.toggle then
                    self.option_text_table[option.event] = option.toggle
                elseif option.labels then
                    self.option_text_table[option.event] = option.labels
                end
            end
        end
    end
end

function OptionsCatalog:getOptionText(event, val)
    if not self.option_text_table then
        self:generateOptionText()
    end
    if not event or not val then
        logger.err("[Notification:getOptionText] Either event or val not set. This should not happen!")
        return ""
    end
    if not self.option_text_table[event] then
        logger.err("[Notification:getOptionText] Event:" .. event .. " not found in option_text_table")
        return ""
    end
    local text = self.option_text_table[event][val]
    if not text then
        logger.err("[Notification:getOptionText] Option #" .. val .. " for event:" .. event .." not set in option_text_table")
    end
    return text
end

return OptionsCatalog
