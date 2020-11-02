--- The qrcode library is licensed under the 3-clause BSD license (aka "new BSD")
--- To get in contact with the author, mail to <gundlach@speedata.de>.
---
--- Please report bugs on the [github project page](http://speedata.github.com/luaqrcode/).
-- Copyright (c) 2012-2020, Patrick Gundlach and contributors, see https://github.com/speedata/luaqrcode
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions are met:
--     * Redistributions of source code must retain the above copyright
--       notice, this list of conditions and the following disclaimer.
--     * Redistributions in binary form must reproduce the above copyright
--       notice, this list of conditions and the following disclaimer in the
--       documentation and/or other materials provided with the distribution.
--     * Neither the name of the <organization> nor the
--       names of its contributors may be used to endorse or promote products
--       derived from this software without specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
-- DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
-- DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
-- (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
-- LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
-- ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
-- (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
-- SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


--- Overall workflow
--- ================
--- The steps to generate the qrcode, assuming we already have the codeword:
---
--- 1. Determine version, ec level and mode (=encoding) for codeword
--- 1. Encode data
--- 1. Arrange data and calculate error correction code
--- 1. Generate 8 matrices with different masks and calculate the penalty
--- 1. Return qrcode with least penalty
---
--- Each step is of course more or less complex and needs further description

--- Helper functions
--- ================
---
--- We start with some helper functions

-- To calculate xor we need to do that bitwise. This helper table speeds up the num-to-bit
-- part a bit (no pun intended)
local cclxvi = {[0] = {0,0,0,0,0,0,0,0}, {1,0,0,0,0,0,0,0}, {0,1,0,0,0,0,0,0}, {1,1,0,0,0,0,0,0},
{0,0,1,0,0,0,0,0}, {1,0,1,0,0,0,0,0}, {0,1,1,0,0,0,0,0}, {1,1,1,0,0,0,0,0},
{0,0,0,1,0,0,0,0}, {1,0,0,1,0,0,0,0}, {0,1,0,1,0,0,0,0}, {1,1,0,1,0,0,0,0},
{0,0,1,1,0,0,0,0}, {1,0,1,1,0,0,0,0}, {0,1,1,1,0,0,0,0}, {1,1,1,1,0,0,0,0},
{0,0,0,0,1,0,0,0}, {1,0,0,0,1,0,0,0}, {0,1,0,0,1,0,0,0}, {1,1,0,0,1,0,0,0},
{0,0,1,0,1,0,0,0}, {1,0,1,0,1,0,0,0}, {0,1,1,0,1,0,0,0}, {1,1,1,0,1,0,0,0},
{0,0,0,1,1,0,0,0}, {1,0,0,1,1,0,0,0}, {0,1,0,1,1,0,0,0}, {1,1,0,1,1,0,0,0},
{0,0,1,1,1,0,0,0}, {1,0,1,1,1,0,0,0}, {0,1,1,1,1,0,0,0}, {1,1,1,1,1,0,0,0},
{0,0,0,0,0,1,0,0}, {1,0,0,0,0,1,0,0}, {0,1,0,0,0,1,0,0}, {1,1,0,0,0,1,0,0},
{0,0,1,0,0,1,0,0}, {1,0,1,0,0,1,0,0}, {0,1,1,0,0,1,0,0}, {1,1,1,0,0,1,0,0},
{0,0,0,1,0,1,0,0}, {1,0,0,1,0,1,0,0}, {0,1,0,1,0,1,0,0}, {1,1,0,1,0,1,0,0},
{0,0,1,1,0,1,0,0}, {1,0,1,1,0,1,0,0}, {0,1,1,1,0,1,0,0}, {1,1,1,1,0,1,0,0},
{0,0,0,0,1,1,0,0}, {1,0,0,0,1,1,0,0}, {0,1,0,0,1,1,0,0}, {1,1,0,0,1,1,0,0},
{0,0,1,0,1,1,0,0}, {1,0,1,0,1,1,0,0}, {0,1,1,0,1,1,0,0}, {1,1,1,0,1,1,0,0},
{0,0,0,1,1,1,0,0}, {1,0,0,1,1,1,0,0}, {0,1,0,1,1,1,0,0}, {1,1,0,1,1,1,0,0},
{0,0,1,1,1,1,0,0}, {1,0,1,1,1,1,0,0}, {0,1,1,1,1,1,0,0}, {1,1,1,1,1,1,0,0},
{0,0,0,0,0,0,1,0}, {1,0,0,0,0,0,1,0}, {0,1,0,0,0,0,1,0}, {1,1,0,0,0,0,1,0},
{0,0,1,0,0,0,1,0}, {1,0,1,0,0,0,1,0}, {0,1,1,0,0,0,1,0}, {1,1,1,0,0,0,1,0},
{0,0,0,1,0,0,1,0}, {1,0,0,1,0,0,1,0}, {0,1,0,1,0,0,1,0}, {1,1,0,1,0,0,1,0},
{0,0,1,1,0,0,1,0}, {1,0,1,1,0,0,1,0}, {0,1,1,1,0,0,1,0}, {1,1,1,1,0,0,1,0},
{0,0,0,0,1,0,1,0}, {1,0,0,0,1,0,1,0}, {0,1,0,0,1,0,1,0}, {1,1,0,0,1,0,1,0},
{0,0,1,0,1,0,1,0}, {1,0,1,0,1,0,1,0}, {0,1,1,0,1,0,1,0}, {1,1,1,0,1,0,1,0},
{0,0,0,1,1,0,1,0}, {1,0,0,1,1,0,1,0}, {0,1,0,1,1,0,1,0}, {1,1,0,1,1,0,1,0},
{0,0,1,1,1,0,1,0}, {1,0,1,1,1,0,1,0}, {0,1,1,1,1,0,1,0}, {1,1,1,1,1,0,1,0},
{0,0,0,0,0,1,1,0}, {1,0,0,0,0,1,1,0}, {0,1,0,0,0,1,1,0}, {1,1,0,0,0,1,1,0},
{0,0,1,0,0,1,1,0}, {1,0,1,0,0,1,1,0}, {0,1,1,0,0,1,1,0}, {1,1,1,0,0,1,1,0},
{0,0,0,1,0,1,1,0}, {1,0,0,1,0,1,1,0}, {0,1,0,1,0,1,1,0}, {1,1,0,1,0,1,1,0},
{0,0,1,1,0,1,1,0}, {1,0,1,1,0,1,1,0}, {0,1,1,1,0,1,1,0}, {1,1,1,1,0,1,1,0},
{0,0,0,0,1,1,1,0}, {1,0,0,0,1,1,1,0}, {0,1,0,0,1,1,1,0}, {1,1,0,0,1,1,1,0},
{0,0,1,0,1,1,1,0}, {1,0,1,0,1,1,1,0}, {0,1,1,0,1,1,1,0}, {1,1,1,0,1,1,1,0},
{0,0,0,1,1,1,1,0}, {1,0,0,1,1,1,1,0}, {0,1,0,1,1,1,1,0}, {1,1,0,1,1,1,1,0},
{0,0,1,1,1,1,1,0}, {1,0,1,1,1,1,1,0}, {0,1,1,1,1,1,1,0}, {1,1,1,1,1,1,1,0},
{0,0,0,0,0,0,0,1}, {1,0,0,0,0,0,0,1}, {0,1,0,0,0,0,0,1}, {1,1,0,0,0,0,0,1},
{0,0,1,0,0,0,0,1}, {1,0,1,0,0,0,0,1}, {0,1,1,0,0,0,0,1}, {1,1,1,0,0,0,0,1},
{0,0,0,1,0,0,0,1}, {1,0,0,1,0,0,0,1}, {0,1,0,1,0,0,0,1}, {1,1,0,1,0,0,0,1},
{0,0,1,1,0,0,0,1}, {1,0,1,1,0,0,0,1}, {0,1,1,1,0,0,0,1}, {1,1,1,1,0,0,0,1},
{0,0,0,0,1,0,0,1}, {1,0,0,0,1,0,0,1}, {0,1,0,0,1,0,0,1}, {1,1,0,0,1,0,0,1},
{0,0,1,0,1,0,0,1}, {1,0,1,0,1,0,0,1}, {0,1,1,0,1,0,0,1}, {1,1,1,0,1,0,0,1},
{0,0,0,1,1,0,0,1}, {1,0,0,1,1,0,0,1}, {0,1,0,1,1,0,0,1}, {1,1,0,1,1,0,0,1},
{0,0,1,1,1,0,0,1}, {1,0,1,1,1,0,0,1}, {0,1,1,1,1,0,0,1}, {1,1,1,1,1,0,0,1},
{0,0,0,0,0,1,0,1}, {1,0,0,0,0,1,0,1}, {0,1,0,0,0,1,0,1}, {1,1,0,0,0,1,0,1},
{0,0,1,0,0,1,0,1}, {1,0,1,0,0,1,0,1}, {0,1,1,0,0,1,0,1}, {1,1,1,0,0,1,0,1},
{0,0,0,1,0,1,0,1}, {1,0,0,1,0,1,0,1}, {0,1,0,1,0,1,0,1}, {1,1,0,1,0,1,0,1},
{0,0,1,1,0,1,0,1}, {1,0,1,1,0,1,0,1}, {0,1,1,1,0,1,0,1}, {1,1,1,1,0,1,0,1},
{0,0,0,0,1,1,0,1}, {1,0,0,0,1,1,0,1}, {0,1,0,0,1,1,0,1}, {1,1,0,0,1,1,0,1},
{0,0,1,0,1,1,0,1}, {1,0,1,0,1,1,0,1}, {0,1,1,0,1,1,0,1}, {1,1,1,0,1,1,0,1},
{0,0,0,1,1,1,0,1}, {1,0,0,1,1,1,0,1}, {0,1,0,1,1,1,0,1}, {1,1,0,1,1,1,0,1},
{0,0,1,1,1,1,0,1}, {1,0,1,1,1,1,0,1}, {0,1,1,1,1,1,0,1}, {1,1,1,1,1,1,0,1},
{0,0,0,0,0,0,1,1}, {1,0,0,0,0,0,1,1}, {0,1,0,0,0,0,1,1}, {1,1,0,0,0,0,1,1},
{0,0,1,0,0,0,1,1}, {1,0,1,0,0,0,1,1}, {0,1,1,0,0,0,1,1}, {1,1,1,0,0,0,1,1},
{0,0,0,1,0,0,1,1}, {1,0,0,1,0,0,1,1}, {0,1,0,1,0,0,1,1}, {1,1,0,1,0,0,1,1},
{0,0,1,1,0,0,1,1}, {1,0,1,1,0,0,1,1}, {0,1,1,1,0,0,1,1}, {1,1,1,1,0,0,1,1},
{0,0,0,0,1,0,1,1}, {1,0,0,0,1,0,1,1}, {0,1,0,0,1,0,1,1}, {1,1,0,0,1,0,1,1},
{0,0,1,0,1,0,1,1}, {1,0,1,0,1,0,1,1}, {0,1,1,0,1,0,1,1}, {1,1,1,0,1,0,1,1},
{0,0,0,1,1,0,1,1}, {1,0,0,1,1,0,1,1}, {0,1,0,1,1,0,1,1}, {1,1,0,1,1,0,1,1},
{0,0,1,1,1,0,1,1}, {1,0,1,1,1,0,1,1}, {0,1,1,1,1,0,1,1}, {1,1,1,1,1,0,1,1},
{0,0,0,0,0,1,1,1}, {1,0,0,0,0,1,1,1}, {0,1,0,0,0,1,1,1}, {1,1,0,0,0,1,1,1},
{0,0,1,0,0,1,1,1}, {1,0,1,0,0,1,1,1}, {0,1,1,0,0,1,1,1}, {1,1,1,0,0,1,1,1},
{0,0,0,1,0,1,1,1}, {1,0,0,1,0,1,1,1}, {0,1,0,1,0,1,1,1}, {1,1,0,1,0,1,1,1},
{0,0,1,1,0,1,1,1}, {1,0,1,1,0,1,1,1}, {0,1,1,1,0,1,1,1}, {1,1,1,1,0,1,1,1},
{0,0,0,0,1,1,1,1}, {1,0,0,0,1,1,1,1}, {0,1,0,0,1,1,1,1}, {1,1,0,0,1,1,1,1},
{0,0,1,0,1,1,1,1}, {1,0,1,0,1,1,1,1}, {0,1,1,0,1,1,1,1}, {1,1,1,0,1,1,1,1},
{0,0,0,1,1,1,1,1}, {1,0,0,1,1,1,1,1}, {0,1,0,1,1,1,1,1}, {1,1,0,1,1,1,1,1},
{0,0,1,1,1,1,1,1}, {1,0,1,1,1,1,1,1}, {0,1,1,1,1,1,1,1}, {1,1,1,1,1,1,1,1}}

-- Return a number that is the result of interpreting the table tbl (msb first)
local function tbl_to_number(tbl)
    local n = #tbl
    local rslt = 0
    local power = 1
    for i = 1, n do
        rslt = rslt + tbl[i]*power
        power = power*2
    end
    return rslt
end

-- Calculate bitwise xor of bytes m and n. 0 <= m,n <= 256.
local function bit_xor(m, n)
    local tbl_m = cclxvi[m]
    local tbl_n = cclxvi[n]
    local tbl = {}
    for i = 1, 8 do
        if(tbl_m[i] ~= tbl_n[i]) then
            tbl[i] = 1
        else
            tbl[i] = 0
        end
    end
    return tbl_to_number(tbl)
end

-- Return the binary representation of the number x with the width of `digits`.
local function binary(x,digits)
  local s=string.format("%o",x)
  local a={["0"]="000",["1"]="001", ["2"]="010",["3"]="011",
           ["4"]="100",["5"]="101", ["6"]="110",["7"]="111"}
  s=string.gsub(s,"(.)",function (d) return a[d] end)
  -- remove leading 0s
  s = string.gsub(s,"^0*(.*)$","%1")
  local fmtstring = string.format("%%%ds",digits)
  local ret = string.format(fmtstring,s)
  return string.gsub(ret," ","0")
end

-- A small helper function for add_typeinfo_to_matrix() and add_version_information()
-- Add a 2 (black by default) / -2 (blank by default) to the matrix at position x,y
-- depending on the bitstring (size 1!) where "0"=blank and "1"=black.
local function fill_matrix_position(matrix,bitstring,x,y)
    if bitstring == "1" then
        matrix[x][y] = 2
    else
        matrix[x][y] = -2
    end
end


--- Step 1: Determine version, ec level and mode for codeword
--- ========================================================
---
--- First we need to find out the version (= size) of the QR code. This depends on
--- the input data (the mode to be used), the requested error correction level
--- (normally we use the maximum level that fits into the minimal size).

-- Return the mode for the given string `str`.
-- See table 2 of the spec. We only support mode 1, 2 and 4.
-- That is: numeric, alaphnumeric and binary.
local function get_mode( str )
    local mode
    if string.match(str,"^[0-9]+$") then
        return 1
    elseif string.match(str,"^[0-9A-Z $%%*./:+-]+$") then
        return 2
    else
        return 4
    end
    assert(false,"never reached")
    return nil
end



--- Capacity of QR codes
--- --------------------
--- The capacity is calculated as follow: \\(\text{Number of data bits} = \text{number of codewords} * 8\\).
--- The number of data bits is now reduced by 4 (the mode indicator) and the length string,
--- that varies between 8 and 16, depending on the version and the mode (see method `get_length()`). The
--- remaining capacity is multiplied by the amount of data per bit string (numeric: 3, alphanumeric: 2, other: 1)
--- and divided by the length of the bit string (numeric: 10, alphanumeric: 11, binary: 8, kanji: 13).
--- Then the floor function is applied to the result:
--- $$\Big\lfloor \frac{( \text{#data bits} - 4 - \text{length string}) * \text{data per bit string}}{\text{length of the bit string}} \Big\rfloor$$
---
--- There is one problem remaining. The length string depends on the version,
--- and the version depends on the length string. But we take this into account when calculating the
--- the capacity, so this is not really a problem here.

-- The capacity (number of codewords) of each version (1-40) for error correction levels 1-4 (LMQH).
-- The higher the ec level, the lower the capacity of the version. Taken from spec, tables 7-11.
local capacity = {
  {  19,   16,   13,    9},{  34,   28,   22,   16},{  55,   44,   34,   26},{  80,   64,   48,   36},
  { 108,   86,   62,   46},{ 136,  108,   76,   60},{ 156,  124,   88,   66},{ 194,  154,  110,   86},
  { 232,  182,  132,  100},{ 274,  216,  154,  122},{ 324,  254,  180,  140},{ 370,  290,  206,  158},
  { 428,  334,  244,  180},{ 461,  365,  261,  197},{ 523,  415,  295,  223},{ 589,  453,  325,  253},
  { 647,  507,  367,  283},{ 721,  563,  397,  313},{ 795,  627,  445,  341},{ 861,  669,  485,  385},
  { 932,  714,  512,  406},{1006,  782,  568,  442},{1094,  860,  614,  464},{1174,  914,  664,  514},
  {1276, 1000,  718,  538},{1370, 1062,  754,  596},{1468, 1128,  808,  628},{1531, 1193,  871,  661},
  {1631, 1267,  911,  701},{1735, 1373,  985,  745},{1843, 1455, 1033,  793},{1955, 1541, 1115,  845},
  {2071, 1631, 1171,  901},{2191, 1725, 1231,  961},{2306, 1812, 1286,  986},{2434, 1914, 1354, 1054},
  {2566, 1992, 1426, 1096},{2702, 2102, 1502, 1142},{2812, 2216, 1582, 1222},{2956, 2334, 1666, 1276}}


--- Return the smallest version for this codeword. If `requested_ec_level` is supplied,
--- then the ec level (LMQH - 1,2,3,4) must be at least the requested level.
-- mode = 1,2,4,8
local function get_version_eclevel(len,mode,requested_ec_level)
    local local_mode = mode
    if mode == 4 then
        local_mode = 3
    elseif mode == 8 then
        local_mode = 4
    end
    assert( local_mode <= 4 )

    local bytes, bits, digits, modebits, c
    local tab = { {10,9,8,8},{12,11,16,10},{14,13,16,12} }
    local minversion = 40
    local maxec_level = requested_ec_level or 1
    local min,max = 1, 4
    if requested_ec_level and requested_ec_level >= 1 and requested_ec_level <= 4 then
        min = requested_ec_level
        max = requested_ec_level
    end
    for ec_level=min,max do
        for version=1,#capacity do
            bits = capacity[version][ec_level] * 8
            bits = bits - 4 -- the mode indicator
            if version < 10 then
                digits = tab[1][local_mode]
            elseif version < 27 then
                digits = tab[2][local_mode]
            elseif version <= 40 then
                digits = tab[3][local_mode]
            end
            modebits = bits - digits
            if local_mode == 1 then -- numeric
                c = math.floor(modebits * 3 / 10)
            elseif local_mode == 2 then -- alphanumeric
                c = math.floor(modebits * 2 / 11)
            elseif local_mode == 3 then -- binary
                c = math.floor(modebits * 1 / 8)
            else
                c = math.floor(modebits * 1 / 13)
            end
            if c >= len then
                if version <= minversion then
                    minversion = version
                    maxec_level = ec_level
                end
                break
            end
        end
    end
    return minversion, maxec_level
end

-- Return a bit string of 0s and 1s that includes the length of the code string.
-- The modes are numeric = 1, alphanumeric = 2, binary = 4, and japanese = 8
local function get_length(str,version,mode)
    local i = mode
    if mode == 4 then
        i = 3
    elseif mode == 8 then
        i = 4
    end
    assert( i <= 4 )
    local tab = { {10,9,8,8},{12,11,16,10},{14,13,16,12} }
    local digits
    if version < 10 then
        digits = tab[1][i]
    elseif version < 27 then
        digits = tab[2][i]
    elseif version <= 40 then
        digits = tab[3][i]
    else
        assert(false, "get_length, version > 40 not supported")
    end
    local len = binary(#str,digits)
    return len
end

--- If the `requested_ec_level` or the `mode` are provided, this will be used if possible.
--- The mode depends on the characters used in the string `str`. It seems to be
--- possible to split the QR code to handle multiple modes, but we don't do that.
local function get_version_eclevel_mode_bistringlength(str,requested_ec_level,mode)
    local local_mode
    if mode then
        assert(false,"not implemented")
        -- check if the mode is OK for the string
        local_mode = mode
    else
        local_mode = get_mode(str)
    end
    local version, ec_level
    version, ec_level = get_version_eclevel(#str,local_mode,requested_ec_level)
    local length_string = get_length(str,version,local_mode)
    return version,ec_level,binary(local_mode,4),local_mode,length_string
end

--- Step 2: Encode data
--- ===================

--- There are several ways to encode the data. We currently support only numeric, alphanumeric and binary.
--- We already chose the encoding (a.k.a. mode) in the first step, so we need to apply the mode to the
--- codeword.
---
--- **Numeric**: take three digits and encode them in 10 bits
--- **Alphanumeric**: take two characters and encode them in 11 bits
--- **Binary**: take one octet and encode it in 8 bits

local asciitbl = {
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,  -- 0x01-0x0f
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,  -- 0x10-0x1f
    36, -1, -1, -1, 37, 38, -1, -1, -1, -1, 39, 40, -1, 41, 42, 43,  -- 0x20-0x2f
     0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 44, -1, -1, -1, -1, -1,  -- 0x30-0x3f
    -1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,  -- 0x40-0x4f
    25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, -1, -1, -1, -1, -1,  -- 0x50-0x5f
  }

-- Return a binary representation of the numeric string `str`. This must contain only digits 0-9.
local function encode_string_numeric(str)
    local bitstring = ""
    local int
    string.gsub(str,"..?.?",function(a)
        int = tonumber(a)
        if #a == 3 then
            bitstring = bitstring .. binary(int,10)
        elseif #a == 2 then
            bitstring = bitstring .. binary(int,7)
        else
            bitstring = bitstring .. binary(int,4)
        end
    end)
    return bitstring
end

-- Return a binary representation of the alphanumeric string `str`. This must contain only
-- digits 0-9, uppercase letters A-Z, space and the following chars: $%*./:+-.
local function encode_string_ascii(str)
    local bitstring = ""
    local int
    local b1, b2
    string.gsub(str,"..?",function(a)
        if #a == 2 then
            b1 = asciitbl[string.byte(string.sub(a,1,1))]
            b2 = asciitbl[string.byte(string.sub(a,2,2))]
            int = b1 * 45 + b2
            bitstring = bitstring .. binary(int,11)
        else
            int = asciitbl[string.byte(a)]
            bitstring = bitstring .. binary(int,6)
        end
      end)
    return bitstring
end

-- Return a bitstring representing string str in binary mode.
-- We don't handle UTF-8 in any special way because we assume the
-- scanner recognizes UTF-8 and displays it correctly.
local function encode_string_binary(str)
    local ret = {}
    string.gsub(str,".",function(x)
        ret[#ret + 1] = binary(string.byte(x),8)
    end)
    return table.concat(ret)
end

-- Return a bitstring representing string str in the given mode.
local function encode_data(str,mode)
    if mode == 1 then
        return encode_string_numeric(str)
    elseif mode == 2 then
        return encode_string_ascii(str)
    elseif mode == 4 then
        return encode_string_binary(str)
    else
        assert(false,"not implemented yet")
    end
end

-- Encoding the codeword is not enough. We need to make sure that
-- the length of the binary string is equal to the number of codewords of the version.
local function add_pad_data(version,ec_level,data)
    local count_to_pad, missing_digits
    local cpty = capacity[version][ec_level] * 8
    count_to_pad = math.min(4,cpty - #data)
    if count_to_pad > 0 then
        data = data .. string.rep("0",count_to_pad)
    end
    if math.fmod(#data,8) ~= 0 then
        missing_digits = 8 - math.fmod(#data,8)
        data = data .. string.rep("0",missing_digits)
    end
    assert(math.fmod(#data,8) == 0)
    -- add "11101100" and "00010001" until enough data
    while #data < cpty do
        data = data .. "11101100"
        if #data < cpty then
            data = data .. "00010001"
        end
    end
    return data
end



--- Step 3: Organize data and calculate error correction code
--- =======================================================
--- The data in the qrcode is not encoded linearly. For example code 5-H has four blocks, the first two blocks
--- contain 11 codewords and 22 error correction codes each, the second block contain 12 codewords and 22 ec codes each.
--- We just take the table from the spec and don't calculate the blocks ourself. The table `ecblocks` contains this info.
---
--- During the phase of splitting the data into codewords, we do the calculation for error correction codes. This step involves
--- polynomial division. Find a math book from school and follow the code here :)

--- ### Reed Solomon error correction
--- Now this is the slightly ugly part of the error correction. We start with log/antilog tables
-- https://codyplanteen.com/assets/rs/gf256_log_antilog.pdf
local alpha_int = {
    [0] = 1,
      2,   4,   8,  16,  32,  64, 128,  29,  58, 116, 232, 205, 135,  19,  38,  76,
    152,  45,  90, 180, 117, 234, 201, 143,   3,   6,  12,  24,  48,  96, 192, 157,
     39,  78, 156,  37,  74, 148,  53, 106, 212, 181, 119, 238, 193, 159,  35,  70,
    140,   5,  10,  20,  40,  80, 160,  93, 186, 105, 210, 185, 111, 222, 161,  95,
    190,  97, 194, 153,  47,  94, 188, 101, 202, 137,  15,  30,  60, 120, 240, 253,
    231, 211, 187, 107, 214, 177, 127, 254, 225, 223, 163,  91, 182, 113, 226, 217,
    175,  67, 134,  17,  34,  68, 136,  13,  26,  52, 104, 208, 189, 103, 206, 129,
     31,  62, 124, 248, 237, 199, 147,  59, 118, 236, 197, 151,  51, 102, 204, 133,
     23,  46,  92, 184, 109, 218, 169,  79, 158,  33,  66, 132,  21,  42,  84, 168,
     77, 154,  41,  82, 164,  85, 170,  73, 146,  57, 114, 228, 213, 183, 115, 230,
    209, 191,  99, 198, 145,  63, 126, 252, 229, 215, 179, 123, 246, 241, 255, 227,
    219, 171,  75, 150,  49,  98, 196, 149,  55, 110, 220, 165,  87, 174,  65, 130,
     25,  50, 100, 200, 141,   7,  14,  28,  56, 112, 224, 221, 167,  83, 166,  81,
    162,  89, 178, 121, 242, 249, 239, 195, 155,  43,  86, 172,  69, 138,   9,  18,
     36,  72, 144,  61, 122, 244, 245, 247, 243, 251, 235, 203, 139,  11,  22,  44,
     88, 176, 125, 250, 233, 207, 131,  27,  54, 108, 216, 173,  71, 142,   0,   0
}

local int_alpha = {
    [0] = 256, -- special value
    0,   1,  25,   2,  50,  26, 198,   3, 223,  51, 238,  27, 104, 199,  75,   4,
    100, 224,  14,  52, 141, 239, 129,  28, 193, 105, 248, 200,   8,  76, 113,   5,
    138, 101,  47, 225,  36,  15,  33,  53, 147, 142, 218, 240,  18, 130,  69,  29,
    181, 194, 125, 106,  39, 249, 185, 201, 154,   9, 120,  77, 228, 114, 166,   6,
    191, 139,  98, 102, 221,  48, 253, 226, 152,  37, 179,  16, 145,  34, 136,  54,
    208, 148, 206, 143, 150, 219, 189, 241, 210,  19,  92, 131,  56,  70,  64,  30,
     66, 182, 163, 195,  72, 126, 110, 107,  58,  40,  84, 250, 133, 186,  61, 202,
     94, 155, 159,  10,  21, 121,  43,  78, 212, 229, 172, 115, 243, 167,  87,   7,
    112, 192, 247, 140, 128,  99,  13, 103,  74, 222, 237,  49, 197, 254,  24, 227,
    165, 153, 119,  38, 184, 180, 124,  17,  68, 146, 217,  35,  32, 137,  46,  55,
     63, 209,  91, 149, 188, 207, 205, 144, 135, 151, 178, 220, 252, 190,  97, 242,
     86, 211, 171,  20,  42,  93, 158, 132,  60,  57,  83,  71, 109,  65, 162,  31,
     45,  67, 216, 183, 123, 164, 118, 196,  23,  73, 236, 127,  12, 111, 246, 108,
    161,  59,  82,  41, 157,  85, 170, 251,  96, 134, 177, 187, 204,  62,  90, 203,
     89,  95, 176, 156, 169, 160,  81,  11, 245,  22, 235, 122, 117,  44, 215,  79,
    174, 213, 233, 230, 231, 173, 232, 116, 214, 244, 234, 168,  80,  88, 175
}

-- We only need the polynomial generators for block sizes 7, 10, 13, 15, 16, 17, 18, 20, 22, 24, 26, 28, and 30. Version
-- 2 of the qr codes don't need larger ones (as opposed to version 1). The table has the format x^1*ɑ^21 + x^2*a^102 ...
local generator_polynomial = {
     [7] = { 21, 102, 238, 149, 146, 229,  87,   0},
    [10] = { 45,  32,  94,  64,  70, 118,  61,  46,  67, 251,   0 },
    [13] = { 78, 140, 206, 218, 130, 104, 106, 100,  86, 100, 176, 152,  74,   0 },
    [15] = {105,  99,   5, 124, 140, 237,  58,  58,  51,  37, 202,  91,  61, 183,   8,   0},
    [16] = {120, 225, 194, 182, 169, 147, 191,  91,   3,  76, 161, 102, 109, 107, 104, 120,   0},
    [17] = {136, 163, 243,  39, 150,  99,  24, 147, 214, 206, 123, 239,  43,  78, 206, 139,  43,   0},
    [18] = {153,  96,  98,   5, 179, 252, 148, 152, 187,  79, 170, 118,  97, 184,  94, 158, 234, 215,   0},
    [20] = {190, 188, 212, 212, 164, 156, 239,  83, 225, 221, 180, 202, 187,  26, 163,  61,  50,  79,  60,  17,   0},
    [22] = {231, 165, 105, 160, 134, 219,  80,  98, 172,   8,  74, 200,  53, 221, 109,  14, 230,  93, 242, 247, 171, 210,   0},
    [24] = { 21, 227,  96,  87, 232, 117,   0, 111, 218, 228, 226, 192, 152, 169, 180, 159, 126, 251, 117, 211,  48, 135, 121, 229,   0},
    [26] = { 70, 218, 145, 153, 227,  48, 102,  13, 142, 245,  21, 161,  53, 165,  28, 111, 201, 145,  17, 118, 182, 103,   2, 158, 125, 173,   0},
    [28] = {123,   9,  37, 242, 119, 212, 195,  42,  87, 245,  43,  21, 201, 232,  27, 205, 147, 195, 190, 110, 180, 108, 234, 224, 104, 200, 223, 168,   0},
    [30] = {180, 192,  40, 238, 216, 251,  37, 156, 130, 224, 193, 226, 173,  42, 125, 222,  96, 239,  86, 110,  48,  50, 182, 179,  31, 216, 152, 145, 173, 41, 0}}


-- Turn a binary string of length 8*x into a table size x of numbers.
local function convert_bitstring_to_bytes(data)
    local msg = {}
    local tab = string.gsub(data,"(........)",function(x)
        msg[#msg+1] = tonumber(x,2)
        end)
    return msg
end

-- Return a table that has 0's in the first entries and then the alpha
-- representation of the generator polynominal
local function get_generator_polynominal_adjusted(num_ec_codewords,highest_exponent)
    local gp_alpha = {[0]=0}
    for i=0,highest_exponent - num_ec_codewords - 1 do
        gp_alpha[i] = 0
    end
    local gp = generator_polynomial[num_ec_codewords]
    for i=1,num_ec_codewords + 1 do
        gp_alpha[highest_exponent - num_ec_codewords + i - 1] = gp[i]
    end
    return gp_alpha
end

--- These converter functions use the log/antilog table above.
--- We could have created the table programatically, but I like fixed tables.
-- Convert polynominal in int notation to alpha notation.
local function convert_to_alpha( tab )
    local new_tab = {}
    for i=0,#tab do
        new_tab[i] = int_alpha[tab[i]]
    end
    return new_tab
end

-- Convert polynominal in alpha notation to int notation.
local function convert_to_int(tab,len_message)
    local new_tab = {}
    for i=0,#tab do
        new_tab[i] = alpha_int[tab[i]]
    end
    return new_tab
end

-- That's the heart of the error correction calculation.
local function calculate_error_correction(data,num_ec_codewords)
    local mp
    if type(data)=="string" then
        mp = convert_bitstring_to_bytes(data)
    elseif type(data)=="table" then
        mp = data
    else
        assert(false,"Unknown type for data: %s",type(data))
    end
    local len_message = #mp

    local highest_exponent = len_message + num_ec_codewords - 1
    local gp_alpha,tmp
    local he
    local gp_int = {}
    local mp_int,mp_alpha = {},{}
    -- create message shifted to left (highest exponent)
    for i=1,len_message do
        mp_int[highest_exponent - i + 1] = mp[i]
    end
    for i=1,highest_exponent - len_message do
        mp_int[i] = 0
    end
    mp_int[0] = 0

    mp_alpha = convert_to_alpha(mp_int)

    while highest_exponent >= num_ec_codewords do
        gp_alpha = get_generator_polynominal_adjusted(num_ec_codewords,highest_exponent)

        -- Multiply generator polynomial by first coefficient of the above polynomial

        -- take the highest exponent from the message polynom (alpha) and add
        -- it to the generator polynom
        local exp = mp_alpha[highest_exponent]
        for i=highest_exponent,highest_exponent - num_ec_codewords,-1 do
            if exp ~= 256 then
                if gp_alpha[i] + exp >= 255 then
                    gp_alpha[i] = math.fmod(gp_alpha[i] + exp,255)
                else
                    gp_alpha[i] = gp_alpha[i] + exp
                end
            else
                gp_alpha[i] = 256
            end
        end
        for i=highest_exponent - num_ec_codewords - 1,0,-1 do
            gp_alpha[i] = 256
        end

        gp_int = convert_to_int(gp_alpha)
        mp_int = convert_to_int(mp_alpha)


        tmp = {}
        for i=highest_exponent,0,-1 do
            tmp[i] = bit_xor(gp_int[i],mp_int[i])
        end
        -- remove leading 0's
        he = highest_exponent
        for i=he,0,-1 do
            -- We need to stop if the length of the codeword is matched
            if i < num_ec_codewords then break end
            if tmp[i] == 0 then
                tmp[i] = nil
                highest_exponent = highest_exponent - 1
            else
                break
            end
        end
        mp_int = tmp
        mp_alpha = convert_to_alpha(mp_int)
    end
    local ret = {}

    -- reverse data
    for i=#mp_int,0,-1 do
        ret[#ret + 1] = mp_int[i]
    end
    return ret
end

--- #### Arranging the data
--- Now we arrange the data into smaller chunks. This table is taken from the spec.
-- ecblocks has 40 entries, one for each version. Each version entry has 4 entries, for each LMQH
-- ec level. Each entry has two or four fields, the odd files are the number of repetitions for the
-- folowing block info. The first entry of the block is the total number of codewords in the block,
-- the second entry is the number of data codewords. The third is not important.
local ecblocks = {
  {{  1,{ 26, 19, 2}                 },   {  1,{26,16, 4}},                  {  1,{26,13, 6}},                  {  1, {26, 9, 8}               }},
  {{  1,{ 44, 34, 4}                 },   {  1,{44,28, 8}},                  {  1,{44,22,11}},                  {  1, {44,16,14}               }},
  {{  1,{ 70, 55, 7}                 },   {  1,{70,44,13}},                  {  2,{35,17, 9}},                  {  2, {35,13,11}               }},
  {{  1,{100, 80,10}                 },   {  2,{50,32, 9}},                  {  2,{50,24,13}},                  {  4, {25, 9, 8}               }},
  {{  1,{134,108,13}                 },   {  2,{67,43,12}},                  {  2,{33,15, 9},  2,{34,16, 9}},   {  2, {33,11,11},  2,{34,12,11}}},
  {{  2,{ 86, 68, 9}                 },   {  4,{43,27, 8}},                  {  4,{43,19,12}},                  {  4, {43,15,14}               }},
  {{  2,{ 98, 78,10}                 },   {  4,{49,31, 9}},                  {  2,{32,14, 9},  4,{33,15, 9}},   {  4, {39,13,13},  1,{40,14,13}}},
  {{  2,{121, 97,12}                 },   {  2,{60,38,11},  2,{61,39,11}},   {  4,{40,18,11},  2,{41,19,11}},   {  4, {40,14,13},  2,{41,15,13}}},
  {{  2,{146,116,15}                 },   {  3,{58,36,11},  2,{59,37,11}},   {  4,{36,16,10},  4,{37,17,10}},   {  4, {36,12,12},  4,{37,13,12}}},
  {{  2,{ 86, 68, 9},  2,{ 87, 69, 9}},   {  4,{69,43,13},  1,{70,44,13}},   {  6,{43,19,12},  2,{44,20,12}},   {  6, {43,15,14},  2,{44,16,14}}},
  {{  4,{101, 81,10}                 },   {  1,{80,50,15},  4,{81,51,15}},   {  4,{50,22,14},  4,{51,23,14}},   {  3, {36,12,12},  8,{37,13,12}}},
  {{  2,{116, 92,12},  2,{117, 93,12}},   {  6,{58,36,11},  2,{59,37,11}},   {  4,{46,20,13},  6,{47,21,13}},   {  7, {42,14,14},  4,{43,15,14}}},
  {{  4,{133,107,13}                 },   {  8,{59,37,11},  1,{60,38,11}},   {  8,{44,20,12},  4,{45,21,12}},   { 12, {33,11,11},  4,{34,12,11}}},
  {{  3,{145,115,15},  1,{146,116,15}},   {  4,{64,40,12},  5,{65,41,12}},   { 11,{36,16,10},  5,{37,17,10}},   { 11, {36,12,12},  5,{37,13,12}}},
  {{  5,{109, 87,11},  1,{110, 88,11}},   {  5,{65,41,12},  5,{66,42,12}},   {  5,{54,24,15},  7,{55,25,15}},   { 11, {36,12,12},  7,{37,13,12}}},
  {{  5,{122, 98,12},  1,{123, 99,12}},   {  7,{73,45,14},  3,{74,46,14}},   { 15,{43,19,12},  2,{44,20,12}},   {  3, {45,15,15}, 13,{46,16,15}}},
  {{  1,{135,107,14},  5,{136,108,14}},   { 10,{74,46,14},  1,{75,47,14}},   {  1,{50,22,14}, 15,{51,23,14}},   {  2, {42,14,14}, 17,{43,15,14}}},
  {{  5,{150,120,15},  1,{151,121,15}},   {  9,{69,43,13},  4,{70,44,13}},   { 17,{50,22,14},  1,{51,23,14}},   {  2, {42,14,14}, 19,{43,15,14}}},
  {{  3,{141,113,14},  4,{142,114,14}},   {  3,{70,44,13}, 11,{71,45,13}},   { 17,{47,21,13},  4,{48,22,13}},   {  9, {39,13,13}, 16,{40,14,13}}},
  {{  3,{135,107,14},  5,{136,108,14}},   {  3,{67,41,13}, 13,{68,42,13}},   { 15,{54,24,15},  5,{55,25,15}},   { 15, {43,15,14}, 10,{44,16,14}}},
  {{  4,{144,116,14},  4,{145,117,14}},   { 17,{68,42,13}},                  { 17,{50,22,14},  6,{51,23,14}},   { 19, {46,16,15},  6,{47,17,15}}},
  {{  2,{139,111,14},  7,{140,112,14}},   { 17,{74,46,14}},                  {  7,{54,24,15}, 16,{55,25,15}},   { 34, {37,13,12}               }},
  {{  4,{151,121,15},  5,{152,122,15}},   {  4,{75,47,14}, 14,{76,48,14}},   { 11,{54,24,15}, 14,{55,25,15}},   { 16, {45,15,15}, 14,{46,16,15}}},
  {{  6,{147,117,15},  4,{148,118,15}},   {  6,{73,45,14}, 14,{74,46,14}},   { 11,{54,24,15}, 16,{55,25,15}},   { 30, {46,16,15},  2,{47,17,15}}},
  {{  8,{132,106,13},  4,{133,107,13}},   {  8,{75,47,14}, 13,{76,48,14}},   {  7,{54,24,15}, 22,{55,25,15}},   { 22, {45,15,15}, 13,{46,16,15}}},
  {{ 10,{142,114,14},  2,{143,115,14}},   { 19,{74,46,14},  4,{75,47,14}},   { 28,{50,22,14},  6,{51,23,14}},   { 33, {46,16,15},  4,{47,17,15}}},
  {{  8,{152,122,15},  4,{153,123,15}},   { 22,{73,45,14},  3,{74,46,14}},   {  8,{53,23,15}, 26,{54,24,15}},   { 12, {45,15,15}, 28,{46,16,15}}},
  {{  3,{147,117,15}, 10,{148,118,15}},   {  3,{73,45,14}, 23,{74,46,14}},   {  4,{54,24,15}, 31,{55,25,15}},   { 11, {45,15,15}, 31,{46,16,15}}},
  {{  7,{146,116,15},  7,{147,117,15}},   { 21,{73,45,14},  7,{74,46,14}},   {  1,{53,23,15}, 37,{54,24,15}},   { 19, {45,15,15}, 26,{46,16,15}}},
  {{  5,{145,115,15}, 10,{146,116,15}},   { 19,{75,47,14}, 10,{76,48,14}},   { 15,{54,24,15}, 25,{55,25,15}},   { 23, {45,15,15}, 25,{46,16,15}}},
  {{ 13,{145,115,15},  3,{146,116,15}},   {  2,{74,46,14}, 29,{75,47,14}},   { 42,{54,24,15},  1,{55,25,15}},   { 23, {45,15,15}, 28,{46,16,15}}},
  {{ 17,{145,115,15}                 },   { 10,{74,46,14}, 23,{75,47,14}},   { 10,{54,24,15}, 35,{55,25,15}},   { 19, {45,15,15}, 35,{46,16,15}}},
  {{ 17,{145,115,15},  1,{146,116,15}},   { 14,{74,46,14}, 21,{75,47,14}},   { 29,{54,24,15}, 19,{55,25,15}},   { 11, {45,15,15}, 46,{46,16,15}}},
  {{ 13,{145,115,15},  6,{146,116,15}},   { 14,{74,46,14}, 23,{75,47,14}},   { 44,{54,24,15},  7,{55,25,15}},   { 59, {46,16,15},  1,{47,17,15}}},
  {{ 12,{151,121,15},  7,{152,122,15}},   { 12,{75,47,14}, 26,{76,48,14}},   { 39,{54,24,15}, 14,{55,25,15}},   { 22, {45,15,15}, 41,{46,16,15}}},
  {{  6,{151,121,15}, 14,{152,122,15}},   {  6,{75,47,14}, 34,{76,48,14}},   { 46,{54,24,15}, 10,{55,25,15}},   {  2, {45,15,15}, 64,{46,16,15}}},
  {{ 17,{152,122,15},  4,{153,123,15}},   { 29,{74,46,14}, 14,{75,47,14}},   { 49,{54,24,15}, 10,{55,25,15}},   { 24, {45,15,15}, 46,{46,16,15}}},
  {{  4,{152,122,15}, 18,{153,123,15}},   { 13,{74,46,14}, 32,{75,47,14}},   { 48,{54,24,15}, 14,{55,25,15}},   { 42, {45,15,15}, 32,{46,16,15}}},
  {{ 20,{147,117,15},  4,{148,118,15}},   { 40,{75,47,14},  7,{76,48,14}},   { 43,{54,24,15}, 22,{55,25,15}},   { 10, {45,15,15}, 67,{46,16,15}}},
  {{ 19,{148,118,15},  6,{149,119,15}},   { 18,{75,47,14}, 31,{76,48,14}},   { 34,{54,24,15}, 34,{55,25,15}},   { 20, {45,15,15}, 61,{46,16,15}}}
}

-- The bits that must be 0 if the version does fill the complete matrix.
-- Example: for version 1, no bits need to be added after arranging the data, for version 2 we need to add 7 bits at the end.
local remainder = {0, 7, 7, 7, 7, 7, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0}

-- This is the formula for table 1 in the spec:
-- function get_capacity_remainder( version )
--     local len = version * 4 + 17
--     local size = len^2
--     local function_pattern_modules = 192 + 2 * len - 32 -- Position Adjustment pattern + timing pattern
--     local count_alignemnt_pattern = #alignment_pattern[version]
--     if count_alignemnt_pattern > 0 then
--         -- add 25 for each aligment pattern
--         function_pattern_modules = function_pattern_modules + 25 * ( count_alignemnt_pattern^2 - 3 )
--         -- but substract the timing pattern occupied by the aligment pattern on the top and left
--         function_pattern_modules = function_pattern_modules - ( count_alignemnt_pattern - 2) * 10
--     end
--     size = size - function_pattern_modules
--     if version > 6 then
--         size = size - 67
--     else
--         size = size - 31
--     end
--     return math.floor(size/8),math.fmod(size,8)
-- end


--- Example: Version 5-H has four data and four error correction blocks. The table above lists
--- `2, {33,11,11},  2,{34,12,11}` for entry [5][4]. This means we take two blocks with 11 codewords
--- and two blocks with 12 codewords, and two blocks with 33 - 11 = 22 ec codes and another
--- two blocks with 34 - 12 = 22 ec codes.
---         Block 1: D1  D2  D3  ... D11
---         Block 2: D12 D13 D14 ... D22
---         Block 3: D23 D24 D25 ... D33 D34
---         Block 4: D35 D36 D37 ... D45 D46
--- Then we place the data like this in the matrix: D1, D12, D23, D35, D2, D13, D24, D36 ... D45, D34, D46.  The same goes
--- with error correction codes.

-- The given data can be a string of 0's and 1' (with #string mod 8 == 0).
-- Alternatively the data can be a table of codewords. The number of codewords
-- must match the capacity of the qr code.
local function arrange_codewords_and_calculate_ec( version,ec_level,data )
    if type(data)=="table" then
        local tmp = ""
        for i=1,#data do
            tmp = tmp .. binary(data[i],8)
        end
        data = tmp
    end
    -- If the size of the data is not enough for the codeword, we add 0's and two special bytes until finished.
    local blocks = ecblocks[version][ec_level]
    local size_datablock_bytes, size_ecblock_bytes
    local datablocks = {}
    local ecblocks = {}
    local count = 1
    local pos = 0
    local cpty_ec_bits = 0
    for i=1,#blocks/2 do
        for j=1,blocks[2*i - 1] do
            size_datablock_bytes = blocks[2*i][2]
            size_ecblock_bytes   = blocks[2*i][1] - blocks[2*i][2]
            cpty_ec_bits = cpty_ec_bits + size_ecblock_bytes * 8
            datablocks[#datablocks + 1] = string.sub(data, pos * 8 + 1,( pos + size_datablock_bytes)*8)
            tmp_tab = calculate_error_correction(datablocks[#datablocks],size_ecblock_bytes)
            tmp_str = ""
            for x=1,#tmp_tab do
                tmp_str = tmp_str .. binary(tmp_tab[x],8)
            end
            ecblocks[#ecblocks + 1] = tmp_str
            pos = pos + size_datablock_bytes
            count = count + 1
        end
    end
    local arranged_data = ""
    pos = 1
    repeat
        for i=1,#datablocks do
            if pos < #datablocks[i] then
                arranged_data = arranged_data .. string.sub(datablocks[i],pos, pos + 7)
            end
        end
        pos = pos + 8
    until #arranged_data == #data
    -- ec
    local arranged_ec = ""
    pos = 1
    repeat
        for i=1,#ecblocks do
            if pos < #ecblocks[i] then
                arranged_ec = arranged_ec .. string.sub(ecblocks[i],pos, pos + 7)
            end
        end
        pos = pos + 8
    until #arranged_ec == cpty_ec_bits
    return arranged_data .. arranged_ec
end

--- Step 4: Generate 8 matrices with different masks and calculate the penalty
--- ==========================================================================
---
--- Prepare matrix
--- --------------
--- The first step is to prepare an _empty_ matrix for a given size/mask. The matrix has a
--- few predefined areas that must be black or blank. We encode the matrix with a two
--- dimensional field where the numbers determine which pixel is blank or not.
---
--- The following code is used for our matrix:
---         0 = not in use yet,
---        -2 = blank by mandatory pattern,
---         2 = black by mandatory pattern,
---        -1 = blank by data,
---         1 = black by data
---
---
--- To prepare the _empty_, we add positioning, alingment and timing patters.

--- ### Positioning patterns ###
local function add_position_detection_patterns(tab_x)
    local size = #tab_x
    -- allocate quite zone in the matrix area
    for i=1,8 do
        for j=1,8 do
            tab_x[i][j] = -2
            tab_x[size - 8 + i][j] = -2
            tab_x[i][size - 8 + j] = -2
        end
    end
    -- draw the detection pattern (outer)
    for i=1,7 do
        -- top left
        tab_x[1][i]=2
        tab_x[7][i]=2
        tab_x[i][1]=2
        tab_x[i][7]=2

        -- top right
        tab_x[size][i]=2
        tab_x[size - 6][i]=2
        tab_x[size - i + 1][1]=2
        tab_x[size - i + 1][7]=2

        -- bottom left
        tab_x[1][size - i + 1]=2
        tab_x[7][size - i + 1]=2
        tab_x[i][size - 6]=2
        tab_x[i][size]=2
    end
    -- draw the detection pattern (inner)
    for i=1,3 do
        for j=1,3 do
            -- top left
            tab_x[2+j][i+2]=2
            -- top right
            tab_x[size - j - 1][i+2]=2
            -- bottom left
            tab_x[2 + j][size - i - 1]=2
        end
    end
end

--- ### Timing patterns ###
-- The timing patterns (two) are the dashed lines between two adjacent positioning patterns on row/column 7.
local function add_timing_pattern(tab_x)
    local line,col
    line = 7
    col = 9
    for i=col,#tab_x - 8 do
        if math.fmod(i,2) == 1 then
            tab_x[i][line] = 2
        else
            tab_x[i][line] = -2
        end
    end
    for i=col,#tab_x - 8 do
        if math.fmod(i,2) == 1 then
            tab_x[line][i] = 2
        else
            tab_x[line][i] = -2
        end
    end
end


--- ### Alignment patterns ###
--- The alignment patterns must be added to the matrix for versions > 1. The amount and positions depend on the versions and are
--- given by the spec. Beware: the patterns must not be placed where we have the positioning patterns
--- (that is: top left, top right and bottom left.)

-- For each version, where should we place the alignment patterns? See table E.1 of the spec
local alignment_pattern = {
  {},{6,18},{6,22},{6,26},{6,30},{6,34}, -- 1-6
  {6,22,38},{6,24,42},{6,26,46},{6,28,50},{6,30,54},{6,32,58},{6,34,62}, -- 7-13
  {6,26,46,66},{6,26,48,70},{6,26,50,74},{6,30,54,78},{6,30,56,82},{6,30,58,86},{6,34,62,90}, -- 14-20
  {6,28,50,72,94},{6,26,50,74,98},{6,30,54,78,102},{6,28,54,80,106},{6,32,58,84,110},{6,30,58,86,114},{6,34,62,90,118}, -- 21-27
  {6,26,50,74,98 ,122},{6,30,54,78,102,126},{6,26,52,78,104,130},{6,30,56,82,108,134},{6,34,60,86,112,138},{6,30,58,86,114,142},{6,34,62,90,118,146}, -- 28-34
  {6,30,54,78,102,126,150}, {6,24,50,76,102,128,154},{6,28,54,80,106,132,158},{6,32,58,84,110,136,162},{6,26,54,82,110,138,166},{6,30,58,86,114,142,170} -- 35 - 40
}

--- The alignment pattern has size 5x5 and looks like this:
---     XXXXX
---     X   X
---     X X X
---     X   X
---     XXXXX
local function add_alignment_pattern( tab_x )
    local version = (#tab_x - 17) / 4
    local ap = alignment_pattern[version]
    local pos_x, pos_y
    for x=1,#ap do
        for y=1,#ap do
            -- we must not put an alignment pattern on top of the positioning pattern
            if not (x == 1 and y == 1 or x == #ap and y == 1 or x == 1 and y == #ap ) then
                pos_x = ap[x] + 1
                pos_y = ap[y] + 1
                tab_x[pos_x][pos_y] = 2
                tab_x[pos_x+1][pos_y] = -2
                tab_x[pos_x-1][pos_y] = -2
                tab_x[pos_x+2][pos_y] =  2
                tab_x[pos_x-2][pos_y] =  2
                tab_x[pos_x  ][pos_y - 2] = 2
                tab_x[pos_x+1][pos_y - 2] = 2
                tab_x[pos_x-1][pos_y - 2] = 2
                tab_x[pos_x+2][pos_y - 2] = 2
                tab_x[pos_x-2][pos_y - 2] = 2
                tab_x[pos_x  ][pos_y + 2] = 2
                tab_x[pos_x+1][pos_y + 2] = 2
                tab_x[pos_x-1][pos_y + 2] = 2
                tab_x[pos_x+2][pos_y + 2] = 2
                tab_x[pos_x-2][pos_y + 2] = 2

                tab_x[pos_x  ][pos_y - 1] = -2
                tab_x[pos_x+1][pos_y - 1] = -2
                tab_x[pos_x-1][pos_y - 1] = -2
                tab_x[pos_x+2][pos_y - 1] =  2
                tab_x[pos_x-2][pos_y - 1] =  2
                tab_x[pos_x  ][pos_y + 1] = -2
                tab_x[pos_x+1][pos_y + 1] = -2
                tab_x[pos_x-1][pos_y + 1] = -2
                tab_x[pos_x+2][pos_y + 1] =  2
                tab_x[pos_x-2][pos_y + 1] =  2
            end
        end
    end
end

--- ### Type information ###
--- Let's not forget the type information that is in column 9 next to the left positioning patterns and on row 9 below
--- the top positioning patterns. This type information is not fixed, it depends on the mask and the error correction.

-- The first index is ec level (LMQH,1-4), the second is the mask (0-7). This bitstring of length 15 is to be used
-- as mandatory pattern in the qrcode. Mask -1 is for debugging purpose only and is the 'noop' mask.
local typeinfo = {
    { [-1]= "111111111111111", [0] = "111011111000100", "111001011110011", "111110110101010", "111100010011101", "110011000101111", "110001100011000", "110110001000001", "110100101110110" },
    { [-1]= "111111111111111", [0] = "101010000010010", "101000100100101", "101111001111100", "101101101001011", "100010111111001", "100000011001110", "100111110010111", "100101010100000" },
    { [-1]= "111111111111111", [0] = "011010101011111", "011000001101000", "011111100110001", "011101000000110", "010010010110100", "010000110000011", "010111011011010", "010101111101101" },
    { [-1]= "111111111111111", [0] = "001011010001001", "001001110111110", "001110011100111", "001100111010000", "000011101100010", "000001001010101", "000110100001100", "000100000111011" }
}

-- The typeinfo is a mixture of mask and ec level information and is
-- added twice to the qr code, one horizontal, one vertical.
local function add_typeinfo_to_matrix( matrix,ec_level,mask )
    local ec_mask_type = typeinfo[ec_level][mask]

    local bit
    -- vertical from bottom to top
    for i=1,7 do
        bit = string.sub(ec_mask_type,i,i)
        fill_matrix_position(matrix, bit, 9, #matrix - i + 1)
    end
    for i=8,9 do
        bit = string.sub(ec_mask_type,i,i)
        fill_matrix_position(matrix,bit,9,17-i)
    end
    for i=10,15 do
        bit = string.sub(ec_mask_type,i,i)
        fill_matrix_position(matrix,bit,9,16 - i)
    end
    -- horizontal, left to right
    for i=1,6 do
        bit = string.sub(ec_mask_type,i,i)
        fill_matrix_position(matrix,bit,i,9)
    end
    bit = string.sub(ec_mask_type,7,7)
    fill_matrix_position(matrix,bit,8,9)
    for i=8,15 do
        bit = string.sub(ec_mask_type,i,i)
        fill_matrix_position(matrix,bit,#matrix - 15 + i,9)
    end
end

-- Bits for version information 7-40
-- The reversed strings from https://www.thonky.com/qr-code-tutorial/format-version-tables
local version_information = {"001010010011111000", "001111011010000100", "100110010101100100", "110010110010010100",
  "011011111101110100", "010001101110001100", "111000100001101100", "101100000110011100", "000101001001111100",
  "000111101101000010", "101110100010100010", "111010000101010010", "010011001010110010", "011001011001001010",
  "110000010110101010", "100100110001011010", "001101111110111010", "001000110111000110", "100001111000100110",
  "110101011111010110", "011100010000110110", "010110000011001110", "111111001100101110", "101011101011011110",
  "000010100100111110", "101010111001000001", "000011110110100001", "010111010001010001", "111110011110110001",
  "110100001101001001", "011101000010101001", "001001100101011001", "100000101010111001", "100101100011000101" }

-- Versions 7 and above need two bitfields with version information added to the code
local function add_version_information(matrix,version)
    if version < 7 then return end
    local size = #matrix
    local bitstring = version_information[version - 6]
    local x,y, bit
    local start_x, start_y
    -- first top right
    start_x = #matrix - 10
    start_y = 1
    for i=1,#bitstring do
        bit = string.sub(bitstring,i,i)
        x = start_x + math.fmod(i - 1,3)
        y = start_y + math.floor( (i - 1) / 3 )
        fill_matrix_position(matrix,bit,x,y)
    end

    -- now bottom left
    start_x = 1
    start_y = #matrix - 10
    for i=1,#bitstring do
        bit = string.sub(bitstring,i,i)
        x = start_x + math.floor( (i - 1) / 3 )
        y = start_y + math.fmod(i - 1,3)
        fill_matrix_position(matrix,bit,x,y)
    end
end

--- Now it's time to use the methods above to create a prefilled matrix for the given mask
local function prepare_matrix_with_mask( version,ec_level, mask )
    local size
    local tab_x = {}

    size = version * 4 + 17
    for i=1,size do
        tab_x[i]={}
        for j=1,size do
            tab_x[i][j] = 0
        end
    end
    add_position_detection_patterns(tab_x)
    add_timing_pattern(tab_x)
    add_version_information(tab_x,version)

    -- black pixel above lower left position detection pattern
    tab_x[9][size - 7] = 2
    add_alignment_pattern(tab_x)
    add_typeinfo_to_matrix(tab_x,ec_level, mask)
    return tab_x
end

--- Finally we come to the place where we need to put the calculated data (remember step 3?) into the qr code.
--- We do this for each mask. BTW speaking of mask, this is what we find in the spec:
---         Mask Pattern Reference   Condition
---         000                      (y + x) mod 2 = 0
---         001                      y mod 2 = 0
---         010                      x mod 3 = 0
---         011                      (y + x) mod 3 = 0
---         100                      ((y div 2) + (x div 3)) mod 2 = 0
---         101                      (y x) mod 2 + (y x) mod 3 = 0
---         110                      ((y x) mod 2 + (y x) mod 3) mod 2 = 0
---         111                      ((y x) mod 3 + (y+x) mod 2) mod 2 = 0

-- Return 1 (black) or -1 (blank) depending on the mask, value and position.
-- Parameter mask is 0-7 (-1 for 'no mask'). x and y are 1-based coordinates,
-- 1,1 = upper left. tonumber(value) must be 0 or 1.
local function get_pixel_with_mask( mask, x,y,value )
    x = x - 1
    y = y - 1
    local invert = false
    -- test purpose only:
    if mask == -1 then
        -- ignore, no masking applied
    elseif mask == 0 then
        if math.fmod(x + y,2) == 0 then invert = true end
    elseif mask == 1 then
        if math.fmod(y,2) == 0 then invert = true end
    elseif mask == 2 then
        if math.fmod(x,3) == 0 then invert = true end
    elseif mask == 3 then
        if math.fmod(x + y,3) == 0 then invert = true end
    elseif mask == 4 then
        if math.fmod(math.floor(y / 2) + math.floor(x / 3),2) == 0 then invert = true end
    elseif mask == 5 then
        if math.fmod(x * y,2) + math.fmod(x * y,3) == 0 then invert = true end
    elseif mask == 6 then
        if math.fmod(math.fmod(x * y,2) + math.fmod(x * y,3),2) == 0 then invert = true end
    elseif mask == 7 then
        if math.fmod(math.fmod(x * y,3) + math.fmod(x + y,2),2) == 0 then invert = true end
    else
        assert(false,"This can't happen (mask must be <= 7)")
    end
    if invert then
        -- value = 1? -> -1, value = 0? -> 1
        return 1 - 2 * tonumber(value)
    else
        -- value = 1? -> 1, value = 0? -> -1
        return -1 + 2*tonumber(value)
    end
end


-- We need up to 8 positions in the matrix. Only the last few bits may be less then 8.
-- The function returns a table of (up to) 8 entries with subtables where
-- the x coordinate is the first and the y coordinate is the second entry.
local function get_next_free_positions(matrix,x,y,dir,byte)
    local ret = {}
    local count = 1
    local mode = "right"
    while count <= #byte do
        if mode == "right" and matrix[x][y] == 0 then
            ret[#ret + 1] = {x,y}
            mode = "left"
            count = count + 1
        elseif mode == "left" and matrix[x-1][y] == 0 then
            ret[#ret + 1] = {x-1,y}
            mode = "right"
            count = count + 1
            if dir == "up" then
                y = y - 1
            else
                y = y + 1
            end
        elseif mode == "right" and matrix[x-1][y] == 0 then
            ret[#ret + 1] = {x-1,y}
            count = count + 1
            if dir == "up" then
                y = y - 1
            else
                y = y + 1
            end
        else
            if dir == "up" then
                y = y - 1
            else
                y = y + 1
            end
        end
        if y < 1 or y > #matrix then
            x = x - 2
            -- don't overwrite the timing pattern
            if x == 7 then x = 6 end
            if dir == "up" then
                dir = "down"
                y = 1
            else
                dir = "up"
                y = #matrix
            end
        end
    end
    return ret,x,y,dir
end

-- Add the data string (0's and 1's) to the matrix for the given mask.
local function add_data_to_matrix(matrix,data,mask)
    size = #matrix
    local x,y,positions
    local _x,_y,m
    local dir = "up"
    local byte_number = 0
    x,y = size,size
    string.gsub(data,".?.?.?.?.?.?.?.?",function ( byte )
        byte_number = byte_number + 1
        positions,x,y,dir = get_next_free_positions(matrix,x,y,dir,byte,mask)
        for i=1,#byte do
            _x = positions[i][1]
            _y = positions[i][2]
            m = get_pixel_with_mask(mask,_x,_y,string.sub(byte,i,i))
            if debugging then
                matrix[_x][_y] = m * (i + 10)
            else
                matrix[_x][_y] = m
            end
        end
    end)
end


--- The total penalty of the matrix is the sum of four steps. The following steps are taken into account:
---
--- 1. Adjacent modules in row/column in same color
--- 1. Block of modules in same color
--- 1. 1:1:3:1:1 ratio (dark:light:dark:light:dark) pattern in row/column
--- 1. Proportion of dark modules in entire symbol
---
--- This all is done to avoid bad patterns in the code that prevent the scanner from
--- reading the code.
-- Return the penalty for the given matrix
local function calculate_penalty(matrix)
    local penalty1, penalty2, penalty3, penalty4 = 0,0,0,0
    local size = #matrix
    -- this is for penalty 4
    local number_of_dark_cells = 0

    -- 1: Adjacent modules in row/column in same color
    -- --------------------------------------------
    -- No. of modules = (5+i)  -> 3 + i
    local last_bit_blank -- < 0:  blank, > 0: black
    local is_blank
    local number_of_consecutive_bits
    -- first: vertical
    for x=1,size do
        number_of_consecutive_bits = 0
        last_bit_blank = nil
        for y = 1,size do
            if matrix[x][y] > 0 then
                -- small optimization: this is for penalty 4
                number_of_dark_cells = number_of_dark_cells + 1
                is_blank = false
            else
                is_blank = true
            end
            is_blank = matrix[x][y] < 0
            if last_bit_blank == is_blank then
                number_of_consecutive_bits = number_of_consecutive_bits + 1
            else
                if number_of_consecutive_bits >= 5 then
                    penalty1 = penalty1 + number_of_consecutive_bits - 2
                end
                number_of_consecutive_bits = 1
            end
            last_bit_blank = is_blank
        end
        if number_of_consecutive_bits >= 5 then
            penalty1 = penalty1 + number_of_consecutive_bits - 2
        end
    end
    -- now horizontal
    for y=1,size do
        number_of_consecutive_bits = 0
        last_bit_blank = nil
        for x = 1,size do
            is_blank = matrix[x][y] < 0
            if last_bit_blank == is_blank then
                number_of_consecutive_bits = number_of_consecutive_bits + 1
            else
                if number_of_consecutive_bits >= 5 then
                    penalty1 = penalty1 + number_of_consecutive_bits - 2
                end
                number_of_consecutive_bits = 1
            end
            last_bit_blank = is_blank
        end
        if number_of_consecutive_bits >= 5 then
            penalty1 = penalty1 + number_of_consecutive_bits - 2
        end
    end
    for x=1,size do
        for y=1,size do
            -- 2: Block of modules in same color
            -- -----------------------------------
            -- Blocksize = m × n  -> 3 × (m-1) × (n-1)
            if (y < size - 1) and ( x < size - 1) and ( (matrix[x][y] < 0 and matrix[x+1][y] < 0 and matrix[x][y+1] < 0 and matrix[x+1][y+1] < 0) or (matrix[x][y] > 0 and matrix[x+1][y] > 0 and matrix[x][y+1] > 0 and matrix[x+1][y+1] > 0) ) then
                penalty2 = penalty2 + 3
            end

            -- 3: 1:1:3:1:1 ratio (dark:light:dark:light:dark) pattern in row/column
            -- ------------------------------------------------------------------
            -- Gives 40 points each
            --
            -- I have no idea why we need the extra 0000 on left or right side. The spec doesn't mention it,
            -- other sources do mention it. This is heavily inspired by zxing.
            if (y + 6 < size and
                matrix[x][y] > 0 and
                matrix[x][y +  1] < 0 and
                matrix[x][y +  2] > 0 and
                matrix[x][y +  3] > 0 and
                matrix[x][y +  4] > 0 and
                matrix[x][y +  5] < 0 and
                matrix[x][y +  6] > 0 and
                ((y + 10 < size and
                    matrix[x][y +  7] < 0 and
                    matrix[x][y +  8] < 0 and
                    matrix[x][y +  9] < 0 and
                    matrix[x][y + 10] < 0) or
                 (y - 4 >= 1 and
                    matrix[x][y -  1] < 0 and
                    matrix[x][y -  2] < 0 and
                    matrix[x][y -  3] < 0 and
                    matrix[x][y -  4] < 0))) then penalty3 = penalty3 + 40 end
            if (x + 6 <= size and
                matrix[x][y] > 0 and
                matrix[x +  1][y] < 0 and
                matrix[x +  2][y] > 0 and
                matrix[x +  3][y] > 0 and
                matrix[x +  4][y] > 0 and
                matrix[x +  5][y] < 0 and
                matrix[x +  6][y] > 0 and
                ((x + 10 <= size and
                    matrix[x +  7][y] < 0 and
                    matrix[x +  8][y] < 0 and
                    matrix[x +  9][y] < 0 and
                    matrix[x + 10][y] < 0) or
                 (x - 4 >= 1 and
                    matrix[x -  1][y] < 0 and
                    matrix[x -  2][y] < 0 and
                    matrix[x -  3][y] < 0 and
                    matrix[x -  4][y] < 0))) then penalty3 = penalty3 + 40 end
        end
    end
    -- 4: Proportion of dark modules in entire symbol
    -- ----------------------------------------------
    -- 50 ± (5 × k)% to 50 ± (5 × (k + 1))% -> 10 × k
    local dark_ratio = number_of_dark_cells / ( size * size )
    penalty4 = math.floor(math.abs(dark_ratio * 100 - 50)) * 2
    return penalty1 + penalty2 + penalty3 + penalty4
end

-- Create a matrix for the given parameters and calculate the penalty score.
-- Return both (matrix and penalty)
local function get_matrix_and_penalty(version,ec_level,data,mask)
    local tab = prepare_matrix_with_mask(version,ec_level,mask)
    add_data_to_matrix(tab,data,mask)
    local penalty = calculate_penalty(tab)
    return tab, penalty
end

-- Return the matrix with the smallest penalty. To to this
-- we try out the matrix for all 8 masks and determine the
-- penalty (score) each.
local function get_matrix_with_lowest_penalty(version,ec_level,data)
    local tab, penalty
    local tab_min_penalty, min_penalty

    -- try masks 0-7
    tab_min_penalty, min_penalty = get_matrix_and_penalty(version,ec_level,data,0)
    for i=1,7 do
        tab, penalty = get_matrix_and_penalty(version,ec_level,data,i)
        if penalty < min_penalty then
            tab_min_penalty = tab
            min_penalty = penalty
        end
    end
    return tab_min_penalty
end

--- The main function. We connect everything together. Remember from above:
---
--- 1. Determine version, ec level and mode (=encoding) for codeword
--- 1. Encode data
--- 1. Arrange data and calculate error correction code
--- 1. Generate 8 matrices with different masks and calculate the penalty
--- 1. Return qrcode with least penalty
-- If ec_level or mode is given, use the ones for generating the qrcode. (mode is not implemented yet)
local function qrcode( str, ec_level, mode )
    local arranged_data, version, data_raw, mode, len_bitstring
    version, ec_level, data_raw, mode, len_bitstring = get_version_eclevel_mode_bistringlength(str,ec_level)
    data_raw = data_raw .. len_bitstring
    data_raw = data_raw .. encode_data(str,mode)
    data_raw = add_pad_data(version,ec_level,data_raw)
    arranged_data = arrange_codewords_and_calculate_ec(version,ec_level,data_raw)
    if math.fmod(#arranged_data,8) ~= 0 then
        return false, string.format("Arranged data %% 8 != 0: data length = %d, mod 8 = %d",#arranged_data, math.fmod(#arranged_data,8))
    end
    arranged_data = arranged_data .. string.rep("0",remainder[version])
    local tab = get_matrix_with_lowest_penalty(version,ec_level,arranged_data)
    return true, tab
end


if testing then
    return {
        encode_string_numeric = encode_string_numeric,
        encode_string_ascii = encode_string_ascii,
        qrcode = qrcode,
        binary = binary,
        get_mode = get_mode,
        get_length = get_length,
        add_pad_data = add_pad_data,
        get_generator_polynominal_adjusted = get_generator_polynominal_adjusted,
        get_pixel_with_mask = get_pixel_with_mask,
        get_version_eclevel_mode_bistringlength = get_version_eclevel_mode_bistringlength,
        remainder = remainder,
        --get_capacity_remainder = get_capacity_remainder,
        arrange_codewords_and_calculate_ec = arrange_codewords_and_calculate_ec,
        calculate_error_correction = calculate_error_correction,
        convert_bitstring_to_bytes = convert_bitstring_to_bytes,
        bit_xor = bit_xor,
    }
end

return {
    qrcode = qrcode
}