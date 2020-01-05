menu-icon.png is post-processed with:

```bash
convert menu-icon.png -grayscale Rec709Luma -dither Riemersma -remap eink_cmap.gif -quality 75 png:menu-icon-grayscale.png
```

The intent being to grayscale, dither down to the 16c eInk palette, and save as a 16c paletted grayscale PNG.
Start from an RGB copy of the image if you end up with a 256c or sRGB PNG (check via IM's identify tool).

See https://www.mobileread.com/forums/showpost.php?p=3728291&postcount=17 for more details ;).

