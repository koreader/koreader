# Porting

This page aims to provide guidance on how to port KOReader to other platforms.

There are mainly two modules that you need to take care of: input and output.
After you finish these two, KOReader should have no problem running on your
platform. Feel free to open issues in our issue tracker if you need further help on this topic :)


## Output Module

KOReader uses the Linux framebuffer to control eInk devices, so the output module here is
[base/ffi/framebuffer_einkfb.lua](https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer_einkfb.lua).

Following are the framebuffers that `framebuffer_einkfb.lua` currently supports:

  * 4BPP framebuffer (palette is always inverted)
  * 16c 8BPP framebuffer (inverted grayscale palette)
  * 16c 8BPP framebuffer

For 4BPP framebuffers, it means every pixel is represented with 4 bits, so we
have 2 pixels in 1 byte. That also effectively limits the palette to 16 colors.
The inverted part means all the bits are flipped (`^ 0xFF`) in the framebuffer.
For example, two pixels `[0x00, 0xF0]` will be stored as `0xFF0F` in framebuffer.

For 8BPP framebuffers, it means each pixel is instead stored in 1 byte.
The effective color palette of the display is still limited to 16 shades of gray:
it will do a decimating quantization pass on its own on refresh.
So, while a black pixel will indeed be `0x00`, any color value < `0x11`
(the next effective shade of gray in the palette) will be displayed as pure black, too.
If the palette is expected to be inverted, then all the bits are
flipped in the same way as done on a 4BPP framebuffer.

The actual framebuffer content is then refreshed (i.e., displayed) via device-specific ioctls.

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
