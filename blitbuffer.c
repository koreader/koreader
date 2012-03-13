/*
    KindlePDFViewer: buffer for blitting muPDF data to framebuffer (blitbuffer)
    Copyright (C) 2011 Hans-Werner Hilse <hilse@web.de>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <stdlib.h>
#include <string.h>
#include "blitbuffer.h"

int newBlitBufferNative(lua_State *L, int w, int h, BlitBuffer **newBuffer) {
	BlitBuffer *bb = (BlitBuffer*) lua_newuserdata(L, sizeof(BlitBuffer));
	luaL_getmetatable(L, "blitbuffer");
	lua_setmetatable(L, -2);

	bb->w = w;
	bb->pitch = (w + 1) / 2;
	bb->h = h;
	bb->data = malloc(bb->pitch * h);
	if(bb->data == NULL) {
		return luaL_error(L, "cannot allocate memory for blitbuffer");
	}
	memset(bb->data, 0, bb->pitch * h);
	bb->allocated = 1;
	if(newBuffer != NULL) {
		*newBuffer = bb;
	}
	return 1;
}

static int newBlitBuffer(lua_State *L) {
	int w = luaL_checkint(L, 1);
	int h = luaL_checkint(L, 2);
	return newBlitBufferNative(L, w, h, NULL);
}

static int getWidth(lua_State *L) {
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	lua_pushinteger(L, bb->w);
	return 1;
}

static int getHeight(lua_State *L) {
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	lua_pushinteger(L, bb->h);
	return 1;
}

static int freeBlitBuffer(lua_State *L) {
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");

	if(bb->allocated && bb->data != NULL) {
		free(bb->data);
		bb->data = NULL;
	}
	return 0;
}

static int blitFullToBuffer(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	BlitBuffer *src = (BlitBuffer*) luaL_checkudata(L, 2, "blitbuffer");

	if(src->w != dst->w || src->h != dst->h) {
		return luaL_error(L, "blitbuffer size must be framebuffer size!");
	}
	
	memcpy(dst->data, src->data, src->pitch * src->h);

	return 0;
}

static int blitToBuffer(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	BlitBuffer *src = (BlitBuffer*) luaL_checkudata(L, 2, "blitbuffer");
	int xdest = luaL_checkint(L, 3);
	int ydest = luaL_checkint(L, 4);
	int xoffs = luaL_checkint(L, 5);
	int yoffs = luaL_checkint(L, 6);
	int w = luaL_checkint(L, 7);
	int h = luaL_checkint(L, 8);
	int x, y;

	// check bounds
	if(ydest < 0) {
		// negative ydest, try to compensate
		if(ydest + h > 0) {
			// shrink h by negative dest offset
			h += ydest;
			// extend source offset
			yoffs += -ydest;
			ydest = 0;
		} else {
			// effectively no height
			return 0;
		}
	} else if(ydest >= dst->h) {
		// we're told to paint to off-bound target coords
		return 0;
	}
	if(ydest + h > dst->h) {
		// clamp height if too large for target size
		h = dst->h - ydest;
	}
	if(yoffs >= src->h) {
		// recalculated source offset is out of bounds
		return 0;
	} else if(yoffs + h > src->h) {
		// clamp height if too large for source size
		h = src->h - yoffs;
	}
	// same stuff for x coords:
	if(xdest < 0) {
		if(xdest + w > 0) {
			w += xdest;
			xoffs += -xdest;
			xdest = 0;
		} else {
			return 0;
		}
	} else if(xdest >= dst->w) {
		return 0;
	}
	if(xdest + w > dst->w) {
		w = dst->w - xdest;
	}
	if(xoffs >= src->w) {
		return 0;
	} else if(xoffs + w > src->w) {
		w = src->w - xoffs;
	}

	uint8_t *dstptr;
	uint8_t *srcptr;

	if(xdest & 1) {
		/* this will render the leftmost column */
		dstptr = (uint8_t*)(dst->data + 
				ydest * dst->pitch + 
				xdest / 2);
		srcptr = (uint8_t*)(src->data +
				yoffs * src->pitch +
				xoffs / 2 );
		if(xoffs & 1) {
			for(y = 0; y < h; y++) {
				*dstptr &= 0xF0;
				*dstptr |= *srcptr & 0x0F;
				dstptr += dst->pitch;
				srcptr += src->pitch;
			}
		} else {
			for(y = 0; y < h; y++) {
				*dstptr &= 0xF0;
				*dstptr |= *srcptr >> 4;
				dstptr += dst->pitch;
				srcptr += src->pitch;
			}
		}
		xdest++;
		xoffs++;
		w--;
	}

	dstptr = (uint8_t*)(dst->data + 
			ydest * dst->pitch + 
			xdest / 2);
	srcptr = (uint8_t*)(src->data +
			yoffs * src->pitch +
			xoffs / 2 );

	if(xoffs & 1) {
		for(y = 0; y < h; y++) {
			for(x = 0; x < (w / 2); x++) {
				dstptr[x] = (srcptr[x] << 4) | (srcptr[x+1] >> 4);
			}
			if(w & 1) {
				dstptr[x] &= 0x0F;
				dstptr[x] |= srcptr[x] << 4;
			}
			dstptr += dst->pitch;
			srcptr += src->pitch;
		}
	} else {
		for(y = 0; y < h; y++) {
			memcpy(dstptr, srcptr, w / 2);
			if(w & 1) {
				dstptr[w/2] &= 0x0F;
				dstptr[w/2] |= (srcptr[w/2] & 0xF0);
			}
			dstptr += dst->pitch;
			srcptr += src->pitch;
		}
	}
	return 0;
}

static int addblitToBuffer(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	BlitBuffer *src = (BlitBuffer*) luaL_checkudata(L, 2, "blitbuffer");
	int xdest = luaL_checkint(L, 3);
	int ydest = luaL_checkint(L, 4);
	int xoffs = luaL_checkint(L, 5);
	int yoffs = luaL_checkint(L, 6);
	int w = luaL_checkint(L, 7);
	int h = luaL_checkint(L, 8);
	int x, y;

	// check bounds
	if(yoffs >= src->h) {
		return 0;
	} else if(yoffs + h > src->h) {
		h = src->h - yoffs;
	}
	if(ydest >= dst->h) {
		return 0;
	} else if(ydest + h > dst->h) {
		h = dst->h - ydest;
	}
	if(xoffs >= src->w) {
		return 0;
	} else if(xoffs + w > src->w) {
		w = src->w - xoffs;
	}
	if(xdest >= dst->w) {
		return 0;
	} else if(xdest + w > dst->w) {
		w = dst->w - xdest;
	}

	uint8_t *dstptr;
	uint8_t *srcptr;

	if(xdest & 1) {
		/* this will render the leftmost column */
		dstptr = (uint8_t*)(dst->data + 
				ydest * dst->pitch + 
				xdest / 2);
		srcptr = (uint8_t*)(src->data +
				yoffs * src->pitch +
				xoffs / 2 );
		if(xoffs & 1) {
			for(y = 0; y < h; y++) {
				uint8_t v = (*dstptr & 0x0F) + (*srcptr & 0x0F);
				*dstptr = (*dstptr & 0xF0) | (v < 0x0F ? v : 0x0F);
				dstptr += dst->pitch;
				srcptr += src->pitch;
			}
		} else {
			for(y = 0; y < h; y++) {
				uint8_t v = (*dstptr & 0x0F) + (*srcptr >> 4);
				*dstptr = (*dstptr & 0xF0) | (v < 0x0F ? v : 0x0F);
				dstptr += dst->pitch;
				srcptr += src->pitch;
			}
		}
		xdest++;
		xoffs++;
		w--;
	}

	dstptr = (uint8_t*)(dst->data + 
			ydest * dst->pitch + 
			xdest / 2);
	srcptr = (uint8_t*)(src->data +
			yoffs * src->pitch +
			xoffs / 2 );

	if(xoffs & 1) {
		for(y = 0; y < h; y++) {
			for(x = 0; x < (w / 2); x++) {
				uint16_t v1 = (dstptr[x] & 0xF0) + ((srcptr[x] & 0x0F) << 4);
				uint8_t v2 = (dstptr[x] & 0x0F) + (srcptr[x+1] >> 4);
				dstptr[x] = (v1 < 0xF0 ? v1 : 0xF0) | (v2 < 0x0F ? v2 : 0x0F);
			}
			if(w & 1) {
				uint16_t v1 = (dstptr[x] & 0xF0) + ((srcptr[x] & 0x0F) << 4);
				dstptr[x] = (dstptr[x] & 0x0F) | (v1 < 0xF0 ? v1 : 0xF0);
			}
			dstptr += dst->pitch;
			srcptr += src->pitch;
		}
	} else {
		for(y = 0; y < h; y++) {
			for(x = 0; x < (w / 2); x++) {
				uint16_t v1 = (dstptr[x] & 0xF0) + (srcptr[x] & 0xF0);
				uint8_t v2 = (dstptr[x] & 0x0F) + (srcptr[x] & 0x0F);
				dstptr[x] = (v1 < 0xF0 ? v1 : 0xF0) | (v2 < 0x0F ? v2 : 0x0F);
			}
			if(w & 1) {
				uint16_t v1 = (dstptr[x] & 0xF0) + (srcptr[x] & 0xF0);
				dstptr[x] = (dstptr[x] & 0x0F) | (v1 < 0xF0 ? v1 : 0xF0);
			}
			dstptr += dst->pitch;
			srcptr += src->pitch;
		}
	}
	return 0;
}

static int paintRect(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	int x = luaL_checkint(L, 2);
	int y = luaL_checkint(L, 3);
	int w = luaL_checkint(L, 4);
	int h = luaL_checkint(L, 5);
	int c = luaL_checkint(L, 6);
	uint8_t *dstptr;

	int cy;
	if(w <= 0 || h <= 0 || x >= dst->w || y >= dst->h) {
		return 0;
	}
	if(x + w > dst->w) {
		w = dst->w - x;
	}
	if(y + h > dst->h) {
		h = dst->h - y;
	}

	if(x & 1) {
		/* This will render the leftmost column
		 * in the case when x is odd. After this,
		 * x will become even. */
		dstptr = (uint8_t*)(dst->data + 
				y * dst->pitch + 
				x / 2);
		for(cy = 0; cy < h; cy++) {
			*dstptr &= 0xF0;
			*dstptr |= c;
			dstptr += dst->pitch;
		}
		x++;
		w--;
	}
	dstptr = (uint8_t*)(dst->data + 
			y * dst->pitch + 
			x / 2);
	for(cy = 0; cy < h; cy++) {
		memset(dstptr, c | (c << 4), w / 2);
		dstptr += dst->pitch;
	}
	if(w & 1) {
		/* This will render the rightmost column 
		 * in the case when (w & 1) && !(x & 1) or
		 * !(w & 1) && (x & 1). */
		dstptr = (uint8_t*)(dst->data + 
				y * dst->pitch + 
				(x + w) / 2);
		for(cy = 0; cy < h; cy++) {
			*dstptr &= 0x0F;
			*dstptr |= (c << 4);
			dstptr += dst->pitch;
		}
	}
	return 0;
}

static const struct luaL_reg blitbuffer_func[] = {
	{"new", newBlitBuffer},
	{NULL, NULL}
};

static const struct luaL_reg blitbuffer_meth[] = {
	{"getWidth", getWidth},
	{"getHeight", getHeight},
	{"blitFrom", blitToBuffer},
	{"addblitFrom", addblitToBuffer},
	{"blitFullFrom", blitFullToBuffer},
	{"paintRect", paintRect},
	{"free", freeBlitBuffer},
	{"__gc", freeBlitBuffer},
	{NULL, NULL}
};

int luaopen_blitbuffer(lua_State *L) {
	luaL_newmetatable(L, "blitbuffer");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, blitbuffer_meth);
	lua_setglobal(L, "blitbuffer");
	luaL_register(L, "Blitbuffer", blitbuffer_func);

	return 1;
}
