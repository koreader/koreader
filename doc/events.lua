-- You can call me with something like `ldoc --filter events.filter .`

local function output_table(events_and_handlers, name_len, module_len)
    local empty_table_line = "<tr><td bgcolor=\"#FFFFFF\" style=\"line-height:0.8;\" colspan=3>&nbsp;</td></tr>\n"

    local function make_modules_link(link, text)
        text = text or link
        return "<a href=\"../modules/"..link..".html\">" .. text .. "</a>"
    end

    local function make_source_link(path, lineno)
        -- Turn the symbolic link from `/frontend/plugins` to `/plugins/`.
        path = path:gsub("/frontend/plugins/","/plugins/")
        local text = path:gsub("^.*koreader/", "")
        local link = path:gsub("^.*koreader", "https://github.com/koreader/koreader/tree/master/") .. "#L" .. lineno
        return "<a href=\""..link.."\">" .. text .. "</a>"
    end

    io.write("<br><br>\n")
    io.write("<table style=\"width:1024px\">\n")

    -- Write header line.
    io.write("<thead>\n")
    io.write("<tr>")
    io.write("<th><b>Event/Handler"    .. string.rep(" ", name_len   - #"Event/Handler") .. "</b></th>")
    io.write("<th><b>" .."Module Name" .. string.rep(" ", module_len - #"Module Name") ..   "</b></th>")
    io.write("<th><b> Line# </b></th>")
    io.write("<th><b> File </b></th>")
    io.write("</tr>\n")
    io.write("</thead>\n")

    -- Write table body.
    io.write("<tbody>\n")
    io.write(empty_table_line)
    local event_plus_handler_nb = 0
    -- Write events and handlers.
    for _,v in pairs(events_and_handlers) do
        local name = v.name
        if name then
            if name:sub(1, 2) ~= "on" and name:sub(1, 3) ~= "_on" then
                name = "&nbsp;&nbsp;&nbsp;" .. name
            elseif name:sub(1, 2) == "on" then
                name = "&nbsp;" .. name
            end
            name = name:gsub("[_]+_key_event", "&nbsp;&nbsp; (key_event)")
            name = name:gsub("[_]+_ges_event", "&nbsp;&nbsp; (gesture_event)")
            io.write("<tr>")
            io.write("<td><code>" .. name .. string.rep(" ", name_len - #name) .. "&nbsp;</code></td>")
            io.write("<td>" .. make_modules_link(v.module_name) .. "&nbsp;</td>")
            io.write("<td align =\"right\">" .. string.format("%5d", v.lineno) .. "&nbsp;</td>")
            io.write("<td>" .. make_source_link(v.module_file, v.lineno) .. "</td>")
            io.write("</tr>\n")

            event_plus_handler_nb = event_plus_handler_nb + 1
        else
            io.write(empty_table_line)
        end
    end
    io.write("</tr></tbody>\n")
    io.write("</table>\n")
    return event_plus_handler_nb
end

-- We process all ldoc tags and look for `event` and `eventHandler`.
return {
    filter = function (t)
        local nb_events = 0
        local nb_handlers = 0
        local events_and_handlers = {} -- table to store events and handlers
        for _, mod in ipairs(t) do
            for _, item in ipairs(mod.items) do
                if item.type == "event" then
                    nb_events = nb_events + 1
                    table.insert(events_and_handlers, {
                        name = item.name,
                        module_name = mod.name,
                        module_file = mod.file,
                        lineno = item.lineno,
                        })
                elseif item.type == "eventHandler" then
                    nb_handlers = nb_handlers + 1
                    table.insert(events_and_handlers, {
                        name = item.name,
                        module_name = mod.name,
                        module_file = mod.file,
                        lineno = item.lineno,
                        })
                end
            end
        end

        local function drop_key_and_ges_event(text)
            local i
            i = text:find("[_]+_key_event")
            if i and i > 1 then
                text = text:sub(1, i-1)
            end
            i = text:find("[_]+_ges_event")
            if i and i > 1 then
                text = text:sub(1, i-1)
            end
            return text
        end

        local function get_base_name(name)
            if name:sub(1, 2) == "on" then
                name = name:sub(3)
            elseif name:sub(1, 3) == "_on" then
                name = name:sub(4)
            else
                name = name
            end
            name = drop_key_and_ges_event(name)
            return name
        end

        local function sort_events_and_handlers(a, b)
            local a_name = get_base_name(a.name)
            local b_name = get_base_name(b.name)

            if a_name < b_name then
                return true
            elseif a_name > b_name then
                return false
            elseif a_name == b_name then
                local is_a_handler = a.name:sub(1, 2) == "on" or a.name:sub(1, 3) == "_on"
                local is_b_handler = b.name:sub(1, 2) == "on" or b.name:sub(1, 3) == "_on"
                if not is_a_handler and is_b_handler then
                    return true
                elseif is_a_handler and not is_b_handler then
                    return false
                elseif a_name == b_name then
                    return a.module_name < b.module_name
                else
                    return a_name < b_name
                end
            end
        end

        table.sort(events_and_handlers, sort_events_and_handlers)

        local name_len=15
        local module_len=20

        for _,v in pairs(events_and_handlers) do
            if v.name and #v.name > name_len then
                name_len = #v.name
            end
            if v.module_name and #v.module_name > module_len then
                module_len = #v.module_name
            end
        end

        local events_and_handler_file = io.open("./generated/Events_and_handler.md", "w")
        if not events_and_handler_file then
            print("ERROR: cannot open /generated/Events_and_handler.md")
            return
        end

        -- Output title and info-line
        io.output(events_and_handler_file)
        io.write("# Events and Handlers\n")
        io.write("\n")
        io.write(string.format("Found %d events and %d handlers.\n", nb_events, nb_handlers))

        -- Write the table.
        output_table(events_and_handlers, name_len, module_len)

        -- Close the file.
        io.close(events_and_handler_file)
    end
}
