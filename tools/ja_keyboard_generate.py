#!/usr/bin/env python3

# Copyright (c) 2021 Aleksa Sarai <cyphar@cyphar.com>
# Licensed under the AGPLv3-or-later.
#
# usage: ./tools/ja_keyboard_generate.py > frontend/ui/data/keyboardlayouts/ja_keyboard_keys.lua
#
# Generates the modifier cycle table for the Japanese 12-key flick keyboard as
# well as the cycle table for each key, the goal being to create an efficient
# mapping for each kana so that when a given modifier is pressed we can easily
# switch to the next key. Each kana is part of a cycle so pressing the modifier
# key multiple times will loop through the options, as will tapping the same
# letter multiple times.

import os
import unicodedata

import jinja2

def NFC(s): return unicodedata.normalize("NFC", s)
def NFD(s): return unicodedata.normalize("NFD", s)

RAW_DAKUTEN = "\u3099"
RAW_HANDAKUTEN = "\u309A"

def modified_kana(kana):
	# Try to produce versions of the kana which are combined with dakuten or
	# handakuten. We only care about combined versions of the character if the
	# combined version is a single codepoint (which means it's a "standard"
	# combination and is thus a valid modified version of the given kana).
	#
	# Python3's len() counts the number of codepoints, which is what we want.
	return [ NFC(kana+modifier)
			 for modifier in [RAW_DAKUTEN, RAW_HANDAKUTEN]
				 if len(NFC(kana+modifier)) == 1 ]

# Hiragana and katakana without any dakuten.
BASE_KANA = "あいえうおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん" + \
			"アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン"

# The set of small kana (from their big kana equivalent).
TO_SMALL_KANA = {
	# Hiragana
	"あ": "ぁ", "い": "ぃ", "う": "ぅ", "え": "ぇ", "お": "ぉ",
	"や": "ゃ",             "ゆ": "ゅ",             "よ": "ょ",
	"わ": "ゎ",             "つ": "っ",

	# Katakana
	"ア": "ァ", "イ": "ィ", "ウ": "ゥ", "エ": "ェ", "オ": "ォ",
	"ヤ": "ャ",             "ユ": "ュ",             "ヨ": "ョ",
	"ワ": "ヮ",             "ツ": "ッ",
}
# ... and vice-versa.
FROM_SMALL_KANA = {small: big for big, small in TO_SMALL_KANA.items()}

# The set of kana derived from BASE_KANA.
MODIFIED_KANA = "".join("".join(modified_kana(kana)) for kana in BASE_KANA)
SMALL_KANA = "".join(FROM_SMALL_KANA.keys())
ALL_KANA = BASE_KANA + MODIFIED_KANA + SMALL_KANA

EN_ALPHABET = "abcdefghijklmnopqrstuvwxyz"

def escape_luastring(s):
	# We cannot use repr() because Python escapes are not valid Lua.
	return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def generate_cycle(kana):
	"Generate an array describing the modifier cycle for a given kana."
	# The cycle starts with the provided kana.
	cycle = [NFC(kana)]
	# If there are any small kana, add them to the cycle.
	if kana in TO_SMALL_KANA:
		cycle.append(TO_SMALL_KANA[kana])
	# If there are any valid modifications of this kana, add them to the cycle.
	cycle.extend(modified_kana(kana))
	return cycle

def generate_basic_cycle(kana, modifier):
	"""
	Generate an array describing a basic cycle using just the given combining
	mark.
	"""
	cycle = [NFC(kana)]
	# Remove any combining marks and convert back to large kana if possible.
	# This allows us to create cycles which start with a modified kana (mainly
	# useful for the dedicated modifiers).
	base_kana, *_ = NFD(kana)
	if base_kana in FROM_SMALL_KANA:
		base_kana = FROM_SMALL_KANA[base_kana]
	new_kana = NFC(base_kana + modifier)
	if new_kana != kana and len(new_kana) == 1:
		cycle.append(new_kana)
	return cycle

def generate_smallkana_cycle(kana):
	cycle = [NFC(kana)]
	base_kana, *_ = NFD(kana) # Remove any combining marks.
	if base_kana in TO_SMALL_KANA:
		cycle.append(TO_SMALL_KANA[base_kana])
	return cycle

def generate_alphabet_shift_cycle(letter):
	return [letter, letter.upper()]

def output_cycle(cycle, loop=True):
	"Return a snippet of a Lua table describing the cycle passed."
	cycle = list(cycle)
	if len(cycle) == 1:
		return "" # Don't do anything for noop one-kana cycles.
	if loop:
		# Map the last kana back to the start.
		mapping = zip(cycle, cycle[1:] + [cycle[0]])
	else:
		# The last kana doesn't get any mapping.
		mapping = zip(cycle, cycle[1:])
	lua_snippet = []
	for kana_src, kana_dst in mapping:
		lua_snippet.append(f"[{escape_luastring(kana_src)}] = {escape_luastring(kana_dst)},")
	return " ".join(lua_snippet)

# Straightforward cycle over all options.
cyclic_table = [ output_cycle(generate_cycle(kana)) for kana in BASE_KANA ]

# For all of the specialised tables we do not loop back to the original kana.
# This is done to match the GBoard behaviour, where only the base 変換 button
# loops back through all of the options.
dakuten_table = [ output_cycle(generate_basic_cycle(kana, RAW_DAKUTEN), loop=False) for kana in ALL_KANA ]
handakuten_table = [ output_cycle(generate_basic_cycle(kana, RAW_HANDAKUTEN), loop=False) for kana in ALL_KANA ]
smallkana_table = [ output_cycle(generate_smallkana_cycle(kana), loop=False) for kana in ALL_KANA ]
# NOTE: If we ever want to enable looping for these modifiers, just set
#       loop=True for BASE_KANA and loop=False only for the derived
#       {MODIFIED,SMALL}_KANA.

# Straightforward cycle through shifted and unshifted letters.
shift_table = [ output_cycle(generate_alphabet_shift_cycle(letter)) for letter in EN_ALPHABET ]

class Key(object):
	def __init__(self, name, popout, loop=None, label=None, alt_label=None):
		self.name = name
		self.popout = popout
		self.label = label
		self.alt_label = alt_label
		self.loop = loop or popout # default to popout order

	def render_key(self, indent_level=1):
		lua_items = []
		if self.label:
			lua_items.append(f'label = {escape_luastring(self.label)}')
		if self.alt_label:
			lua_items.append(f'alt_label = {escape_luastring(self.alt_label)}')
		if lua_items:
			lua_items.append("\n") # Put the labels on a separate line.
		for direction, key in zip(["", "west", "north", "east", "south"], self.popout):
			if key != '\0':
				if direction:
					lua_items.append(f'{direction} = {escape_luastring(key)}')
				else:
					lua_items.append(f'{escape_luastring(key)}')
		lua_item = f'{self.name} = {{ {", ".join(lua_items)} }}'
		# Fix newlines to match the indentation and remove the doubled comma.
		indent = len(self.name) + 4 * (indent_level + 1)
		return lua_item.replace(", \n, ", ",\n" + " " * indent)

	def render_key_cycle(self):
		cycle = output_cycle(self.loop)
		if cycle:
			return f"{{ {cycle} }}"
		else:
			return "nil"

# Hiragana, katakana, latin, and symbol keys in [tap, east, north, west, south]
# order to match GBoard/Flick input. This is basically the Japanese version of
# T9 order. The keys are the variable names we assign for each keypad, for use
# in ja_keyboard.lua.
KEYPADS = [
	# Hiragana keys.
	Key("h_a", "あいうえお", loop="あいうえおぁぃぅぇぉ"),
	Key("hKa", "かきくけこ"),
	Key("hSa", "さしすせそ"),
	Key("hTa", "たちつてと", loop="たちつてとっ"),
	Key("hNa", "なにぬねの"),
	Key("hHa", "はひふへほ"),
	Key("hMa", "まみむめも"),
	Key("hYa", "や（ゆ）よ", loop="やゆよゃゅょ", alt_label="（）"),
	Key("hRa", "らりるれろ"),
	Key("hWa", "わをんー〜", loop="わをんゎー〜", alt_label="ー〜"),
	Key("h_P", "、。？！…", loop="、。？！…・　", alt_label="。？！…"),

	# Katakana keys.
	Key("k_a", "アイウエオ", loop="アイウエオァィゥェォ"),
	Key("kKa", "カキクケコ"),
	Key("kSa", "サシスセソ"),
	Key("kTa", "タチツテト", loop="タチツテトッ"),
	Key("kNa", "ナニヌネノ"),
	Key("kHa", "ハヒフヘホ"),
	Key("kMa", "マミムメモ"),
	Key("kYa", "ヤ（ユ）ヨ", loop="ヤユヨャュョ", alt_label="（）"),
	Key("kRa", "ラリルレロ"),
	Key("kWa", "ワヲンー〜", loop="ワヲンヮー〜", alt_label="ー〜"),
	Key("k_P", "、。？！…", loop="、。？！…・　", alt_label="。？！…"),

	# Latin alphabet.
	Key("l_1", "@-_/１", label="@-_/", alt_label="１"),
	Key("l_2", "abc\0２", loop="abcABC２", label="abc", alt_label="２"),
	Key("l_3", "def\0３", loop="defDEF３", label="def", alt_label="３"),
	Key("l_4", "ghi\0４", loop="ghiGHI４", label="ghi", alt_label="４"),
	Key("l_5", "jkl\0５", loop="jklJKL５", label="jkl", alt_label="５"),
	Key("l_6", "mno\0６", loop="mnoMNO６", label="mno", alt_label="６"),
	Key("l_7", "pqrs７", loop="pqrsPQRS７", label="pqrs", alt_label="７"),
	Key("l_8", "tuv\0８", loop="tuvTUV８", label="tuv", alt_label="８"),
	Key("l_9", "wxyz９", loop="wxyzWXYZ９", label="wxyz", alt_label="９"),
	Key("l_0", "'\":;０", label="'\":;", alt_label="０"),
	Key("l_P", ",.?!", label=",.?!"),

	# Symbol / numpad keys. Note that we do not have any loops for this layer.
	Key("s_1", "1☆♪", loop="1", alt_label="☆♪"), # NOTE: Cannot include → because it's used internally.
	Key("s_2", "2¥$€", loop="2", alt_label="¥$€"),
	Key("s_3", "3%゜#", loop="3", alt_label="%゜#"),
	Key("s_4", "4○*・", loop="4", alt_label="○*・"),
	Key("s_5", "5+×÷", loop="5", alt_label="+×÷"),
	Key("s_6", "6<=>", loop="6", alt_label="<=>"),
	Key("s_7", "7「」:", loop="7", alt_label="「」:"),
	Key("s_8", "8〒々〆", loop="8", alt_label="〒々〆"),
	Key("s_9", "9^|\\", loop="9", alt_label="^|\\"),
	Key("s_0", "0~…@", loop="0", alt_label="~…@"),
	Key("s_b", "()[]", loop="(", label="()[]"),
	Key("s_p", ".,-/", loop=".", label=".,-/"),
]

TEMPLATE = jinja2.Template("""
--- @note This file was generated with tools/ja_keyboard_generate.py.
-- DO NOT EDIT THIS FILE MANUALLY. Instead, edit and re-run the script.

-- These values are displayed to users when they long-press on the modifier
-- key, so make them somewhat understandable (変換 is not the best word to use
-- for the cycle button because it's fairly generic and in IMEs it usually
-- indicates cycling through the IME suggestions but I couldn't find any
-- documentation about the 12-key keyboard that uses a more specific term).

local MODIFIER_CYCLIC = "変換"
local MODIFIER_DAKUTEN = "◌゙"
local MODIFIER_HANDAKUTEN = "◌゚"
local MODIFIER_SMALLKANA = "小"
local MODIFIER_SHIFT = "\uED35"

return {
    -- Keypad definitions.
{% for key in KEYPADS %}
    {{ key.render_key() }},
{% endfor %}

    -- Cycle lookup table for keitai (multi-tap) keypad input.
    KEITAI_TABLE = {
{% for key in KEYPADS %}
{% set key_cycle = key.render_key_cycle() %}
{% if key_cycle != "nil" %}
    {#
       Some loops (including the trigger character) are repeated (mainly h_P
       and k_P) but that's okay because the order is the same so we can just
       output it once and skip the next one.
    #}
    {% set loop_id = key.popout[0] + key.loop %}
    {% if loop_id not in seen_loops %}
        ["{{ key.popout[0] }}"] = {{ key_cycle }},
    {# We need to do some trickery to do the "seen set" pattern in Jinja. #}
    {{- [seen_loops.add(loop_id), ""][1] -}}
    {% endif %}
{% endif %}
{% endfor %}
    },

    -- Special keycodes for the cyclic keys.
    MODIFIER_KEY_CYCLIC = MODIFIER_CYCLIC,
    MODIFIER_KEY_DAKUTEN = MODIFIER_DAKUTEN,
    MODIFIER_KEY_HANDAKUTEN = MODIFIER_HANDAKUTEN,
    MODIFIER_KEY_SMALLKANA = MODIFIER_SMALLKANA,
    MODIFIER_KEY_SHIFT = MODIFIER_SHIFT,

    -- Modifier lookup table.
    MODIFIER_TABLE = {
        [MODIFIER_CYCLIC] = {
{% for entry in cyclic_table %}
    {% if entry %}
            {{ entry }}
    {% endif %}
{% endfor %}
        },
        [MODIFIER_DAKUTEN] = {
{% for entry in dakuten_table %}
    {% if entry %}
            {{ entry }}
    {% endif %}
{% endfor %}
        },
        [MODIFIER_HANDAKUTEN] = {
{% for entry in handakuten_table %}
    {% if entry %}
            {{ entry }}
    {% endif %}
{% endfor %}
        },
        [MODIFIER_SMALLKANA] = {
{% for entry in smallkana_table %}
    {% if entry %}
            {{ entry }}
    {% endif %}
{% endfor %}
        },
        [MODIFIER_SHIFT] = {
{% for entry in shift_table %}
    {% if entry %}
            {{ entry }}
    {% endif %}
{% endfor %}
        },
    },
}
""", trim_blocks=True, lstrip_blocks=True)

seen_loops = set()
print(TEMPLATE.render(locals()))
