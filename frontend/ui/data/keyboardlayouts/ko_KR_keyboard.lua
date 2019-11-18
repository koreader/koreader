local logger = require("logger")

--------
-- # Korean 2-beolsik Keyboard layout
--------

local HgHelper = require("ui/data/keyboardlayouts/ko_KR_helper")

--------
-- UI handler implementation for communicating with text input box widget
--------
function HgHelper.UIHandler:put_char(char)
    HgHelper.UIHandler.inputbox:_addChars(char)
end
function HgHelper.UIHandler:del_char(char)
    HgHelper.UIHandler.inputbox:_delChar()
end
HgHelper.HgFSM:init(HgHelper.UIHandler)

--------
-- Custom key event handlers with Hangul support
--------
local wrapInputBox = function(inputbox)
    HgHelper.HgFSM.clean_state() -- reset helper

    if inputbox._wrapped == nil then
        inputbox._wrapped = true

        -- helper function
        local function copy_func_reference(obj, name)
            obj["_" .. name] = obj[name]
        end

        -- override original implementations with helper object
        copy_func_reference(inputbox, "addChars")
        copy_func_reference(inputbox, "delChar")

        function inputbox:addChars(key)
            logger.dbg("ko_KR_kbd:addChar(", key, ")")
            HgHelper.UIHandler.inputbox = self
            HgHelper.HgFSM:process_char(key)
        end
        function inputbox:delChar()
            logger.dbg("ko_KR_kbd:delChar()")
            HgHelper.UIHandler.inputbox = self
            HgHelper.HgFSM:process_bsp()
        end

        -- override implementations: reset helper if we have to stop combining current syllable
        ---- helper function
        local function wrap_func_with_hghelper_reset(obj, name)
            copy_func_reference(obj, name)
            obj[name] = function(self)
                HgHelper.HgFSM.clean_state()
                self["_" .. name](self)
            end
        end

       ---- delete text
        wrap_func_with_hghelper_reset(inputbox, "delToStartOfLine")
        wrap_func_with_hghelper_reset(inputbox, "clear")

        ---- move cursor
        wrap_func_with_hghelper_reset(inputbox, "leftChar")
        wrap_func_with_hghelper_reset(inputbox, "rightChar")
        wrap_func_with_hghelper_reset(inputbox, "upLine")
        wrap_func_with_hghelper_reset(inputbox, "downLine")

        ---- unfocus: move to other inputbox
        wrap_func_with_hghelper_reset(inputbox, "unfocus")

        ---- tap/hold/swipe: move cursor
        ------ helper function
        local function wrap_touch_event_func_with_hghelper_reset(obj, name)
            copy_func_reference(obj, name)
            obj[name] = function(self, arg, ges)
                HgHelper.HgFSM.clean_state()
                return self["_" .. name](self, arg, ges)
            end
        end

        wrap_touch_event_func_with_hghelper_reset(inputbox, "onTapTextBox")
        wrap_touch_event_func_with_hghelper_reset(inputbox, "onHoldTextBox")
        wrap_touch_event_func_with_hghelper_reset(inputbox, "onSwipeTextBox")
    end
end

-- Belows are just same as the English keyboard popup
local en_popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
local com = en_popup.com -- comma (,)
local prd = en_popup.prd -- period (.)
local _at = en_popup._at
local _eq = en_popup._eq -- equals sign (=)
local _A_ = en_popup._A_
local _a_ = en_popup._a_
local _B_ = en_popup._B_
local _b_ = en_popup._b_
local _C_ = en_popup._C_
local _c_ = en_popup._c_
local _D_ = en_popup._D_
local _d_ = en_popup._d_
local _E_ = en_popup._E_
local _e_ = en_popup._e_
local _F_ = en_popup._F_
local _f_ = en_popup._f_
local _G_ = en_popup._G_
local _g_ = en_popup._g_
local _H_ = en_popup._H_
local _h_ = en_popup._h_
local _I_ = en_popup._I_
local _i_ = en_popup._i_
local _J_ = en_popup._J_
local _j_ = en_popup._j_
local _K_ = en_popup._K_
local _k_ = en_popup._k_
local _L_ = en_popup._L_
local _l_ = en_popup._l_
local _M_ = en_popup._M_
local _m_ = en_popup._m_
local _N_ = en_popup._N_
local _n_ = en_popup._n_
local _O_ = en_popup._O_
local _o_ = en_popup._o_
local _P_ = en_popup._P_
local _p_ = en_popup._p_
local _Q_ = en_popup._Q_
local _q_ = en_popup._q_
local _R_ = en_popup._R_
local _r_ = en_popup._r_
local _S_ = en_popup._S_
local _s_ = en_popup._s_
local _T_ = en_popup._T_
local _t_ = en_popup._t_
local _U_ = en_popup._U_
local _u_ = en_popup._u_
local _V_ = en_popup._V_
local _v_ = en_popup._v_
local _W_ = en_popup._W_
local _w_ = en_popup._w_
local _X_ = en_popup._X_
local _x_ = en_popup._x_
local _Y_ = en_popup._Y_
local _y_ = en_popup._y_
local _Z_ = en_popup._Z_
local _z_ = en_popup._z_

-- Based on English keyboard layout, but modifications are made for Korean layout
return {
    min_layer = 1,
    max_layer = 12,
    shiftmode_keys = {["Shift"] = true},
    symbolmode_keys = {["Sym"] = true, ["ABC"] = true},
    utf8mode_keys = {["🌐"] = true},
    umlautmode_keys = {["Äéß"] = false},  -- Disabled 'umlaut' keys
    keys = {
        -- [shift, unshift, symbol-shift, symbol-unshift]
        -- 1, 2, 3, 4: default
        -- 5, 6, 7, 8: 'IM' (globe)
        -- 9, 10, 11, 12: 'umlaut' (UNUSED)
        --
        -- first row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { _Q_,        _q_,    "„",    "0",    "ㅃ",    "ㅂ",   "￦",    "0",    "Å",    "å",    "1",    "ª", },
            { _W_,        _w_,    "!",    "1",    "ㅉ",    "ㅈ",    "!",    "1",    "Ä",    "ä",    "2",    "º", },
            { _E_,        _e_,    _at,    "2",    "ㄸ",    "ㄷ",    _at,    "2",    "Ö",    "ö",    "3",    "¡", },
            { _R_,        _r_,    "#",    "3",    "ㄲ",    "ㄱ",    "#",    "3",    "ß",    "ß",    "4",    "¿", },
            { _T_,        _t_,    "+",    _eq,    "ㅆ",    "ㅅ",    "+",    _eq,    "À",    "à",    "5",    "¼", },
            { _Y_,        _y_,    "€",    "(",    "ㅛ",    "ㅛ",    "☆",    "(",    "Â",    "â",    "6",    "½", },
            { _U_,        _u_,    "‰",    ")",    "ㅕ",    "ㅕ",    "★",    ")",    "Æ",    "æ",    "7",    "¾", },
            { _I_,        _i_,    "|",   "\\",    "ㅑ",    "ㅑ",    "♡",   "\\",    "Ü",    "ü",    "8",    "©", },
            { _O_,        _o_,    "?",    "/",    "ㅒ",    "ㅐ",    "♥",    "/",    "È",    "è",    "9",    "®", },
            { _P_,        _p_,    "~",    "`",    "ㅖ",    "ㅔ",    "※",    "`",    "É",    "é",    "0",    "™", },
        },
        -- second row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { _A_,        _a_,    "…",    _at,    "ㅁ",    "ㅁ",    "…",    "@",    "Ê",    "ê",    "Ş",    "ş", },
            { _S_,        _s_,    "$",    "4",    "ㄴ",    "ㄴ",    "$",    "4",    "Ë",    "ë",    "İ",    "ı", },
            { _D_,        _d_,    "%",    "5",    "ㅇ",    "ㅇ",    "%",    "5",    "Î",    "î",    "Ğ",    "ğ", },
            { _F_,        _f_,    "^",    "6",    "ㄹ",    "ㄹ",    "^",    "6",    "Ï",    "ï",    "Ć",    "ć", },
            { _G_,        _g_,    ":",    ";",    "ㅎ",    "ㅎ",    ":",    "'",    "Ô",    "ô",    "Č",    "č", },
            { _H_,        _h_,    '"',    "'",    "ㅗ",    "ㅗ",    "♩",   "\"",    "Œ",    "œ",    "Đ",    "đ", },
            { _J_,        _j_,    "{",    "[",    "ㅓ",    "ㅓ",    "♪",    "[",    "Ù",    "ù",    "Š",    "š", },
            { _K_,        _k_,    "}",    "]",    "ㅏ",    "ㅏ",    "♬",    "]",    "Û",    "û",    "Ž",    "ž", },
            { _L_,        _l_,    "_",    "-",    "ㅣ",    "ㅣ",    "™",    "-",    "Ÿ",    "ÿ",    "Ő",    "ő", },
        },
        -- third row
        {  --  1           2       3       4       5       6       7       8       9       10      11      12
            { label = "Shift",
              icon = "resources/icons/appbar.arrow.shift.png",
              width = 1.5
            },
            { _Z_,        _z_,    "&",    "7",    "ㅋ",    "ㅋ",    "「",    "7",    "Á",    "á",    "Ű",    "ű", },
            { _X_,        _x_,    "*",    "8",    "ㅌ",    "ㅌ",    "」",    "8",    "Ø",    "ø",    "Ã",    "ã", },
            { _C_,        _c_,    "£",    "9",    "ㅊ",    "ㅊ",    "*",    "9",    "Í",    "í",    "Þ",    "þ", },
            { _V_,        _v_,    "<",    com,    "ㅍ",    "ㅍ",    "❤",    com,    "Ñ",    "ñ",    "Ý",    "ý", },
            { _B_,        _b_,    ">",    prd,    "ㅠ",    "ㅠ",    "&",    prd,    "Ó",    "ó",    "†",    "‡", },
            { _N_,        _n_,    "‘",    "↑",    "ㅜ",    "ㅜ",    "『",    "↑",    "Ú",    "ú",    "–",    "—", },
            { _M_,        _m_,    "’",    "↓",    "ㅡ",    "ㅡ",    "』",    "↓",    "Ç",    "ç",    "…",    "¨", },
            { label = "Backspace",
              icon = "resources/icons/appbar.clear.reflect.horizontal.png",
              width = 1.5
            },
        },
        -- fourth row
        {
            { "Sym",     "Sym",  "ABC",  "ABC",  "Sym",  "Sym",  "ABC",  "ABC",  "Sym",  "Sym",  "ABC",  "ABC",
              width = 1.5},
            { label = "🌐",
              width = 2,
            },
            -- { "Äéß",     "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß",  "Äéß", },
            { label = "간격",
              " ",        " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",    " ",
              width = 3.0},
            { com,        com,    "“",    "←",    com,    com,    com,    "←",    "Ũ",   "ũ",    com,    com, },
            { prd,        prd,    "”",    "→",    prd,    prd,    prd,    "→",    "Ĩ",   "ĩ",    prd,    prd, },
            { label = "Enter",
              "\n",       "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",   "\n",
              icon = "resources/icons/appbar.arrow.enter.png",
              width = 1.5,
            },
        },
    },

    -- wrap InputBox for hooking events to the helper
    wrapInputBox = wrapInputBox,
}
