--[[--
This module shows HTML code and CSS content from crengine documents.
It it used by ReaderHighlight as an action after text selection.
--]]

local BD = require("ui/bidi")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local ViewHtml = {
    VIEWS = {
        -- For available flags, see the "#define WRITENODEEX_*" in crengine/src/lvtinydom.cpp.
        -- Start with valid and classic displayed HTML (with only block nodes indented),
        -- including styles found in <HEAD>, linked CSS files content, and misc info.
        { _("Switch to standard view"), 0xE830, false },

        -- Each node on a line, with markers and numbers of skipped chars and siblings shown,
        -- with possibly invalid HTML (text nodes not escaped)
        { _("Switch to debug view"), 0xEB5A, true },

        -- Additionally show rendering methods of each node
        { _("Switch to rendering debug view"), 0xEF5A, true },

        -- Or additionally show unicode codepoint of each char
        { _("Switch to unicode debug view"), 0xEB5E, true },
    },
}

-- Main entry point
function ViewHtml:viewSelectionHTML(document, selected_text)
    if not selected_text or not selected_text.pos0 or not selected_text.pos1 then
        return
    end
    self:_viewSelectionHTML(document, selected_text, 1, true, false)
end

function ViewHtml:_viewSelectionHTML(document, selected_text, view, with_css_files_buttons, hide_stylesheet_elem_content)
    local next_view = view < #self.VIEWS and view + 1 or 1
    local next_view_text = self.VIEWS[next_view][1]

    local html_flags = self.VIEWS[view][2]
    local massage_html = self.VIEWS[view][3]

    local html, css_files, css_selectors_offsets = document:getHTMLFromXPointers(selected_text.pos0,
                                                        selected_text.pos1, html_flags, true)
    if not html then
        UIManager:show(InfoMessage:new{
            text = _("Failed getting HTML for selection"),
        })
        return
    end

    -- Our substitutions may mess with the offsets in css_selectors_offsets: we need to keep
    -- track of shifts induced by these substitutions to correct the offsets
    local offset_shifts = {}
    local replace_in_html = function(pat, repl)
        local new_html = ""
        local is_match = false -- given the html we get and our patterns, we know the first part won't be a match
        for part in util.gsplit(html, pat, true, true) do
            if is_match then
                local r = type(repl) == "function" and repl(part) or repl
                local offset_shift = #r - #part
                if offset_shift ~= 0 then
                    table.insert(offset_shifts, {#new_html + #part + 1, offset_shift})
                end
                new_html = new_html .. r
            else
                -- (we provided capture_empty_entity=true, to match adjacent 'pat',
                -- so here we may get empty 'part', that we can just concatenate)
                new_html = new_html .. part
            end
            is_match = not is_match
        end
        html = new_html
    end
    if massage_html then
        -- Make some invisible chars visible
        replace_in_html("\u{00A0}", "\u{2423}") -- no break space: open box
        replace_in_html("\u{00AD}", "\u{22C5}") -- soft hyphen: dot operator (smaller than middle dot ·)
        -- Prettify inlined CSS (from <HEAD>, put in an internal
        -- <body><stylesheet> element by crengine (the opening tag may
        -- include some href=, or end with " ~X>" with some html_flags)
        -- (We do that in debug views only: as this may increase the
        -- height of this section, we don't want to have to scroll many
        -- pages to get to the HTML content on the initial view.)
    end
    if massage_html or hide_stylesheet_elem_content then
        replace_in_html("<stylesheet[^>]*>.-</stylesheet>", function(s)
            local pre, css_text, post = s:match("(<stylesheet[^>]*>)%s*(.-)%s*(</stylesheet>)")
            if hide_stylesheet_elem_content then
                return pre .. "[...]" .. post
            end
            return pre .. "\n" .. util.prettifyCSS(css_text) .. post
        end)
    end
    -- Make sure we won't get wrapped just after our indentation if there is no break opportunity later
    replace_in_html("\n *", function(s)
        return "\n" .. ("\u{00A0}"):rep(#s - 1)
    end)

    local textviewer
    -- Prepare bottom buttons and their actions
    local buttons_hold_callback = function()
        -- Allow hiding css files buttons if there are too many
        -- and the available height for text is too short
        UIManager:close(textviewer)
        self:_viewSelectionHTML(document, selected_text, view, not with_css_files_buttons, hide_stylesheet_elem_content)
    end
    local buttons_table = {}
    if css_files and with_css_files_buttons then
        for i=1, #css_files do
            local button = {
                text = T(_("View %1"), BD.filepath(css_files[i])),
                callback = function()
                    local css_text = document:getDocumentFileContent(css_files[i])
                    local cssviewer
                    cssviewer = TextViewer:new{
                        title = css_files[i],
                        text = css_text or _("Failed getting CSS content"),
                        text_type = "code",
                        para_direction_rtl = false,
                        auto_para_direction = false,
                        add_default_buttons = true,
                        buttons_table = {
                            {{
                                text = _("Prettify"),
                                enabled = css_text and true or false,
                                callback = function()
                                    UIManager:close(cssviewer)
                                    UIManager:show(TextViewer:new{
                                        title = css_files[i],
                                        text = util.prettifyCSS(css_text),
                                        text_type = "code",
                                        para_direction_rtl = false,
                                        auto_para_direction = false,
                                    })
                                end,
                            }},
                        }
                    }
                    UIManager:show(cssviewer)
                end,
                hold_callback = buttons_hold_callback,
            }
            -- One button per row, to make room for the possibly long css filename
            table.insert(buttons_table, {button})
        end
    end
    table.insert(buttons_table, {{
        text = next_view_text,
        callback = function()
            UIManager:close(textviewer)
            self:_viewSelectionHTML(document, selected_text, next_view, with_css_files_buttons, hide_stylesheet_elem_content)
        end,
        hold_callback = buttons_hold_callback,
    }})

    -- Long-press in the HTML will present a list of CSS selectors related to the element
    -- we pressed on, to be copied to clipboard
    local text_selection_callback = function(text, hold_duration, start_idx, end_idx, to_source_index_func)
        if not css_selectors_offsets or css_selectors_offsets == "" then -- no flag provided
            Device.input.setClipboardText(text)
            UIManager:show(Notification:new{
                text = _("Selection copied to clipboard.")
            })
            return
        end
        -- We only work with one index (let's choose start_idx), and we want the offset in the utf8 stream
        local idx = to_source_index_func(start_idx)
        self:_handleLongPress(document, css_selectors_offsets, offset_shifts, idx, function()
            UIManager:close(textviewer)
            self:_viewSelectionHTML(document, selected_text, view, with_css_files_buttons, not hide_stylesheet_elem_content)
        end)
    end

    textviewer = TextViewer:new{
        title = _("Selection HTML"),
        text = html,
        text_type = "code",
        para_direction_rtl = false,
        auto_para_direction = false,
        add_default_buttons = true,
        default_hold_callback = buttons_hold_callback,
        buttons_table = buttons_table,
        text_selection_callback = text_selection_callback,
    }
    UIManager:show(textviewer)
end

function ViewHtml:_handleLongPress(document, css_selectors_offsets, offset_shifts, idx, stylesheet_elem_callback)

    -- We want to propose for "copy into clipboard" a few interesting selectors related to the element
    -- the user long-pressed on, which can then be pasted in "Find" when viewing a stylesheet, or
    -- pasted in "Book style tweaks" when willing to tweak the style for this element.
    local proposed_selectors = {}
    local seen_kind = {} -- only one selector of some kind proposed, to not have too many
    local ancestors_classnames_selector = "" -- we will have a final one selecting the whole ancestors

    -- Ignore some crengine internal attributes:
    local ignore_attrs = { "StyleSheet" }
    -- Some attributes have too variable values, that are not interesting when used as selectors:
    local skip_value_attrs = { "href", "id", "style", "title", }

    -- We will also show 2 buttons to show the individual CSS rulesets (selector + declaration)
    -- that would match this elements, and this element and its ancestor.
    local ancestors = {}

    -- We get as css_selectors_offsets from crengine such content:
    -- (Format: Offset in 'html', node level, node dataIndex, element name, class and attribute selectors
    -- 0       2    33     body
    -- 9       3    449    DocFragment        [StyleSheet=stylesheet.css]     [id=_doc_fragment_52]   [lang=fr-FR]
    -- 90      4    465    stylesheet [href=OPS/]
    -- 163     4
    -- 168     4    481    body       [type=bodymatter]       [lang=fr-FR]    [lang=fr-FR]    .calibre1
    -- 251     5    545    section    .chap   [type=chapter]  [role=doc-chapter]
    -- 321     6    561    div
    -- 349     7    577    p  .justif1   .no-indent   [type=main]
    -- 395     7
    -- 406     7    593    p  .justif1
    -- 457     7
    -- 472     6
    -- 489     5
    -- 501     4
    -- 518     3
    -- 526     2
    local offsets = {}
    for line in css_selectors_offsets:gmatch("[^\n]+") do
        local t = util.splitToArray(line, "\t")
        table.insert(offsets, t)
    end
    -- Iterate from end until we find a smaller offset (this is the element we are in)
    -- and from then on, only deal with elements with a smaller level (the parents)
    local cur_level = math.huge
    local stop_gathering_selectors = false
    for i=#offsets, 1, -1 do
        local info = offsets[i]
        local offset, level = tonumber(info[1]), tonumber(info[2])
        -- Correct offsets with the shifts caused by our substitutions
        for _, offset_shift in ipairs(offset_shifts) do
            if offset >= offset_shift[1] then
                offset = offset + offset_shift[2]
            end
        end
        if offset <= idx and level < cur_level then -- meeting element or new parent
            cur_level = level
            if #info > 2 then -- this is an element (and not a level we leave)
                local elem = info[4]
                table.insert(ancestors, { elem, info[3] })
                if elem == "body" and #proposed_selectors > 0 then
                    -- Stop and don't include body (unless long-press on <body> itself)
                    stop_gathering_selectors = true
                end
                if not stop_gathering_selectors then
                    if not seen_kind.element then
                        -- Propose as selector the selected element tag name, ie. "p".
                        if elem == "stylesheet" then -- long-press on <stylesheet>
                            stylesheet_elem_callback()
                            return
                        end
                        table.insert(proposed_selectors, elem)
                    end
                    local all_classnames = ""
                    local all_attrs = ""
                    for j=5, #info do
                        local sel = info[j]
                        if sel:sub(1,1) == "." then
                            if not seen_kind.individual_classname then
                                -- Propose as selectors each of the classnames of the selected element
                                -- (or its neareast parent with a class), ie. ".justif1" , ".no-indent".
                                table.insert(proposed_selectors, sel)
                            end
                            all_classnames = all_classnames .. sel
                        else
                            local attrname = sel:match("^%[(.-)=") or ""
                            if elem == "DocFragment" then
                                if attrname == "id" then -- keep id= full, it can be useful with DocFragment
                                    all_attrs = all_attrs .. sel
                                end
                            elseif util.arrayContains(ignore_attrs, attrname) then
                                do end -- luacheck: ignore 541
                            elseif util.arrayContains(skip_value_attrs, attrname) then
                                all_attrs = all_attrs .. "[" .. attrname .. "]"
                            else
                                all_attrs = all_attrs .. sel
                            end
                        end
                    end
                    if all_classnames ~= "" and not seen_kind.all_classnames then
                        -- Propose as selector the selected element (or its neareast parent with a class)
                        -- with all its classnames concatenated, ie. "p.justif1.no-indent".
                        table.insert(proposed_selectors, elem .. all_classnames)
                        seen_kind.all_classnames = true
                        seen_kind.individual_classname = true
                    end
                    if all_attrs ~= "" and not seen_kind.element then
                        -- Propose as selector the selected element with all its attributes (and classnames),
                        -- ie. "p.justif1.no-indent[type=main]".
                        table.insert(proposed_selectors, elem .. all_classnames .. all_attrs)
                    end
                    -- Accumulate into the full ancestor element & classname selector
                    if ancestors_classnames_selector ~= "" then
                        ancestors_classnames_selector = " > " .. ancestors_classnames_selector
                    end
                    ancestors_classnames_selector = elem .. all_classnames .. ancestors_classnames_selector
                    seen_kind.element = true -- done with selectors targeting the selected element only
                end
                if elem == "DocFragment" or elem == "FictionBook" then
                    -- Ignore the root node up these
                    break;
                end
            end
        end
    end

    -- Add a button for each proposed selector to copy it, avoiding possible duplicates
    table.insert(proposed_selectors, ancestors_classnames_selector) -- ie. "section.chap > div > p.justif1.no-indent
    local copy_buttons = {}
    local add_copy_button = function(text)
        table.insert(copy_buttons, {{
            text = text,
            callback = function()
                Device.input.setClipboardText(text)
                UIManager:show(Notification:new{
                    text = _("Selector copied to clipboard.")
                })
            end,
            -- Allow "appending" with long-press, in case we want to gather a few selectors
            -- at once to later work with them in a style tweak
            hold_callback = function()
                Device.input.setClipboardText(Device.input.getClipboardText() .. "\n" .. text)
                UIManager:show(Notification:new{
                    text = _("Selector appended to clipboard.")
                })
            end,
        }})
    end
    local already_added = {}
    for _, text in ipairs(proposed_selectors) do
        if text and text ~= "" and not already_added[text] then
            add_copy_button(text)
            already_added[text] = true
        end
    end

    -- Add Show matched stylesheet rulesets buttons
    table.insert(copy_buttons, {})
    table.insert(copy_buttons, {{
        text = _("Show matched stylesheets rules (element only)"),
        callback = function()
            self:_showMatchingSelectors(document, ancestors, false)
        end,
        hold_callback = function()
            -- skip main stylesheet and style tweaks
            self:_showMatchingSelectors(document, ancestors, false, false)
        end,
    }})
    table.insert(copy_buttons, {{
        text = _("Show matched stylesheets rules (all ancestors)"),
        callback = function()
            self:_showMatchingSelectors(document, ancestors, true)
        end,
        hold_callback = function()
            -- skip main stylesheet and style tweaks
            self:_showMatchingSelectors(document, ancestors, true, false)
        end,
    }})

    local ButtonDialog = require("ui/widget/buttondialog")
    local widget = ButtonDialog:new{
        title = _("Copy to clipboard:"),
        title_align = "center",
        width_factor = 0.8,
        use_info_style = false,
        buttons = copy_buttons,
    }
    UIManager:show(widget)
end

function ViewHtml:_showMatchingSelectors(document, ancestors, show_all_ancestors, with_main_stylesheet)
    local snippets
    if not show_all_ancestors then
        local node_dataindex = ancestors[1][2]
        snippets = document:getStylesheetsMatchingRulesets(node_dataindex, with_main_stylesheet)
    else
        snippets = {}
        local elements = {}
        for _, ancestor in ipairs(ancestors) do
            table.insert(elements, 1, ancestor[1])
        end
        for i = 1, #ancestors do
            local node_dataindex = ancestors[i][2]
            if #snippets > 0 then
                -- Separate them with 2 blank lines
                table.insert(snippets, "")
                table.insert(snippets, "")
            end
            local desc = table.concat(elements, " > ", 1, #ancestors - i + 1)
            -- We use Unicode solid black blocks to make these really visible
            table.insert(snippets, "/* \u{259B}" .. ("\u{2580}"):rep(20) .. " */")
            table.insert(snippets, "/* \u{258C}" .. desc .. " */")
            table.insert(snippets, "/* \u{2599}" .. ("\u{2584}"):rep(20) .. " */")
            util.arrayAppend(snippets, document:getStylesheetsMatchingRulesets(node_dataindex, with_main_stylesheet))
        end
    end

    local title = show_all_ancestors and _("Matching rulesets (all ancestors)")
                                      or _("Matching rulesets (element only)")
    local css_text = table.concat(snippets, "\n")
    local cssviewer
    cssviewer = TextViewer:new{
        title = title,
        text = css_text or _("No matching rulesets"),
        text_type = "code",
        para_direction_rtl = false,
        auto_para_direction = false,
        add_default_buttons = true,
        buttons_table = {
            {{
                text = _("Prettify"),
                enabled = css_text and true or false,
                callback = function()
                    UIManager:close(cssviewer)
                    UIManager:show(TextViewer:new{
                        title = title,
                        text = util.prettifyCSS(css_text),
                        text_type = "code",
                        para_direction_rtl = false,
                        auto_para_direction = false,
                    })
                end,
            }},
        }
    }
    UIManager:show(cssviewer)
end

return ViewHtml
