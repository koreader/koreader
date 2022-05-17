-- set search path for 'require()'
package.path =
    "common/?.lua;rocks/share/lua/5.1/?.lua;frontend/?.lua;" ..
    package.path
package.cpath =
    "common/?.so;common/?.dll;/usr/lib/lua/?.so;rocks/lib/lua/5.1/?.so;" ..
    package.cpath
