--- Kazakh suffix inventory and layer ordering.
-- Suffixes attach in a fixed order, so each position is a "layer" and the
-- stemmer walks them left to right. `n` is the suffix length in CHARACTERS,
-- not bytes, `h` is the vowel-harmony class the suffix demands, and `w` marks
-- suffixes ambiguous with ordinary root material.
--
-- Generated from kazsearch/rules.py by tools/gen_lua_rules.py in
-- <https://github.com/iDynbek/kazsearch-py>; do not edit by hand.
--
-- @module koplugin.kazakh.rules
-- @alias M

-- Licensed under the AGPLv3 or later.
--
-- Derived from pg-kazsearch <https://github.com/darkhanakh/pg-kazsearch>,
-- LGPLv3 or later.

local M = {}

M.HARM_ANY, M.HARM_BACK, M.HARM_FRONT = 0, 1, 2

M.LAYER_PRED, M.LAYER_CASE, M.LAYER_POSS = 1, 2, 3
M.LAYER_PLUR, M.LAYER_DERIV = 4, 5
M.LAYER_VPERSON, M.LAYER_VTENSE = 11, 12
M.LAYER_VNEG, M.LAYER_VVOICE = 13, 14

M.KIND_NOMINAL, M.KIND_VERBAL, M.KIND_DERIV = 1, 2, 3

M.PRED = {
  {s="сыңдар", n=6, h=0, w=false},
  {s="сіңдер", n=6, h=0, w=false},
  {s="сыздар", n=6, h=0, w=false},
  {s="сіздер", n=6, h=0, w=false},
  {s="сыз", n=3, h=1, w=false},
  {s="сіз", n=3, h=2, w=false},
  {s="сың", n=3, h=1, w=false},
  {s="сің", n=3, h=2, w=false},
  {s="мын", n=3, h=1, w=false},
  {s="мін", n=3, h=2, w=false},
  {s="бын", n=3, h=1, w=false},
  {s="бін", n=3, h=2, w=false},
  {s="пын", n=3, h=1, w=false},
  {s="пін", n=3, h=2, w=false},
  {s="мыз", n=3, h=1, w=false},
  {s="міз", n=3, h=2, w=false},
}

M.CASE = {
  {s="ның", n=3, h=1, w=false},
  {s="нің", n=3, h=2, w=false},
  {s="дың", n=3, h=1, w=false},
  {s="дің", n=3, h=2, w=false},
  {s="тың", n=3, h=1, w=false},
  {s="тің", n=3, h=2, w=false},
  {s="нан", n=3, h=1, w=false},
  {s="нен", n=3, h=2, w=false},
  {s="дан", n=3, h=1, w=false},
  {s="ден", n=3, h=2, w=false},
  {s="тан", n=3, h=1, w=false},
  {s="тен", n=3, h=2, w=false},
  {s="нда", n=3, h=1, w=false},
  {s="нде", n=3, h=2, w=false},
  {s="бен", n=3, h=0, w=false},
  {s="пен", n=3, h=0, w=false},
  {s="мен", n=3, h=0, w=false},
  {s="ға", n=2, h=1, w=false},
  {s="ге", n=2, h=2, w=false},
  {s="қа", n=2, h=1, w=false},
  {s="ке", n=2, h=2, w=false},
  {s="на", n=2, h=1, w=false},
  {s="не", n=2, h=2, w=false},
  {s="ңа", n=2, h=1, w=false},
  {s="ңе", n=2, h=2, w=false},
  {s="ны", n=2, h=1, w=false},
  {s="ні", n=2, h=2, w=false},
  {s="а", n=1, h=1, w=true},
  {s="е", n=1, h=2, w=true},
  {s="ды", n=2, h=1, w=false},
  {s="ді", n=2, h=2, w=false},
  {s="ты", n=2, h=1, w=false},
  {s="ті", n=2, h=2, w=false},
  {s="ын", n=2, h=1, w=false},
  {s="ін", n=2, h=2, w=false},
  {s="да", n=2, h=1, w=false},
  {s="де", n=2, h=2, w=false},
  {s="та", n=2, h=1, w=false},
  {s="те", n=2, h=2, w=false},
  {s="н", n=1, h=0, w=true},
}

M.POSS = {
  {s="ымыз", n=4, h=1, w=false},
  {s="іміз", n=4, h=2, w=false},
  {s="ыңыз", n=4, h=1, w=false},
  {s="іңіз", n=4, h=2, w=false},
  {s="лары", n=4, h=1, w=false},
  {s="лері", n=4, h=2, w=false},
  {s="дары", n=4, h=1, w=false},
  {s="дері", n=4, h=2, w=false},
  {s="тары", n=4, h=1, w=false},
  {s="тері", n=4, h=2, w=false},
  {s="мыз", n=3, h=1, w=false},
  {s="міз", n=3, h=2, w=false},
  {s="ңыз", n=3, h=1, w=false},
  {s="ңіз", n=3, h=2, w=false},
  {s="сы", n=2, h=1, w=true},
  {s="сі", n=2, h=2, w=true},
  {s="ым", n=2, h=1, w=false},
  {s="ім", n=2, h=2, w=false},
  {s="ың", n=2, h=1, w=false},
  {s="ің", n=2, h=2, w=false},
  {s="ы", n=1, h=1, w=true},
  {s="і", n=1, h=2, w=true},
  {s="м", n=1, h=0, w=true},
  {s="ң", n=1, h=0, w=true},
}

M.PLUR = {
  {s="дар", n=3, h=1, w=false},
  {s="дер", n=3, h=2, w=false},
  {s="лар", n=3, h=1, w=false},
  {s="лер", n=3, h=2, w=false},
  {s="тар", n=3, h=1, w=false},
  {s="тер", n=3, h=2, w=false},
}

M.DERIV = {
  {s="ндағы", n=5, h=1, w=false},
  {s="ндегі", n=5, h=2, w=false},
  {s="дағы", n=4, h=1, w=false},
  {s="дегі", n=4, h=2, w=false},
  {s="тағы", n=4, h=1, w=false},
  {s="тегі", n=4, h=2, w=false},
  {s="нікі", n=4, h=0, w=true},
  {s="дікі", n=4, h=0, w=true},
  {s="тікі", n=4, h=0, w=true},
  {s="ырақ", n=4, h=1, w=false},
  {s="ірек", n=4, h=2, w=false},
  {s="рақ", n=3, h=1, w=false},
  {s="рек", n=3, h=2, w=false},
  {s="лау", n=3, h=1, w=false},
  {s="леу", n=3, h=2, w=false},
  {s="дау", n=3, h=1, w=false},
  {s="деу", n=3, h=2, w=false},
  {s="тау", n=3, h=1, w=false},
  {s="теу", n=3, h=2, w=false},
  {s="лы", n=2, h=1, w=true},
  {s="лі", n=2, h=2, w=true},
  {s="лық", n=3, h=1, w=false},
  {s="лік", n=3, h=2, w=false},
  {s="дық", n=3, h=1, w=false},
  {s="дік", n=3, h=2, w=false},
  {s="тық", n=3, h=1, w=false},
  {s="тік", n=3, h=2, w=false},
  {s="ушы", n=3, h=1, w=true},
  {s="уші", n=3, h=2, w=true},
  {s="шы", n=2, h=1, w=true},
  {s="ші", n=2, h=2, w=true},
  {s="ша", n=2, h=1, w=true},
  {s="ше", n=2, h=2, w=true},
  {s="сыз", n=3, h=1, w=false},
  {s="сіз", n=3, h=2, w=false},
  {s="ғы", n=2, h=1, w=true},
  {s="гі", n=2, h=2, w=true},
  {s="ншы", n=3, h=1, w=false},
  {s="нші", n=3, h=2, w=false},
  {s="дай", n=3, h=1, w=false},
  {s="дей", n=3, h=2, w=false},
  {s="тай", n=3, h=1, w=false},
  {s="тей", n=3, h=2, w=false},
  {s="ба", n=2, h=1, w=true},
  {s="бе", n=2, h=2, w=true},
}

M.VPERSON = {
  {s="сыңдар", n=6, h=0, w=false},
  {s="сіңдер", n=6, h=0, w=false},
  {s="сыздар", n=6, h=1, w=false},
  {s="сіздер", n=6, h=2, w=false},
  {s="мыз", n=3, h=1, w=false},
  {s="міз", n=3, h=2, w=false},
  {s="сыз", n=3, h=1, w=false},
  {s="сіз", n=3, h=2, w=false},
  {s="сың", n=3, h=1, w=false},
  {s="сің", n=3, h=2, w=false},
  {s="мын", n=3, h=1, w=false},
  {s="мін", n=3, h=2, w=false},
  {s="бын", n=3, h=1, w=false},
  {s="бін", n=3, h=2, w=false},
  {s="пын", n=3, h=1, w=false},
  {s="пін", n=3, h=2, w=false},
  {s="м", n=1, h=0, w=true},
  {s="ң", n=1, h=0, w=true},
  {s="қ", n=1, h=1, w=true},
  {s="к", n=1, h=2, w=true},
}

M.VTENSE = {
  {s="майды", n=5, h=1, w=false},
  {s="мейді", n=5, h=2, w=false},
  {s="байды", n=5, h=1, w=false},
  {s="бейді", n=5, h=2, w=false},
  {s="пайды", n=5, h=1, w=false},
  {s="пейді", n=5, h=2, w=false},
  {s="атын", n=4, h=1, w=false},
  {s="етін", n=4, h=2, w=false},
  {s="йтын", n=4, h=1, w=false},
  {s="йтін", n=4, h=2, w=false},
  {s="ыпты", n=4, h=1, w=false},
  {s="іпті", n=4, h=2, w=false},
  {s="пты", n=3, h=1, w=false},
  {s="пті", n=3, h=2, w=false},
  {s="йды", n=3, h=0, w=false},
  {s="йді", n=3, h=0, w=false},
  {s="ады", n=3, h=1, w=false},
  {s="еді", n=3, h=2, w=false},
  {s="ған", n=3, h=1, w=false},
  {s="ген", n=3, h=2, w=false},
  {s="қан", n=3, h=1, w=false},
  {s="кен", n=3, h=2, w=false},
  {s="май", n=3, h=1, w=false},
  {s="мей", n=3, h=2, w=false},
  {s="саң", n=3, h=1, w=false},
  {s="сең", n=3, h=2, w=false},
  {s="сақ", n=3, h=1, w=false},
  {s="сек", n=3, h=2, w=false},
  {s="тын", n=3, h=1, w=false},
  {s="тін", n=3, h=2, w=false},
  {s="мақ", n=3, h=1, w=false},
  {s="мек", n=3, h=2, w=false},
  {s="бақ", n=3, h=1, w=false},
  {s="бек", n=3, h=2, w=false},
  {s="пақ", n=3, h=1, w=false},
  {s="пек", n=3, h=2, w=false},
  {s="ды", n=2, h=1, w=false},
  {s="ді", n=2, h=2, w=false},
  {s="ты", n=2, h=1, w=false},
  {s="ті", n=2, h=2, w=false},
  {s="ып", n=2, h=1, w=false},
  {s="іп", n=2, h=2, w=false},
  {s="са", n=2, h=1, w=false},
  {s="се", n=2, h=2, w=false},
  {s="у", n=1, h=0, w=true},
  {s="й", n=1, h=0, w=true},
  {s="а", n=1, h=1, w=true},
  {s="е", n=1, h=2, w=true},
}

M.VNEG = {
  {s="ма", n=2, h=1, w=false},
  {s="ме", n=2, h=2, w=false},
  {s="ба", n=2, h=1, w=false},
  {s="бе", n=2, h=2, w=false},
  {s="па", n=2, h=1, w=false},
  {s="пе", n=2, h=2, w=false},
}

M.VVOICE = {
  {s="қыз", n=3, h=1, w=false},
  {s="кіз", n=3, h=2, w=false},
  {s="ғыз", n=3, h=1, w=false},
  {s="гіз", n=3, h=2, w=false},
  {s="тыр", n=3, h=1, w=false},
  {s="тір", n=3, h=2, w=false},
  {s="дыр", n=3, h=1, w=false},
  {s="дір", n=3, h=2, w=false},
  {s="ыл", n=2, h=1, w=false},
  {s="іл", n=2, h=2, w=false},
  {s="ыс", n=2, h=1, w=false},
  {s="іс", n=2, h=2, w=false},
  {s="ын", n=2, h=1, w=false},
  {s="ін", n=2, h=2, w=false},
}

M.NOUN_LAYERS = {
  {rules=M.PRED,  id=M.LAYER_PRED,  kind=M.KIND_NOMINAL},
  {rules=M.CASE,  id=M.LAYER_CASE,  kind=M.KIND_NOMINAL},
  {rules=M.POSS,  id=M.LAYER_POSS,  kind=M.KIND_NOMINAL},
  {rules=M.PLUR,  id=M.LAYER_PLUR,  kind=M.KIND_NOMINAL},
  {rules=M.DERIV, id=M.LAYER_DERIV, kind=M.KIND_DERIV},
}

M.VERB_LAYERS = {
  {rules=M.VPERSON, id=M.LAYER_VPERSON, kind=M.KIND_VERBAL},
  {rules=M.VTENSE,  id=M.LAYER_VTENSE,  kind=M.KIND_VERBAL},
  {rules=M.VNEG,    id=M.LAYER_VNEG,    kind=M.KIND_VERBAL},
  {rules=M.VVOICE,  id=M.LAYER_VVOICE,  kind=M.KIND_VERBAL},
}

-- Possessive suffixes whose removal can expose a sound change to undo.
M.POSS_VOWEL = {}
for _, s in ipairs({"сы","сі","ы","ым","ымыз","ың","ыңыз","і","ім","іміз","ің","іңіз"}) do
  M.POSS_VOWEL[s] = true
end

return M
