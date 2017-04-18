# Porting

This page aims to provide guidance on how to port KOReader to other platforms.

There are mainly two modules that you need to take care of: input and output.
After you finish these two, KOReader should have no problem running on your
platform. Feel free to open issues in our issue tracker if you need further help on this topic :)


## Output Module

KOReader uses framebuffer to control EInk devices, so the output module here is
[base/ffi/framebuffer_einkfb.lua](https://github.com/koreader/koreader-base/blob/master/ffi/framebuffer_einkfb.lua).

Following are the framebuffers that `framebuffer_einkfb.lua` currently supports:

  * 4BPP inverted framebuffer
  * 16 scale 8BPP inverted framebuffer
  * 16 scale 8BPP framebuffer

For 4BPP framebuffer, it means every pixel is represented with 4 bits, so we
have 2 pixels in 1 byte. So the color depth is 16. The inverted part means all
the bits are flipped in the framebuffer. For example, two pixels `[0x00, 0xf0]`
will be stored as `0xff0f` in framebuffer.

For 16 scale 8BPP framebuffer, it means each pixel is instead stored in 1 byte,
but the color depth is still 16 (4bits). Since 1 byte has 8 bits, so to fill
up the remaining space, the most significant 4 bits is a copy of the least
significant one. For example, pixel with grey scale 15 will be represented as
`0xffff`. If it's a inverted 16 scale 8BPP framebuffer, then all the bits are
flipped in the same way as 4BPP inverted framebuffer does.

If your device's framebuffer does not fit into any of the categories above,
then you need to add a new transformation function in `framebuffer_einkfb.lua`.

The `framebuffer_einkfb.lua` module works in following ways for non 4BPP framebuffers:

  * a shadow buffer is created and structured as 4BPP inverted framebuffer.
  * all updates on screen bitmap are temporally written into the shadow buffer.
  * each time we want to reflect the updated bitmap on screen, we translate the shadow buffer into a format that the real framebuffer understands and write into the mapped memory region. (varies on devices)
  * call ioctl system call to refresh EInk screen. (varies on devices)

KOReader will handle the 4BPP shadow buffer for you, all you need to do is to
teach `framebuffer_einkfb.lua` how to control the EInk screen and translate the 4BPP inverted
bitmap into the format that your framebuffer understands.

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
