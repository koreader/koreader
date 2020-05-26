-- $Revision: 1.5 $
-- $Date: 2014-09-10 16:54:25 $
 
-- This module was originally taken from http://cube3d.de/uploads/Main/sha1.txt.
 
-------------------------------------------------------------------------------
-- SHA-1 secure hash computation, and HMAC-SHA1 signature computation,
-- in pure Lua (tested on Lua 5.1)
-- License: MIT
--
-- Usage:
-- local hashAsHex = sha1.hex(message) -- returns a hex string
-- local hashAsData = sha1.bin(message) -- returns raw bytes
--
-- local hmacAsHex = sha1.hmacHex(key, message) -- hex string
-- local hmacAsData = sha1.hmacBin(key, message) -- raw bytes
--
--
-- Pass sha1.hex() a string, and it returns a hash as a 40-character hex string.
-- For example, the call
--
-- local hash = sha1.hex("iNTERFACEWARE")
--
-- puts the 40-character string
--
-- "e76705ffb88a291a0d2f9710a5471936791b4819"
--
-- into the variable 'hash'
--
-- Pass sha1.hmacHex() a key and a message, and it returns the signature as a
-- 40-byte hex string.
--
--
-- The two "bin" versions do the same, but return the 20-byte string of raw
-- data that the 40-byte hex strings represent.
--
-------------------------------------------------------------------------------
--
-- Description
-- Due to the lack of bitwise operations in 5.1, this version uses numbers to
-- represents the 32bit words that we combine with binary operations. The basic
-- operations of byte based "xor", "or", "and" are all cached in a combination
-- table (several 64k large tables are built on startup, which
-- consumes some memory and time). The caching can be switched off through
-- setting the local cfg_caching variable to false.
-- For all binary operations, the 32 bit numbers are split into 8 bit values
-- that are combined and then merged again.
--
-- Algorithm: http://www.itl.nist.gov/fipspubs/fip180-1.htm
--
-------------------------------------------------------------------------------
 
sha1 = {}
 
-- set this to false if you don't want to build several 64k sized tables when
-- loading this file (takes a while but grants a boost of factor 13)
local cfg_caching = false
 
-- local storing of global functions (minor speedup)
local floor,modf = math.floor,math.modf
local char,format,rep = string.char,string.format,string.rep
 
-- merge 4 bytes to an 32 bit word
local function bytes_to_w32 (a,b,c,d) return a*0x1000000+b*0x10000+c*0x100+d end
-- split a 32 bit word into four 8 bit numbers
local function w32_to_bytes (i)
   return floor(i/0x1000000)%0x100,floor(i/0x10000)%0x100,floor(i/0x100)%0x100,i%0x100
end
 
-- shift the bits of a 32 bit word. Don't use negative values for "bits"
local function w32_rot (bits,a)
   local b2 = 2^(32-bits)
   local a,b = modf(a/b2)
   return a+b*b2*(2^(bits))
end
 
-- caching function for functions that accept 2 arguments, both of values between
-- 0 and 255. The function to be cached is passed, all values are calculated
-- during loading and a function is returned that returns the cached values (only)
local function cache2arg (fn)
   if not cfg_caching then return fn end
   local lut = {}
   for i=0,0xffff do
      local a,b = floor(i/0x100),i%0x100
      lut[i] = fn(a,b)
   end
   return function (a,b)
      return lut[a*0x100+b]
   end
end
 
-- splits an 8-bit number into 8 bits, returning all 8 bits as booleans
local function byte_to_bits (b)
   local b = function (n)
      local b = floor(b/n)
      return b%2==1
   end
   return b(1),b(2),b(4),b(8),b(16),b(32),b(64),b(128)
end
 
-- builds an 8bit number from 8 booleans
local function bits_to_byte (a,b,c,d,e,f,g,h)
   local function n(b,x) return b and x or 0 end
   return n(a,1)+n(b,2)+n(c,4)+n(d,8)+n(e,16)+n(f,32)+n(g,64)+n(h,128)
end
 
-- debug function for visualizing bits in a string
local function bits_to_string (a,b,c,d,e,f,g,h)
   local function x(b) return b and "1" or "0" end
   return ("%s%s%s%s %s%s%s%s"):format(x(a),x(b),x(c),x(d),x(e),x(f),x(g),x(h))
end
 
-- debug function for converting a 8-bit number as bit string
local function byte_to_bit_string (b)
   return bits_to_string(byte_to_bits(b))
end
 
-- debug function for converting a 32 bit number as bit string
local function w32_to_bit_string(a)
   if type(a) == "string" then return a end
   local aa,ab,ac,ad = w32_to_bytes(a)
   local s = byte_to_bit_string
   return ("%s %s %s %s"):format(s(aa):reverse(),s(ab):reverse(),s(ac):reverse(),s(ad):reverse()):reverse()
end
 
-- bitwise "and" function for 2 8bit number
local band = cache2arg (function(a,b)
      local A,B,C,D,E,F,G,H = byte_to_bits(b)
      local a,b,c,d,e,f,g,h = byte_to_bits(a)
      return bits_to_byte(
         A and a, B and b, C and c, D and d,
         E and e, F and f, G and g, H and h)
   end)
 
-- bitwise "or" function for 2 8bit numbers
local bor = cache2arg(function(a,b)
      local A,B,C,D,E,F,G,H = byte_to_bits(b)
      local a,b,c,d,e,f,g,h = byte_to_bits(a)
      return bits_to_byte(
         A or a, B or b, C or c, D or d,
         E or e, F or f, G or g, H or h)
   end)
 
-- bitwise "xor" function for 2 8bit numbers
local bxor = cache2arg(function(a,b)
      local A,B,C,D,E,F,G,H = byte_to_bits(b)
      local a,b,c,d,e,f,g,h = byte_to_bits(a)
      return bits_to_byte(
         A ~= a, B ~= b, C ~= c, D ~= d,
         E ~= e, F ~= f, G ~= g, H ~= h)
   end)
 
-- bitwise complement for one 8bit number
local function bnot (x)
   return 255-(x % 256)
end
 
-- creates a function to combine to 32bit numbers using an 8bit combination function
local function w32_comb(fn)
   return function (a,b)
      local aa,ab,ac,ad = w32_to_bytes(a)
      local ba,bb,bc,bd = w32_to_bytes(b)
      return bytes_to_w32(fn(aa,ba),fn(ab,bb),fn(ac,bc),fn(ad,bd))
   end
end
 
-- create functions for and, xor and or, all for 2 32bit numbers
local w32_and = w32_comb(band)
local w32_xor = w32_comb(bxor)
local w32_or = w32_comb(bor)
 
-- xor function that may receive a variable number of arguments
local function w32_xor_n (a,...)
   local aa,ab,ac,ad = w32_to_bytes(a)
   for i=1,select('#',...) do
      local ba,bb,bc,bd = w32_to_bytes(select(i,...))
      aa,ab,ac,ad = bxor(aa,ba),bxor(ab,bb),bxor(ac,bc),bxor(ad,bd)
   end
   return bytes_to_w32(aa,ab,ac,ad)
end
 
-- combining 3 32bit numbers through binary "or" operation
local function w32_or3 (a,b,c)
   local aa,ab,ac,ad = w32_to_bytes(a)
   local ba,bb,bc,bd = w32_to_bytes(b)
   local ca,cb,cc,cd = w32_to_bytes(c)
   return bytes_to_w32(
      bor(aa,bor(ba,ca)), bor(ab,bor(bb,cb)), bor(ac,bor(bc,cc)), bor(ad,bor(bd,cd))
   )
end
 
-- binary complement for 32bit numbers
local function w32_not (a)
   return 4294967295-(a % 4294967296)
end
 
-- adding 2 32bit numbers, cutting off the remainder on 33th bit
local function w32_add (a,b) return (a+b) % 4294967296 end
 
-- adding n 32bit numbers, cutting off the remainder (again)
local function w32_add_n (a,...)
   for i=1,select('#',...) do
      a = (a+select(i,...)) % 4294967296
   end
   return a
end
-- converting the number to a hexadecimal string
local function w32_to_hexstring (w) return format("%08x",w) end
 
-- calculating the SHA1 for some text
function sha1.hex(msg)
   local H0,H1,H2,H3,H4 = 0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0
   local msg_len_in_bits = #msg * 8
   
   local first_append = char(0x80) -- append a '1' bit plus seven '0' bits
   
   local non_zero_message_bytes = #msg +1 +8 -- the +1 is the appended bit 1, the +8 are for the final appended length
   local current_mod = non_zero_message_bytes % 64
   local second_append = current_mod>0 and rep(char(0), 64 - current_mod) or ""
   
   -- now to append the length as a 64-bit number.
   local B1, R1 = modf(msg_len_in_bits / 0x01000000)
   local B2, R2 = modf( 0x01000000 * R1 / 0x00010000)
   local B3, R3 = modf( 0x00010000 * R2 / 0x00000100)
   local B4 = 0x00000100 * R3
   
   local L64 = char( 0) .. char( 0) .. char( 0) .. char( 0) -- high 32 bits
   .. char(B1) .. char(B2) .. char(B3) .. char(B4) -- low 32 bits
   
   msg = msg .. first_append .. second_append .. L64
   
   assert(#msg % 64 == 0)
   
   local chunks = #msg / 64
   
   local W = { }
   local start, A, B, C, D, E, f, K, TEMP
   local chunk = 0
   
   while chunk < chunks do
      --
      -- break chunk up into W[0] through W[15]
      --
      start,chunk = chunk * 64 + 1,chunk + 1
      
      for t = 0, 15 do
         W[t] = bytes_to_w32(msg:byte(start, start + 3))
         start = start + 4
      end
      
      --
      -- build W[16] through W[79]
      --
      for t = 16, 79 do
         -- For t = 16 to 79 let Wt = S1(Wt-3 XOR Wt-8 XOR Wt-14 XOR Wt-16).
         W[t] = w32_rot(1, w32_xor_n(W[t-3], W[t-8], W[t-14], W[t-16]))
      end
      
      A,B,C,D,E = H0,H1,H2,H3,H4
      
      for t = 0, 79 do
         if t <= 19 then
            -- (B AND C) OR ((NOT B) AND D)
            f = w32_or(w32_and(B, C), w32_and(w32_not(B), D))
            K = 0x5A827999
         elseif t <= 39 then
            -- B XOR C XOR D
            f = w32_xor_n(B, C, D)
            K = 0x6ED9EBA1
         elseif t <= 59 then
            -- (B AND C) OR (B AND D) OR (C AND D
            f = w32_or3(w32_and(B, C), w32_and(B, D), w32_and(C, D))
            K = 0x8F1BBCDC
         else
            -- B XOR C XOR D
            f = w32_xor_n(B, C, D)
            K = 0xCA62C1D6
         end
         
         -- TEMP = S5(A) + ft(B,C,D) + E + Wt + Kt;
         A,B,C,D,E = w32_add_n(w32_rot(5, A), f, E, W[t], K),
         A, w32_rot(30, B), C, D
      end
      -- Let H0 = H0 + A, H1 = H1 + B, H2 = H2 + C, H3 = H3 + D, H4 = H4 + E.
      H0,H1,H2,H3,H4 = w32_add(H0, A),w32_add(H1, B),w32_add(H2, C),w32_add(H3, D),w32_add(H4, E)
   end
   local f = w32_to_hexstring
   return f(H0) .. f(H1) .. f(H2) .. f(H3) .. f(H4)
end
 
local function hex_to_binary(hex)
   return hex:gsub('..', function(hexval)
         return string.char(tonumber(hexval, 16))
      end)
end
 
function sha1.bin(msg)
   return hex_to_binary(sha1.hex(msg))
end
 
local xor_with_0x5c = {}
local xor_with_0x36 = {}
-- building the lookuptables ahead of time (instead of littering the source code
-- with precalculated values)
for i=0,0xff do
   xor_with_0x5c[char(i)] = char(bxor(i,0x5c))
   xor_with_0x36[char(i)] = char(bxor(i,0x36))
end
 
local blocksize = 64 -- 512 bits
 
function sha1.hmacHex(key, text)
   assert(type(key) == 'string', "key passed to hmacHex should be a string")
   assert(type(text) == 'string', "text passed to hmacHex should be a string")
   
   if #key > blocksize then
      key = sha1.bin(key)
   end
   
   local key_xord_with_0x36 = key:gsub('.', xor_with_0x36) .. string.rep(string.char(0x36), blocksize - #key)
   local key_xord_with_0x5c = key:gsub('.', xor_with_0x5c) .. string.rep(string.char(0x5c), blocksize - #key)
   
   return sha1.hex(key_xord_with_0x5c .. sha1.bin(key_xord_with_0x36 .. text))
end
 
function sha1.hmacBin(key, text)
   return hex_to_binary(sha1.hmacHex(key, text))
end
 
return sha1
