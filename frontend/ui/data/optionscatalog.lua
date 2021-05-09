local CreOptions = require("ui/data/creoptions")
local logger = require("logger")

local OptionsCatalog = {}

function OptionsCatalog:generateOptionText()
    self.option_text_table = {}
    self.option_args_table = {}
    for i=1,#CreOptions do
        for y=1,#CreOptions[i].options do
            local option = CreOptions[i].options[y]
            if option.event then
                if option.toggle then
                    self.option_text_table[option.event] = option.toggle
                elseif option.labels then
                    self.option_text_table[option.event] = option.labels
                end
                self.option_args_table[option.event] = option.args
            end
        end
    end
end

function OptionsCatalog:getOptionText(event, val)
    if not self.option_text_table then
        self:generateOptionText()
    end
    if not event or val == nil then
        logger.err("[OptionsCatalog:getOptionText] Either event or val not set. This should not happen!")
        return ""
    end
    if not self.option_text_table[event] then
        logger.err("[OptionsCatalog:getOptionText] Event:" .. event .. " not found in option_text_table")
        return ""
    end

    local text
    if type(val) == "boolean" then
        text = self.option_text_table[event][val and 2 or 1]
    elseif type(val) == "number" then
        text = self.option_text_table[event][val + 1] -- options count from zero
    end

    -- if there are args, try to find the adequate toggle
    if self.option_args_table[event] then
        for i, args in pairs(self.option_args_table[event]) do
            if args == val then
                text = self.option_text_table[event][i]
            end
        end
    end

    if not text then
        logger.err("[Notification:getOptionText] Option #" .. val .. " for event:" .. event .." not set in option_text_table")
    end
    return text
end

return OptionsCatalog
