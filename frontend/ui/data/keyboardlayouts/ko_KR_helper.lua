--[[--

# Hangul-input-method Kit for Lua/KOReader

## Input method implemented: 2-beolsik (for simplicity, can retrieve many articles for implementation)
## Classes and their features

 * HgSylbls (= Hangul Syllables)
   - Determine if a character is in Hangul consonnant, vowel, initial, medial, or final character
   - Combine initial, medial[, and final] character into a complete syllables
   - Determine if a medial (or final) character can be a double one (can combine another medial (or final) one)
 * HgFSM (= Hangul Finite State Machine)
   - Process Hangul syllabus combination if the character that user inputs are valid one to be combined
 * UIHandler
   - To communicate with the actual UI text input box

## References
<https://ehclub.co.kr/2482>
:: Hangul syllables combination formula, Hangul unicode composition, FSM reference
<https://en.wikipedia.org/wiki/Hangul_consonant_and_vowel_tables>

--]]

local BaseUtil = require("ffi/util")
local util = require("util")
local logger = require("logger")

-- Hangul Syllables

local HgSylbls = {
    -- Hangul character ranges in Unicode
    UNI_HG_BASE = 0xac00,
    UNI_HG_UPPER = 0xd7af,

    UNI_HG_CONSONNANT_BASE = 0x1100,
    UNI_HG_CONSONNANT_UPPER = 0x1112,

    UNI_HG_VOWEL_BASE = 0x1161,
    UNI_HG_VOWEL_UPPER = 0x1175,

    UNI_HG_COMPAT_CONSONNANT_BASE = 0x3131,
    UNI_HG_COMPAT_CONSONNANT_UPPER = 0x314e,
    UNI_HG_COMPAT_VOWEL_BASE = 0x314f,
    UNI_HG_COMPAT_VOWEL_UPPER = 0x3163,

    -- Initial, medial, and final characters to be combined
    CHARS_INITIAL = {"ㄱ", "ㄲ",   "ㄴ", "ㄷ", "ㄸ",   "ㄹ", "ㅁ", "ㅂ", "ㅃ",
                     "ㅅ", "ㅆ",   "ㅇ", "ㅈ", "ㅉ",   "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"},

    CHARS_MEDIAL = {"ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅗㅏ", "ㅗㅐ", "ㅗㅣ", "ㅛ",
                    "ㅜ", "ㅜㅓ", "ㅜㅔ", "ㅜㅣ", "ㅠ", "ㅡ", "ㅡㅣ", "ㅣ"},
    CHARS_MEDIAL_COMBINABLE = {"ㅗ", "ㅜ", "ㅡ"},

    CHARS_FINAL = {nil, "ㄱ", "ㄲ", "ㄱㅅ", "ㄴ", "ㄴㅈ", "ㄴㅎ", "ㄷ", "ㄹ", "ㄹㄱ", "ㄹㅁ", "ㄹㅂ", "ㄹㅅ",
                        "ㄹㅌ", "ㄹㅍ", "ㄹㅎ",
                        "ㅁ", "ㅂ", "ㅂㅅ",  "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"},
    CHARS_FINAL_COMBINABLE = {"ㄴ", "ㄹ", "ㅂ"},

    -- For faster search, inverse index tables will be constructed in runtime
    IDX_INITIAL = nil,
    IDX_MEDIAL = nil,
    IDX_MEDIAL_COMBINABLE = nil,
    IDX_FINAL = nil,
    IDX_FINAL_COMBINABLE = nil,
}

function HgSylbls:create_inverse_tbl()
    HgSylbls:_create_inverse_tbl_impl("CHARS", "IDX", "INITIAL")
    HgSylbls:_create_inverse_tbl_impl("CHARS", "IDX", "MEDIAL")
    HgSylbls:_create_inverse_tbl_impl("CHARS", "IDX", "MEDIAL_COMBINABLE")
    HgSylbls:_create_inverse_tbl_impl("CHARS", "IDX", "FINAL")
    HgSylbls:_create_inverse_tbl_impl("CHARS", "IDX", "FINAL_COMBINABLE")
end

function HgSylbls:_create_inverse_tbl_impl(from_prefix, to_prefix, target_tbl)
    -- ref: https://stackoverflow.com/questions/38282234/returning-the-index-of-a-value-in-a-lua-table
    HgSylbls[to_prefix .. "_" .. target_tbl] = {}
    for k, v in pairs(HgSylbls[from_prefix .. "_" .. target_tbl]) do
        -- NOTE '-1' for making indices start from '0'
        HgSylbls[to_prefix .. "_" .. target_tbl][v] = k - 1
    end
end


function HgSylbls:get_combined_char(initial, medial, final)
    -- utf8.char() (i.e., encode)
    return util.unicodeCodepointToUtf8(HgSylbls:_get_combined_charcode(initial, medial, final))
end
function HgSylbls:_get_combined_charcode(initial, medial, final)
    local len_medial = #HgSylbls.CHARS_MEDIAL
    local len_final = #HgSylbls.CHARS_FINAL

    local combined_code = HgSylbls.UNI_HG_BASE
                  + HgSylbls:_initial_idx(initial) * len_medial * len_final
                  + HgSylbls:_medial_idx(medial) * len_final

    local final_idx = HgSylbls:_final_idx(final)
    if final_idx then
        combined_code = combined_code + final_idx
    end

    return combined_code
end

function HgSylbls:_initial_idx(char)
    -- double initial can be typed directly from 2-beolsik kbd, hence no table of two chars
    return HgSylbls.IDX_INITIAL[char]
end
function HgSylbls:_medial_idx(char)
    char = HgSylbls:_2elem_tbl_to_str(char)
    return HgSylbls.IDX_MEDIAL[char]
end
function HgSylbls:_final_idx(char)
    char = HgSylbls:_2elem_tbl_to_str(char)
    return HgSylbls.IDX_FINAL[char]
end


function HgSylbls:in_intial(char)
    -- double initial can be typed directly from 2-beolsik kbd, hence no table of two chars
    return HgSylbls.IDX_INITIAL[char] ~= nil
end
function HgSylbls:in_medial(char)
    char = HgSylbls:_2elem_tbl_to_str(char)
    return HgSylbls.IDX_MEDIAL[char] ~= nil
end
function HgSylbls:in_final(char)
    char = HgSylbls:_2elem_tbl_to_str(char)
    return HgSylbls.IDX_FINAL[char] ~= nil
end
function HgSylbls:is_medial_comb(char)
    return HgSylbls.IDX_MEDIAL_COMBINABLE[char] ~= nil
end
function HgSylbls:is_final_comb(char)
    return HgSylbls.IDX_FINAL_COMBINABLE[char] ~= nil
end

function HgSylbls:in_consonnant_char(char)
    return HgSylbls:_in_target_char_group(char,
            HgSylbls.UNI_HG_CONSONNANT_BASE, HgSylbls.UNI_HG_CONSONNANT_UPPER,
            HgSylbls.UNI_HG_COMPAT_CONSONNANT_BASE, HgSylbls.UNI_HG_COMPAT_CONSONNANT_UPPER)
end
function HgSylbls:in_vowel_char(char)
    return HgSylbls:_in_target_char_group(char,
            HgSylbls.UNI_HG_VOWEL_BASE, HgSylbls.UNI_HG_VOWEL_UPPER,
            HgSylbls.UNI_HG_COMPAT_VOWEL_BASE, HgSylbls.UNI_HG_COMPAT_VOWEL_UPPER)
end
function HgSylbls:_in_target_char_group(char, base, upper, compat_base, compat_upper)
    local code = BaseUtil.utf8charcode(char) -- utf8.codepoint() (i.e., decode)

    if code == nil then
        return false
    end

    local result = base <= code and code <= upper

    local result_compat = false
    if compat_base ~= nil then
        result_compat = compat_base <= code and code <= compat_upper
    end

    return result or result_compat
end

function HgSylbls:_2elem_tbl_to_str(str_or_tbl)
    -- if the type of argument is a 'table',
    -- then it is a double medial/final character
    if type(str_or_tbl) == "table" then
        local tbl = str_or_tbl
        return tbl[1] .. tbl[2]
    end
    -- otherwise, return an argument as-is
    return str_or_tbl
end

-- initialize HgSylbls inverse index table
HgSylbls:create_inverse_tbl()


---------------
-- UI interface mock; will be implemented
---------------

local UIHandler = {}

function UIHandler:put_char(char)
    logger.dbg("UI:put_char()", char)
end
function UIHandler:del_char()
    logger.dbg("UI:del_char()")
end
function UIHandler:del_put_char(char)
    UIHandler:del_char()
    UIHandler:put_char(char)
end

----------------------
-- Hangul Automata  --
----------------------

local HgFSM = {
    STATE = {
        IDLE = 0,
        GOT_INITIAL = 1,
        GOT_MEDIAL = 2,
        GOT_FINAL = 3,
        GOT_DOUBLE_MEDIAL = 4,
        GOT_DOUBLE_FINAL = 5,
    },

    initial = nil,
    medial = nil,
    final = nil,

    fsm_state = nil,
    fsm_prev_states = nil, -- array

    do_not_del_in_medial = false,

    ui_handler = nil,
}

function HgFSM:init(ui_handler)
    HgFSM:clean_state()

    HgFSM.ui_handler = ui_handler
end

function HgFSM:clean_state()
    HgFSM.initial = nil
    HgFSM.medial = nil
    HgFSM.final = nil

    HgFSM.fsm_prev_states = {HgFSM.STATE.IDLE}
    HgFSM.fsm_state = HgFSM.STATE.IDLE

    HgFSM.do_not_del_in_medial = false
end

function HgFSM:_push_state(state)
    HgFSM.fsm_prev_states[#HgFSM.fsm_prev_states+1] = state -- append a state
    HgFSM.fsm_state = state
end
function HgFSM:_pop_state()
    local prev_state = HgFSM.fsm_prev_states[#HgFSM.fsm_prev_states]

    table.remove(HgFSM.fsm_prev_states) -- pop last item
    HgFSM.fsm_state = HgFSM.fsm_prev_states[#HgFSM.fsm_prev_states]

    return prev_state
end

function HgFSM:process_char(char)
    if HgFSM:_should_handle_as_target_char(char) then
        HgFSM:_process_hg_char(char)
    else
        HgFSM:_process_generic_char(char)
    end
end

function HgFSM:process_bsp(char)
    if HgFSM.fsm_state == HgFSM.STATE.IDLE or HgFSM.fsm_state == HgFSM.STATE.GOT_INITIAL then
        HgFSM:_process_generic_bsp()
    else
        HgFSM:_process_hg_bsp_except_initial()
        HgFSM:_process_hg_char_update_ui(true) -- true: always remove the current character in edit
    end
end

function HgFSM:_should_handle_as_target_char(char)
    if HgSylbls:in_consonnant_char(char) then
        return true
    elseif HgSylbls:in_vowel_char(char) and HgFSM.fsm_state ~= HgFSM.STATE.IDLE then
        return true
    end

    return false
end

function HgFSM:_process_generic_char(char)
    HgFSM:clean_state()
    HgFSM.ui_handler:put_char(char)
end
function HgFSM:_process_generic_bsp(char)
    HgFSM:clean_state()
    HgFSM.ui_handler:del_char()
end

function HgFSM:_process_hg_char(char)
    local result = HgFSM:_process_hg_char_impl(char)

    if result then
        HgFSM:_process_hg_char_update_ui()
    else -- e.g. single vowel character
        HgFSM:_process_generic_char(char)
    end
end

function HgFSM:_process_hg_bsp_except_initial()
    local prev_state = HgFSM:_pop_state()

    if prev_state == HgFSM.STATE.GOT_MEDIAL then
        HgFSM.medial = nil

    elseif prev_state == HgFSM.STATE.GOT_DOUBLE_MEDIAL then
        HgFSM.medial = HgFSM.medial[1]

    elseif prev_state == HgFSM.STATE.GOT_FINAL then
        HgFSM.final = nil

    elseif prev_state == HgFSM.STATE.GOT_DOUBLE_FINAL then
        HgFSM.final = HgFSM.final[1]

    end
end

function HgFSM:_process_hg_char_impl(char)
    if HgFSM.fsm_state == HgFSM.STATE.IDLE then
        HgFSM:_process_hg_char_new_hg(char)

    elseif HgFSM.fsm_state == HgFSM.STATE.GOT_INITIAL then
        if HgSylbls:in_consonnant_char(char) then
            HgFSM:_process_hg_char_new_hg(char)
        else
            HgFSM:_process_hg_char_push_medial(char)
        end

    elseif HgFSM.fsm_state == HgFSM.STATE.GOT_MEDIAL then
        if HgSylbls:in_vowel_char(char) then
            local dbl_medial_cand = {HgFSM.medial, char}
            if HgSylbls:is_medial_comb(HgFSM.medial) and HgSylbls:in_medial(dbl_medial_cand) then
                HgFSM:_process_hg_char_push_medial(dbl_medial_cand, true)
            else
                return false
            end
        else
            HgFSM:_process_hg_char_push_final(char)
        end

    elseif HgFSM.fsm_state == HgFSM.STATE.GOT_DOUBLE_MEDIAL then
        if HgSylbls:in_vowel_char(char) then
            return false
        else
            HgFSM:_process_hg_char_push_final(char)
        end

    elseif HgFSM.fsm_state == HgFSM.STATE.GOT_FINAL then
        if HgSylbls:in_vowel_char(char) then
            HgFSM:_process_hg_char_borrow_initial_push_next_medial(
                nil, HgFSM.final, char)
        else
            local dbl_final_cand = {HgFSM.final, char}
            if HgSylbls:is_final_comb(HgFSM.final) and HgSylbls:in_final(dbl_final_cand) then
                HgFSM:_process_hg_char_push_final(dbl_final_cand, true)
            else
                HgFSM:_process_hg_char_new_hg(char)
            end
        end

    elseif HgFSM.fsm_state == HgFSM.STATE.GOT_DOUBLE_FINAL then
        if HgSylbls:in_vowel_char(char) then
            HgFSM:_process_hg_char_borrow_initial_push_next_medial(
                HgFSM.final[1], HgFSM.final[2], char)
        else
            HgFSM:_process_hg_char_new_hg(char)
        end

    end

    return true
end

function HgFSM:_process_hg_char_new_hg(char)
    HgFSM:clean_state()

    HgFSM:_push_state(HgFSM.STATE.GOT_INITIAL)
    HgFSM.initial = char
end

function HgFSM:_process_hg_char_push_medial(char, is_double)
    if is_double then
        HgFSM:_push_state(HgFSM.STATE.GOT_DOUBLE_MEDIAL)
    else
        HgFSM:_push_state(HgFSM.STATE.GOT_MEDIAL)
    end
    HgFSM.medial = char
end

function HgFSM:_process_hg_char_push_final(char, is_double)
    if is_double then
        HgFSM:_push_state(HgFSM.STATE.GOT_DOUBLE_FINAL)
    else
        HgFSM:_push_state(HgFSM.STATE.GOT_FINAL)
    end
    HgFSM.final = char
end

function HgFSM:_process_hg_char_borrow_initial_push_next_medial(curr_final, next_init, next_medial)
    local next_init_cand = next_init
    HgFSM.final = curr_final
    HgFSM:_pop_state() -- go to previous state
    HgFSM:_process_hg_char_update_ui() -- apply UI the borrow of final character

    HgFSM:_process_hg_char_new_hg(next_init_cand)

    HgFSM:_push_state(HgFSM.STATE.GOT_MEDIAL)
    HgFSM.medial = next_medial
    HgFSM.do_not_del_in_medial = true -- previous character in edit has to be maintained
end


function HgFSM:_process_hg_char_update_ui(should_undo_in_initial)
    should_undo_in_initial = should_undo_in_initial or false

    if HgFSM.fsm_state == HgFSM.STATE.GOT_INITIAL then
        if should_undo_in_initial then
            HgFSM.ui_handler:del_char()
        end
        HgFSM.ui_handler:put_char(HgFSM.initial)

    elseif HgFSM.fsm_state == HgFSM.STATE.GOT_MEDIAL or HgFSM.fsm_state == HgFSM.STATE.GOT_DOUBLE_MEDIAL then
        local combined_char = HgSylbls:get_combined_char(HgFSM.initial, HgFSM.medial, nil)
        if HgFSM.do_not_del_in_medial then
            HgFSM.do_not_del_in_medial = false
            HgFSM.ui_handler:put_char(combined_char)
        else
            HgFSM.ui_handler:del_put_char(combined_char)
        end

    elseif HgFSM.fsm_state == HgFSM.STATE.GOT_FINAL or HgFSM.fsm_state == HgFSM.STATE.GOT_DOUBLE_FINAL then
        local combined_char = HgSylbls:get_combined_char(HgFSM.initial, HgFSM.medial, HgFSM.final)
        HgFSM.ui_handler:del_put_char(combined_char)

    end
end


return {
    UIHandler = UIHandler,
    HgFSM = HgFSM,
}
