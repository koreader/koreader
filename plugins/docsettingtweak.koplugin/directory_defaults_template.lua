return {--do NOT change this line

 --HELP:
 -- You can override default settings for documents per directory in this file.
 -- The directories must be under the home folder.
 -- You can find settings to change in the metadata.lua in the .sdr folder.
 -- The path must start with "/" (absolute path).
 -- The path must not end with a "/" it must end with the folder name.

 -- syntax:

 --   ["path/to/folder"] = {
 --         ["setting_to_override"] = value,
 --    },

 -- examples:

 --[[
    ["/mnt/us/documents/hebrew"] = {
        ["inverse_reading_order"] = true
    },
    ["/mnt/onboard/smalltext"] = {
        ["copt_font_size"] = 34,
        ["copt_line_spacing"] = 130,
    },
    ["/sdcard/Books/smalltext"] = {
        ["copt_font_size"] = 34,
        ["copt_line_spacing"] = 130,
    },
--]]

 -- comment out line ("--" at line start) to disable


 -- ADD YOUR DEFAULTS HERE:


}--do NOT change this line
