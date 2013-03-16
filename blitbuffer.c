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

/* debugging statements, switch as needed */
#ifdef DEBUG
#define ASSERT_BLITBUFFER_BOUNDARIES(bb,bb_ptr) \
	if((bb_ptr < bb->data) || (bb_ptr >= (bb->data + bb->pitch * bb->h))) { \
		fprintf(stderr, "violated blitbuffer constraints in file %s, line %d!\r\n", __FILE__, __LINE__); exit(1); \
	}
#else // DEBUG
#define ASSERT_BLITBUFFER_BOUNDARIES(bb,bb_ptr) {}
#endif // DEBUG

inline int getPixel(BlitBuffer *bb, int x, int y) {
	uint8_t *dstptr = (uint8_t*)(bb->data) + (y * bb->pitch) + (x / 2);
	ASSERT_BLITBUFFER_BOUNDARIES(bb, dstptr);

	if(x % 2 == 0) {
		return (*dstptr & 0xF0) >> 4;
	} else {
		return *dstptr & 0x0F;
	}
}

inline void setPixel(BlitBuffer *bb, int x, int y, int c) {
	uint8_t *dstptr = (uint8_t*)(bb->data) + (y * bb->pitch) + (x / 2);
	ASSERT_BLITBUFFER_BOUNDARIES(bb, dstptr);

	if(x % 2 == 0) {
		*dstptr &= 0x0F;
		*dstptr |= c << 4;
	} else {
		*dstptr &= 0xF0;
		*dstptr |= c;
	}
}

/*
 * if ptich equals zero, we calculate it as (w + 1) / 2
 */
int newBlitBufferNative(lua_State *L, int w, int h, int pitch, BlitBuffer **newBuffer) {
	BlitBuffer *bb = (BlitBuffer*) lua_newuserdata(L, sizeof(BlitBuffer));
	luaL_getmetatable(L, "blitbuffer");
	lua_setmetatable(L, -2);

	bb->w = w;
	bb->pitch = ((pitch == 0) ? ((w + 1) / 2) : pitch);
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
	int pitch = luaL_optint(L, 3, 0);
	return newBlitBufferNative(L, w, h, pitch, NULL);
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

	// should be save if called twice
	if(bb->allocated && bb->data != NULL) {
		free(bb->data);
		bb->data = NULL;
	}
	return 0;
}

static int blitFullToBuffer(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	BlitBuffer *src = (BlitBuffer*) luaL_checkudata(L, 2, "blitbuffer");

	if(src->w != dst->w || src->h != dst->h || src->pitch != dst->pitch) {
		return luaL_error(L, "dst and src blitbuffer size not match!");
	}

	memcpy(dst->data, src->data, src->pitch * src->h);
	return 0;
}

/**
* check/adapt boundaries for blitting operations
*
* @return 0 if no blitting is needed, 1 otherwise
*/
int fitBlitBufferBoundaries(BlitBuffer* src, BlitBuffer* dst, int* xdest, int* ydest, int* xoffs, int* yoffs, int* w, int* h) {
	// check bounds
	if(*ydest < 0) {
		// negative ydest, try to compensate
		if(*ydest + *h > 0) {
			// shrink h by negative dest offset
			*h += *ydest;
			// extend source offset
			*yoffs += -(*ydest);
			*ydest = 0;
		} else {
			// effectively no height
			return 0;
		}
	} else if(*ydest >= dst->h) {
		// we're told to paint to off-bound target coords
		return 0;
	}
	if(*ydest + *h > dst->h) {
		// clamp height if too large for target size
		*h = dst->h - *ydest;
	}
	if(*yoffs >= src->h) {
		// recalculated source offset is out of bounds
		return 0;
	} else if(*yoffs + *h > src->h) {
		// clamp height if too large for source size
		*h = src->h - *yoffs;
	}
	// same stuff for x coords:
	if(*xdest < 0) {
		if(*xdest + *w > 0) {
			*w += *xdest;
			*xoffs += -(*xdest);
			*xdest = 0;
		} else {
			return 0;
		}
	} else if(*xdest >= dst->w) {
		return 0;
	}
	if(*xdest + *w > dst->w) {
		*w = dst->w - *xdest;
	}
	if(*xoffs >= src->w) {
		return 0;
	} else if(*xoffs + *w > src->w) {
		*w = src->w - *xoffs;
	}
	return 1; // continue processing
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

	uint8_t *dstptr;
	uint8_t *srcptr;

	if(!fitBlitBufferBoundaries(src, dst, &xdest, &ydest, &xoffs, &yoffs, &w, &h))
		return 0;

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
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
				*dstptr &= 0xF0;
				*dstptr |= *srcptr & 0x0F;
				dstptr += dst->pitch;
				srcptr += src->pitch;
			}
		} else {
			for(y = 0; y < h; y++) {
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
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
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
			ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
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
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
			ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
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

static int rotate_table[3][2] = {
	/* cos, sin */
	{0, 1}, /* 90 degree */
	{-1, 0}, /* 180 degree */
	{0, -1}, /* 270 degree */
};

/** @brief rotate and blit to buffer
 *
 *  Currently, only support rotation of 90, 180, 270 degree.
 * */
static int blitToBufferRotate(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	BlitBuffer *src = (BlitBuffer*) luaL_checkudata(L, 2, "blitbuffer");
	int degree = luaL_checkint(L, 3);
	int i, j, x, y, /* src and dst coordinate */
		x_adj = 0, y_adj = 0; /* value for translation after rotatation */
	int cosT = rotate_table[degree/90-1][0],
		sinT = rotate_table[degree/90-1][1],
		u, v;

	switch (degree) {
		case 180:
			y_adj = dst->h-1;
		case 90:
			x_adj = dst->w-1;
			break;
		case 270:
			y_adj = dst->h-1;
			break;
	}

	u = x_adj;
	v = y_adj;
	for (j = 0; j < src->h; j++) {
		/*
		 * x = -sinT * j + x_adj;
		 * y = cosT * j + y_adj;
		 */
		x = u;
		y = v;
		for (i = 0; i < src->w; i++) {
			/* 
			 * each (i, j) maps to (x, y)
			 * x = cosT * i - sinT * j + x_adj;
			 * y = cosT * j + sinT * i + y_adj;
			 */
			setPixel(dst, x, y, getPixel(src, i, j));
			x += cosT;
			y += sinT;
		}
		u -= sinT;
		v += cosT;
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
	double p = luaL_checknumber(L, 9);
	int x, y;

	uint8_t *dstptr;
	uint8_t *srcptr;

	if(!fitBlitBufferBoundaries(src, dst, &xdest, &ydest, &xoffs, &yoffs, &w, &h))
		return 0;

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
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
				uint8_t v = (int)((*dstptr & 0x0F)*(1-p) + (*srcptr & 0x0F)*p);
				*dstptr = (*dstptr & 0xF0) | (v < 0x0F ? v : 0x0F);
				dstptr += dst->pitch;
				srcptr += src->pitch;
			}
		} else {
			for(y = 0; y < h; y++) {
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
				uint8_t v = (int)((*dstptr & 0x0F)*(1-p) + (*srcptr >> 4)*p);
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
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
				uint16_t v1 = (int)((dstptr[x] & 0xF0)*(1-p) + ((srcptr[x] & 0x0F) << 4)*p);
				uint8_t v2 = (int)((dstptr[x] & 0x0F)*(1-p) + (srcptr[x+1] >> 4)*p);
				dstptr[x] = (v1 < 0xF0 ? v1 : 0xF0) | (v2 < 0x0F ? v2 : 0x0F);
			}
			if(w & 1) {
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
				uint16_t v1 = (int)((dstptr[x] & 0xF0)*(1-p) + ((srcptr[x] & 0x0F) << 4)*p);
				dstptr[x] = (dstptr[x] & 0x0F) | (v1 < 0xF0 ? v1 : 0xF0);
			}
			dstptr += dst->pitch;
			srcptr += src->pitch;
		}
	} else {
		for(y = 0; y < h; y++) {
			for(x = 0; x < (w / 2); x++) {
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
				uint16_t v1 = (int)((dstptr[x] & 0xF0)*(1-p) + (srcptr[x] & 0xF0)*p);
				uint8_t v2 = (int)((dstptr[x] & 0x0F)*(1-p) + (srcptr[x] & 0x0F)*p);
				dstptr[x] = (v1 < 0xF0 ? v1 : 0xF0) | (v2 < 0x0F ? v2 : 0x0F);
			}
			if(w & 1) {
				ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
				ASSERT_BLITBUFFER_BOUNDARIES(src, srcptr);
				uint16_t v1 = (int)((dstptr[x] & 0xF0)*(1-p) + (srcptr[x] & 0xF0)*p);
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

	if(x < 0) {
		if (x+w > 0) {
			w += x;
			x = 0;
		} else {
			return 0;
		}
	}

	if(y < 0) {
		if (y+h > 0) {
			h += y;
			y = 0;
		} else {
			return 0;
		}
	}

	if(x + w > dst->w) {
		w = dst->w - x;
	}
	if(y + h > dst->h) {
		h = dst->h - y;
	}

	if(w <= 0 || h <= 0 || x >= dst->w || y >= dst->h) {
		return 0;
	}

	if(x & 1) {
		/* This will render the leftmost column
		 * in the case when x is odd. After this,
		 * x will become even. */
		dstptr = (uint8_t*)(dst->data +
				y * dst->pitch +
				x / 2);
		for(cy = 0; cy < h; cy++) {
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
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
		ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
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
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
			*dstptr &= 0x0F;
			*dstptr |= (c << 4);
			dstptr += dst->pitch;
		}
	}
	return 0;
}

static int invertRect(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	int x = luaL_checkint(L, 2);
	int y = luaL_checkint(L, 3);
	int w = luaL_checkint(L, 4);
	int h = luaL_checkint(L, 5);
	uint8_t *dstptr;

	int cy, cx;

	//printf("## invertRect x=%d y=%d w=%d h=%d\n",x,y,w,h);

	if (x < 0) {
		if ( x + w > 0 ) {
			w = w + x;
			x = 0;
		} else {
			//printf("## invertRect x out of bound\n");
			return 0;
		}
	}

	if (y < 0) {
		if ( y + h > 0 ) {
			h = h + y;
			y = 0;
		} else {
			//printf("## invertRect y out of bound\n");
			return 0;
		}
	}

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
		/* This will invert the leftmost column
		 * in the case when x is odd. After this,
		 * x will become even. */
		dstptr = (uint8_t*)(dst->data + 
				y * dst->pitch + 
				x / 2);
		for(cy = 0; cy < h; cy++) {
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
			*dstptr ^= 0x0F;
			dstptr += dst->pitch;
		}
		x++;
		w--;
	}
	dstptr = (uint8_t*)(dst->data + 
			y * dst->pitch + 
			x / 2);
	for(cy = 0; cy < h; cy++) {
		for(cx = 0; cx < w/2; cx++) {
			ASSERT_BLITBUFFER_BOUNDARIES(dst, (dstptr+cx));
			*(dstptr+cx) ^=  0xFF;
		}
		dstptr += dst->pitch;
	}
	if(w & 1) {
		/* This will invert the rightmost column 
		 * in the case when (w & 1) && !(x & 1) or
		 * !(w & 1) && (x & 1). */
		dstptr = (uint8_t*)(dst->data + 
				y * dst->pitch + 
				(x + w) / 2);
		for(cy = 0; cy < h; cy++) {
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
			*dstptr ^= 0xF0;
			dstptr += dst->pitch;
		}
	}
	return 0;
}

static int dimRect(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	int x = luaL_checkint(L, 2);
	int y = luaL_checkint(L, 3);
	int w = luaL_checkint(L, 4);
	int h = luaL_checkint(L, 5);
	uint8_t *dstptr;

	int cy, cx;

	if (x < 0) {
		if ( x + w > 0 ) {
			w = w + x;
			x = 0;
		} else {
			//printf("## invertRect x out of bound\n");
			return 0;
		}
	}

	if (y < 0) {
		if ( y + h > 0 ) {
			h = h + y;
			y = 0;
		} else {
			//printf("## invertRect y out of bound\n");
			return 0;
		}
	}

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
		/* This will dimm the leftmost column
		 * in the case when x is odd. After this,
		 * x will become even. */
		dstptr = (uint8_t*)(dst->data + 
				y * dst->pitch + 
				x / 2);
		for(cy = 0; cy < h; cy++) {
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
			int px = *dstptr & 0x0F;
			*dstptr &= 0xF0 | px >> 1;
			dstptr += dst->pitch;
		}
		x++;
		w--;
	}
	dstptr = (uint8_t*)(dst->data + 
			y * dst->pitch + 
			x / 2);
	for(cy = 0; cy < h; cy++) {
		for(cx = 0; cx < w/2; cx++) {
			ASSERT_BLITBUFFER_BOUNDARIES(dst, (dstptr+cx));
			*(dstptr+cx) =
				( *(dstptr+cx) >> 1 ) & 0xF0 |
				( *(dstptr+cx) & 0x0F ) >> 1;
		}
		dstptr += dst->pitch;
	}
	if(w & 1) {
		/* This will dimm the rightmost column 
		 * in the case when (w & 1) && !(x & 1) or
		 * !(w & 1) && (x & 1). */
		dstptr = (uint8_t*)(dst->data + 
				y * dst->pitch + 
				(x + w) / 2);
		for(cy = 0; cy < h; cy++) {
			ASSERT_BLITBUFFER_BOUNDARIES(dst, dstptr);
			int px = *dstptr & 0xF0;
			*dstptr &= 0x0F | ( px >> 1 & 0xF0 );
			dstptr += dst->pitch;
		}
	}
	return 0;
}

/*
 * @r: radius
 * @c: color of the line to draw
 * @w: width of the line to draw
 */
static int paintCircle(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	int center_x = luaL_checkint(L, 2);
	int center_y = luaL_checkint(L, 3);
	int r = luaL_checkint(L, 4);
	int c = luaL_optint(L, 5, 15);
	int w = luaL_optint(L, 6, r);

	if( (center_x + r > dst->h) || (center_x - r < 0) ||
		(center_y + r > dst->w) || (center_y - r < 0) ||
		(r == 0)) {
		return 0;
	}
	if(w > r) {
		w = r;
	}


	int tmp_y;
	/* for outer circle */
	int x = 0, y = r;	
	float delta = 5/4 - r;
	/* for inter circle */
	int r2 = r - w;
	int x2 = 0, y2 = r2;	
	float delta2 = 5/4 - r;

	/* draw two axles */
	for(tmp_y = r; tmp_y > r2; tmp_y--) {
		setPixel(dst, center_x+0, center_y+tmp_y, c);
		setPixel(dst, center_x-0, center_y-tmp_y, c);
		setPixel(dst, center_x+tmp_y, center_y+0, c);
		setPixel(dst, center_x-tmp_y, center_y-0, c);
	}

	while(x < y) {
		/* decrease y if we are out of circle */
		x++;
		if (delta > 0) {
			y--;
			delta = delta + 2*x - 2*y + 2;
		} else {
			delta = delta + 2*x + 1;
		}

		/* inner circle finished drawing, increase y linearly for filling */
		if(x2 > y2) {
			y2++;
			x2++;
		} else {
			x2++;
			if (delta2 > 0) {
				y2--;
				delta2 = delta2 + 2*x2 - 2*y2 + 2;
			} else {
				delta2 = delta2 + 2*x2 + 1;
			}
		}

		for(tmp_y = y; tmp_y > y2; tmp_y--) {
			setPixel(dst, center_x+x, center_y+tmp_y, c);
			setPixel(dst, center_x+tmp_y, center_y+x, c);

			setPixel(dst, center_x+tmp_y, center_y-x, c);
			setPixel(dst, center_x+x, center_y-tmp_y, c);

			setPixel(dst, center_x-x, center_y-tmp_y, c);
			setPixel(dst, center_x-tmp_y, center_y-x, c);

			setPixel(dst, center_x-tmp_y, center_y+x, c);
			setPixel(dst, center_x-x, center_y+tmp_y, c);
		}
	}
	if(r == w) {
		setPixel(dst, center_x, center_y, c);
	}
	return 0;
}

static int paintRoundedCorner(lua_State *L) {
	BlitBuffer *dst = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");
	int off_x = luaL_checkint(L, 2);
	int off_y = luaL_checkint(L, 3);
	int w = luaL_checkint(L, 4);
	int h = luaL_checkint(L, 5);
	int bw = luaL_checkint(L, 6);
	int r = luaL_checkint(L, 7);
	int c = luaL_optint(L, 8, 15);

	if((2*r > h) || (2*r > w) || (r == 0)) {
		return 0;
	}
	if(r > h) {
		r = h;
	}
	if(r > w) {
		r = w;
	}
	if(bw > r) {
		bw = r;
	}


	int tmp_y;
	/* for outer circle */
	int x = 0, y = r;	
	float delta = 5/4 - r;
	/* for inter circle */
	int r2 = r - bw;
	int x2 = 0, y2 = r2;	
	float delta2 = 5/4 - r;

	/* draw two axles */
	/*for(tmp_y = r; tmp_y > r2; tmp_y--) {*/
		/*setPixel(dst, (w-r)+off_x+0, (h-r)+off_y+tmp_y-1, c);*/
		/*setPixel(dst, (w-r)+off_x-0, (r)+off_y-tmp_y, c);*/
		/*setPixel(dst, (w-r)+off_x+tmp_y, (h-r)+off_y+0, c);*/
		/*setPixel(dst, (r)+off_x-tmp_y, (h-r)+off_y-0-1, c);*/
	/*}*/

	while(x < y) {
		/* decrease y if we are out of circle */
		x++;
		if (delta > 0) {
			y--;
			delta = delta + 2*x - 2*y + 2;
		} else {
			delta = delta + 2*x + 1;
		}

		/* inner circle finished drawing, increase y linearly for filling */
		if(x2 > y2) {
			y2++;
			x2++;
		} else {
			x2++;
			if (delta2 > 0) {
				y2--;
				delta2 = delta2 + 2*x2 - 2*y2 + 2;
			} else {
				delta2 = delta2 + 2*x2 + 1;
			}
		}

		for(tmp_y = y; tmp_y > y2; tmp_y--) {
			setPixel(dst, (w-r)+off_x+x-1, (h-r)+off_y+tmp_y-1, c);
			setPixel(dst, (w-r)+off_x+tmp_y-1, (h-r)+off_y+x-1, c);

			setPixel(dst, (w-r)+off_x+tmp_y-1, (r)+off_y-x, c);
			setPixel(dst, (w-r)+off_x+x-1, (r)+off_y-tmp_y, c);

			setPixel(dst, (r)+off_x-x, (r)+off_y-tmp_y, c);
			setPixel(dst, (r)+off_x-tmp_y, (r)+off_y-x, c);

			setPixel(dst, (r)+off_x-tmp_y, (h-r)+off_y+x-1, c);
			setPixel(dst, (r)+off_x-x, (h-r)+off_y+tmp_y-1, c);
		}
	}
	return 0;
}

static const struct luaL_Reg blitbuffer_func[] = {
	{"new", newBlitBuffer},
	{NULL, NULL}
};

static const struct luaL_Reg blitbuffer_meth[] = {
	{"getWidth", getWidth},
	{"getHeight", getHeight},
	{"blitFrom", blitToBuffer},
	{"blitFromRotate", blitToBufferRotate},
	{"addblitFrom", addblitToBuffer},
	{"blitFullFrom", blitFullToBuffer},
	{"paintRect", paintRect},
	{"paintCircle", paintCircle},
	{"paintRoundedCorner", paintRoundedCorner},
	{"invertRect", invertRect},
	{"dimRect", dimRect},
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
