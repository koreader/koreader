# Porting

This page aims to provide guidance on how to port KOReader to other platforms.

There are mainly two modules that you need to take care of: input and output.
After you finish these two, KOReader should have no problem running on your
platform. Feel free to open issues in our issue tracker if you need further help on this topic :)


## Output Module

### Current mxcfb eInk devices

KOReader uses the Linux framebuffer to control eInk devices, so the output module for mxcfb (i.e., those based on Freescale/NXP hardware) devices is
[base/ffi/framebuffer_mxcfb.lua](https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer_mxcfb.lua).

Most common bitdepths are supported, although no devices should actually be using anything other than 8bpp, 16bpp and 32bpp.
For 8bpp, we assume the grayscale palette is NOT inverted, although support for an inverted palette can be implemented (see the Kindle 4).
At 32bpp, we generally assume the pixel format is BGRA, and we honor Alpha, despite it being effectively ignored by the display (see Kobos).
At 16bpp, we assume the pixel format is RGB565.

For obvious performance reasons, we prefer 8bpp, and we will attempt to enforce that on devices which are not natively running at that depth (i.e., Kobos).
As explained below, the same considerations should be kept in mind regarding the effective 16c palette of eInk screens.
When we're in control of the data, we attempt to always use "perfect" in-palette colors (c.f., the COLOR constants in the BlitBuffer module).
Otherwise, when there'd be signficiant gain in doing so (i.e., when displaying mainly image content), we attempt to make use of dithering,
ideally offloaded to the hardware when supported.

The actual framebuffer content is then refreshed (i.e., displayed) via device-specific ioctls, making the best effort in using device-specific capabilities,
whether that be optimized waveform modes, hardware dithering or hardware inversion.

### Legacy einkfb eInk devices

KOReader uses the Linux framebuffer to control eInk devices, so the output module for legacy einkfb devices is
[base/ffi/framebuffer_einkfb.lua](https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer_einkfb.lua).

Following are the framebuffers that `framebuffer_einkfb.lua` currently supports:

  * 4bpp framebuffer (palette is always inverted)
  * 16c 8bpp framebuffer (inverted grayscale palette)
  * 16c 8bpp framebuffer

For 4bpp framebuffers, it means every pixel is represented with 4 bits, so we
have 2 pixels in 1 byte. That also effectively limits the palette to 16 colors.
The inverted part means all the bits are flipped (`^ 0xFF`) in the framebuffer.
For example, two pixels `[0x00, 0xF0]` will be stored as `[0xFF, 0x0F]` in framebuffer.

For 8bpp framebuffers, it means each pixel is instead stored in 1 byte, making addressing much simpler.
The effective color palette of the display is still limited to 16 shades of gray:
it will do a decimating quantization pass on its own on refresh.
So, while a black pixel will indeed be `0x00`, any color value < `0x11`
(the next effective shade of gray in the palette) will be displayed as pure black, too.
If the palette is expected to be inverted, then all the bits are
flipped in the same way as done on a 4bpp framebuffer.

The actual framebuffer content is then refreshed (i.e., displayed) via device-specific ioctls.

## Blitter Module

All the intermediary buffers are handled in a pixel format that matches the output module in use as closely as possible.
The magic happens in [base/ffi/blitbuffer.lua](https://github.com/koreader/koreader-base/blob/master/ffi/blitbuffer.lua),
with some help from the [LinuxFB](https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer_linux.lua) frontend to the output modules.

Note that on most devices, a [C version](https://github.com/koreader/koreader-base/blob/master/blitbuffer.c) is used instead for more consistent performance.

## Input Module

We have a `input.c` module in [koreader-base][kb-framework] that reads input
events from Linux's input system and pass to Lua frontend. Basically, you don't
need to change on that module because it should support most of the events.

For this part, the file you have to hack on is [`koreader/frontend/ui/input.lua`](https://github.com/koreader/koreader/blob/master/frontend/ui/input.lua).

Firstly, you need to tell which input device to open on KOReader start. All the
input devices are opened in `Input:init()` function.

Next, you might need to define `Input:eventAdjustHook()` function in
`Input:init()` method. We use this hook function to translates events into a
format that KOReader understands. You can look at the KindleTouch initialization code for real example.

For Kobo devices (Mini, Touch, Glo and Aura HD) the function `Input:eventAdjustHook()` was skipped and the functions `Input:init()` and `Input:handleTypeBTouchEv` were changed to allow the single touch protocol. For Kobo Aura with multitouch support an extra function `Input:handlePhoenixTouchEv` was added.

Linux supports two kinds of Multi-touch protocols:

 * <http://www.kernel.org/doc/Documentation/input/multi-touch-protocol.txt>

Currently, KOReader supports gesture detection of protocol B, so if your device sends out
protocol A, you need to make a variant of function `Input:handleTouchEv()` (like `Input:handleTypeBTouchEv` and `Input:handlePhoenixTouchEv`) and simulate protocol B.
Also you are welcome to send a PR that adds protocol A support to KOReader.

More information on Linux's input system:

 * <http://www.kernel.org/doc/Documentation/input/event-codes.txt>
 * <http://www.kernel.org/doc/Documentation/input/input.txt>

[kb-framework]:https://github.com/koreader/koreader-base
