#ifndef _EINKFB_H
#define _EINKFB_H

#define EINK_1BPP               1
#define EINK_2BPP               2
#define EINK_4BPP               4
#define EINK_8BPP               8
#define EINK_BPP_MAX            EINK_8BPP

#define EINK_WHITE              0x00    // For whacking all the pixels in a...
#define EINK_BLACK              0xFF    // ...byte (8, 4, 2, or 1) at once.

// Replace EINK_WHITE & EINK_BLACK with the following macros.
//
#define eink_white(b)           EINK_WHITE
#define eink_black(b)           EINK_BLACK

// For pixels (at bytes at a time) other than white/black, the following holds.
//
#define eink_pixels(b, p)       (p)

#define EINK_ORIENT_LANDSCAPE   1
#define EINK_ORIENT_PORTRAIT    0

#define BPP_SIZE(r, b)          (((r)*(b))/8)
#define BPP_MAX(b)              (1 << (b))

#define U_IN_RANGE(n, m, M)     ((((n) == 0) && ((m) == 0)) || (((n) > (m)) && ((n) <= (M))))
#define IN_RANGE(n, m, M)       (((n) >= (m)) && ((n) <= (M)))

#define ORIENTATION(x, y)       (((y) > (x)) ? EINK_ORIENT_PORTRAIT : EINK_ORIENT_LANDSCAPE)

struct raw_image_t
{
    int xres,		// image's width, in pixels
        yres,		// image's height
        bpp;		// image's pixel (bit) depth
    
    __u8  start[]; 	// actual start of image
};
typedef struct raw_image_t raw_image_t;

struct image_t
{
    int xres,       // image's visual width, in pixels
        xlen,       // image's actual width, used for rowbyte & memory size calculations
        yres,       // image's height
        bpp;        // image's pixel (bit) depth
        
    __u8  *start;     // pointer to start of image
};
typedef struct image_t image_t;

#define INIT_IMAGE_T() { 0, 0, 0, 0, NULL }

enum splash_screen_type
{
    // Simple (non-composite) splash screens.
    //
    //splash_screen_powering_off = 0,        // Deprecated.
    //splash_screen_powering_on,             // Deprecated.

    //splash_screen_powering_off_wireless,   // Deprecated.
    //splash_screen_powering_on_wireless,    // Deprecated.
    
    //splash_screen_exit,                    // Deprecated.
    splash_screen_logo = 5,
    
    //splash_screen_usb_internal,            // Deprecated.
    //splash_screen_usb_external,            // Deprecated.
    //splash_screen_usb,                     // Deprecated.
    
    //splash_screen_sleep,                   // Deprecated.
    //splash_screen_update,                  // Deprecated.
    
    //num_splash_screens,                    // Deprecated.

    // Composite splash screens & messages.
    //
    //splash_screen_drivemode_0,              // Deprecated.
    //splash_screen_drivemode_1,              // Deprecated.
    //splash_screen_drivemode_2,              // Deprecated.
    //splash_screen_drivemode_3,              // Deprecated.
    
    splash_screen_power_off_clear_screen = 16,// Message: clear screen and power down controller.
    //splash_screen_screen_saver_picture,     // Deprecated.
    
    splash_screen_shim_picture = 18,          // Message: shim wants a picture displayed.

    splash_screen_lowbatt,                    // Picture: Not composite, post-legacy ordering (Mario only).
    splash_screen_reboot,                     // Picture: Composite (not used on Fiona).
    
    splash_screen_update_initial,             // Composite software-update screens. 
    splash_screen_update_success,             //
    splash_screen_update_failure,             //
    splash_screen_update_failure_no_wait,     //
    
    splash_screen_repair_needed,              // More composite screens.
    splash_screen_boot,                       // 

    splash_screen_invalid = -1
};
typedef enum splash_screen_type splash_screen_type;

// Alias some of the legacy enumerations for Mario.
//
#define splash_screen_usb_recovery_util ((splash_screen_type)8) // splash_screen_usb

struct power_override_t
{
    u_int   cmd;
    u_long  arg;
};
typedef struct power_override_t power_override_t;

enum fx_type
{
    // Deprecated from the HAL, but still supported by the Shim.
    //
    fx_mask = 11,                           // Only for use with update_area_t's non-NULL buffer which_fx.
    fx_buf_is_mask = 14,                    // Same as fx_mask, but doesn't require a doubling (i.e., the buffer & mask are the same).
    
    fx_none = -1,                           // No legacy-FX to apply.
    
    // Screen-update FX, supported by HAL.
    //
    fx_flash = 20,                          // Only for use with update_area_t (for faking a flashing update).
    fx_invert = 21,                         // Only for use with update_area_t (only inverts output data).
    
    fx_update_partial = 0,                  // eInk GU/PU/MU-style (non-flashing) update.
    fx_update_full = 1                      // eInk GC-style (slower, flashing) update.
};
typedef enum fx_type fx_type;

// The only valid legacy-FX types for area updates are fx_mask and fx_buf_is_mask.
//
#define UPDATE_AREA_FX(f)                   \
    ((fx_mask == (f))                   ||  \
     (fx_buf_is_mask == (f)))

// The default ("none") for area updates is partial (non-flashing); full (flashing) updates
// are for FX and such (i.e., explicit completion is desired).
//
#define UPDATE_AREA_PART(f)                 \
    ((fx_none == (f))           ||          \
     (fx_update_partial == (f)))
     
#define UPDATE_AREA_FULL(f)                 \
    (UPDATE_AREA_FX(f)          ||          \
     (fx_update_full == (f)))

#define UPDATE_AREA_MODE(f)                 \
    (UPDATE_AREA_FULL(f) ? fx_update_full   \
                         : fx_update_partial)

// For use with the FBIO_EINK_UPDATE_DISPLAY ioctl.
//
#define UPDATE_PART(f)                      \
    (fx_update_partial == (f))
#define UPDATE_FULL(f)                      \
    (fx_update_full == (f))
#define UPDATE_MODE(f)                      \
    (UPDATE_FULL(f) ? fx_update_full        \
                    : fx_update_partial)

struct rect_t
{
    // Note:  The bottom-right (x2, y2) coordinate is actually such that (x2 - x1) and (y2 - y1)
    //        are xres and yres, respectively, when normally xres and yres would be
    //        (x2 - x1) + 1 and (y2 - y1) + 1, respectively.
    //
    int x1, y1, x2, y2;
};
typedef struct rect_t rect_t;

#define INIT_RECT_T() { 0, 0, 0, 0 }
#define MAX_EXCLUDE_RECTS 8

struct fx_t
{
    fx_type     update_mode,                // Screen-update FX:  fx_update_full | fx_update_partial.
                which_fx;                   // Shim (legacy) FX.
    
    int         num_exclude_rects;          // 0..MAX_EXCLUDE_RECTS.
    rect_t      exclude_rects[MAX_EXCLUDE_RECTS];
};
typedef struct fx_t fx_t;

#define INIT_FX_T()                     \
    { fx_update_partial, fx_none, 0, {  \
      INIT_RECT_T(),                    \
      INIT_RECT_T(),                    \
      INIT_RECT_T(),                    \
      INIT_RECT_T(),                    \
      INIT_RECT_T(),                    \
      INIT_RECT_T(),                    \
      INIT_RECT_T(),                    \
      INIT_RECT_T()} }

struct update_area_t
{
    // Note:  The bottom-right (x2, y2) coordinate is actually such that (x2 - x1) and (y2 - y1)
    //        are xres and yres, respectively, when normally xres and yres would be
    //        (x2 - x1) + 1 and (y2 - y1) + 1, respectively.
    //
    int         x1, y1,                     // Top-left...
                x2, y2;                     // ...bottom-right.
    
    fx_type     which_fx;                   // FX to use.
        
    __u8        *buffer;                    // If NULL, extract from framebuffer, top-left to bottom-right, by rowbytes.
};
typedef struct update_area_t update_area_t;

#define INIT_UPDATE_AREA_T() { 0, 0, 0, 0, fx_none, NULL }

struct progressbar_xy_t
{
    int         x, y;                       // Top-left corner of progressbar's position (ignores x for now).
};
typedef struct progressbar_xy_t progressbar_xy_t;

enum screen_saver_t
{
    screen_saver_invalid = 0,
    screen_saver_valid
};
typedef enum screen_saver_t screen_saver_t;

enum orientation_t
{
    orientation_portrait,
    orientation_portrait_upside_down,
    orientation_landscape,
    orientation_landscape_upside_down
};
typedef enum orientation_t orientation_t;

#define num_orientations (orientation_landscape_upside_down + 1)

#define ORIENTATION_PORTRAIT(o)     \
    ((orientation_portrait == (o))  || (orientation_portrait_upside_down == (o)))
    
#define ORIENTATION_LANDSCAPE(o)    \
    ((orientation_landscape == (o)) || (orientation_landscape_upside_down == (o)))
    
#define ORIENTATION_SAME(o1, o2)    \
    ((ORIENTATION_PORTRAIT(o1)  && ORIENTATION_PORTRAIT(o2)) || \
     (ORIENTATION_LANDSCAPE(o1) && ORIENTATION_LANDSCAPE(o2)))

enum einkfb_events_t
{
    einkfb_event_update_display = 0,        // FBIO_EINK_UPDATE_DISPLAY
    einkfb_event_update_display_area,       // FBIO_EINK_UPDATE_DISPLAY_AREA
    
    einkfb_event_blank_display,             // FBIOBLANK (fb.h)
    einkfb_event_rotate_display,            // FBIO_EINK_SET_DISPLAY_ORIENTATION
    
    einkfb_event_null = -1
};
typedef enum einkfb_events_t einkfb_events_t;

struct einkfb_event_t
{
    einkfb_events_t event;                  // Not all einkfb_events_t use all of the einkfb_event_t fields.
    
    fx_type         update_mode;            // Screen-update FX:  fx_update_full | fx_update_partial.
    
    // Note:  The bottom-right (x2, y2) coordinate is actually such that (x2 - x1) and (y2 - y1)
    //        are xres and yres, respectively, when normally xres and yres would be
    //        (x2 - x1) + 1 and (y2 - y1) + 1, respectively.
    //
    int             x1, y1,                 // Top-left...
                    x2, y2;                 // ...bottom-right.
                    
    orientation_t   orientation;            // Display rotated into this orientation.
};
typedef struct einkfb_event_t einkfb_event_t;

enum reboot_behavior_t
{
    reboot_screen_asis,
    reboot_screen_clear,
    reboot_screen_splash
};
typedef enum reboot_behavior_t reboot_behavior_t;

enum progressbar_badge_t
{
    progressbar_badge_success,
    progressbar_badge_failure,
    
    progressbar_badge_none
};
typedef enum progressbar_badge_t progressbar_badge_t;

enum sleep_behavior_t
{
    sleep_behavior_allow_sleep,
    sleep_behavior_prevent_sleep
};
typedef enum sleep_behavior_t sleep_behavior_t;

#define EINK_FRAME_BUFFER                   "/dev/fb/0"

#define SIZEOF_EINK_EVENT                   sizeof(einkfb_event_t)
#define EINK_EVENTS                         "/dev/misc/eink_events"

#define EINK_ROTATE_FILE                    "/sys/devices/platform/eink_fb.0/send_fake_rotate"
#define EINK_ROTATE_FILE_LEN                1
#define ORIENT_PORTRAIT                     orientation_portrait
#define ORIENT_PORTRAIT_UPSIDE_DOWN         orientation_portrait_upside_down
#define ORIENT_LANDSCAPE                    orientation_landscape
#define ORIENT_LANDSCAPE_UPSIDE_DOWN        orientation_landscape_upside_down
#define ORIENT_ASIS                         (-1)

#define EINK_USID_FILE                      "/var/local/eink/usid"

#define EINK_CLEAR_SCREEN                   0
#define EINK_CLEAR_BUFFER                   1

#define FBIO_EINK_SCREEN_CLEAR              FBIO_EINK_CLEAR_SCREEN, EINK_CLEAR_SCREEN
#define FBIO_EINK_BUFFER_CLEAR              FBIO_EINK_CLEAR_SCREEN, EINK_CLEAR_BUFFER

#define FBIO_MIN_SCREEN                     splash_screen_powering_off
#define FBIO_MAX_SCREEN                     num_splash_screens
#define FBIO_SCREEN_IN_RANGE(s)             \
    ((FBIO_MIN_SCREEN <= (s)) && (FBIO_MAX_SCREEN > (s)))

#define FBIO_MAGIC_NUMBER                   'F'

// Implemented in the eInk HAL.
//
#define FBIO_EINK_UPDATE_DISPLAY            _IO(FBIO_MAGIC_NUMBER, 0xdb) // 0x46db (fx_type)
#define FBIO_EINK_UPDATE_DISPLAY_AREA       _IO(FBIO_MAGIC_NUMBER, 0xdd) // 0x46dd (update_area_t *)

#define FBIO_EINK_RESTORE_DISPLAY           _IO(FBIO_MAGIC_NUMBER, 0xef) // 0x46ef (fx_type)

#define FBIO_EINK_SET_REBOOT_BEHAVIOR       _IO(FBIO_MAGIC_NUMBER, 0xe9) // 0x46e9 (reboot_behavior_t)
#define FBIO_EINK_GET_REBOOT_BEHAVIOR       _IO(FBIO_MAGIC_NUMBER, 0xed) // 0x46ed (reboot_behavior_t *)

#define FBIO_EINK_SET_DISPLAY_ORIENTATION   _IO(FBIO_MAGIC_NUMBER, 0xf0) // 0x46f0 (orientation_t)
#define FBIO_EINK_GET_DISPLAY_ORIENTATION   _IO(FBIO_MAGIC_NUMBER, 0xf1) // 0x46f1 (orientation_t *)

#define FBIO_EINK_SET_SLEEP_BEHAVIOR        _IO(FBIO_MAGIC_NUMBER, 0xf2) // 0x46f2 (sleep_behavior_t)
#define FBIO_EINK_GET_SLEEP_BEHAVIOR        _IO(FBIO_MAGIC_NUMBER, 0xf3) // 0x46f3 (sleep_behavior_t *)

// Implemented in the eInk Shim.
//
#define FBIO_EINK_UPDATE_DISPLAY_FX         _IO(FBIO_MAGIC_NUMBER, 0xe4) // 0x46e4 (fx_t *)
#define FBIO_EINK_SPLASH_SCREEN             _IO(FBIO_MAGIC_NUMBER, 0xdc) // 0x46dc (splash_screen_type)
#define FBIO_EINK_SPLASH_SCREEN_SLEEP       _IO(FBIO_MAGIC_NUMBER, 0xe0) // 0x46e0 (splash_screen_type)
#define FBIO_EINK_OFF_CLEAR_SCREEN          _IO(FBIO_MAGIC_NUMBER, 0xdf) // 0x46df (EINK_CLEAR_SCREEN || EINK_CLEAR_BUFFER)
#define FBIO_EINK_CLEAR_SCREEN              _IO(FBIO_MAGIC_NUMBER, 0xe1) // 0x46e1 (no args)
#define FBIO_EINK_POWER_OVERRIDE            _IO(FBIO_MAGIC_NUMBER, 0xe3) // 0x46e3 (power_override_t *)

#define FBIO_EINK_PROGRESSBAR               _IO(FBIO_MAGIC_NUMBER, 0xea) // 0x46ea (int: 0..100 -> draw progressbar || !(0..100) -> clear progressbar)
#define FBIO_EINK_PROGRESSBAR_SET_XY        _IO(FBIO_MAGIC_NUMBER, 0xeb) // 0x46eb (progressbar_xy_t *)
#define FBIO_EINK_PROGRESSBAR_BADGE         _IO(FBIO_MAGIC_NUMBER, 0xec) // 0x46ec (progressbar_badge_t);
#define FBIO_EINK_PROGRESSBAR_BACKGROUND    _IO(FBIO_MAGIC_NUMBER, 0xf4) // 0x46f4 (int: EINKFB_WHITE || EINKFB_BLACK)

// Deprecated from the HAL & Shim.
//
//#define FBIO_EINK_UPDATE_DISPLAY_ASYNC    _IO(FBIO_MAGIC_NUMBER, 0xde) // 0x46de (fx_type: fx_update_full || fx_update_partial)
//#define FBIO_EINK_FAKE_PNLCD              _IO(FBIO_MAGIC_NUMBER, 0xe8) // 0x46e8 (char *)

// For use with /proc/eink_fb/update_display.
//
#define PROC_EINK_UPDATE_DISPLAY_CLS        0   // FBIO_EINK_CLEAR_SCREEN
#define PROC_EINK_UPDATE_DISPLAY_PART       1   // FBIO_EINK_UPDATE_DISPLAY(fx_update_partial)
#define PROC_EINK_UPDATE_DISPLAY_FULL       2   // FBIO_EINK_UPDATE_DISPLAY(fx_update_full)
#define PROC_EINK_UPDATE_DISPLAY_AREA       3   // FBIO_EINK_UPDATE_DISPLAY_AREA
//#define PROC_EINK_UPDATE_DISPLAY_REST     4   // FBIO_EINK_RESTORE_SCREEN
#define PROC_EINK_UPDATE_DISPLAY_SCRN       5   // FBIO_EINK_SPLASH_SCREEN
#define PROC_EINK_UPDATE_DISPLAY_OVRD       6   // FBIO_EINK_FPOW_OVERRIDE
#define PROC_EINK_UPDATE_DISPLAY_FX         7   // FBIO_EINK_UPDATE_DISPLAY_FX
//#define PROC_EINK_UPDATE_DISPLAY_SYNC     8   // FBIO_EINK_SYNC_BUFFERS
//#define PROC_EINK_UPDATE_DISPLAY_PNLCD    9   // FBIO_EINK_FAKE_PNLCD
#define PROC_EINK_SET_REBOOT_BEHAVIOR      10   // FBIO_EINK_SET_REBOOT_BEHAVIOR
#define PROC_EINK_SET_PROGRESSBAR_XY       11   // FBIO_EINK_PROGRESSBAR_SET_XY
#define PROC_EINK_UPDATE_DISPLAY_SCRN_SLP  12   // FBIO_EINK_SPLASH_SCREEN_SLEEP
#define PROC_EINK_PROGRESSBAR_BADGE        13   // FBIO_EINK_PROGRESSBAR_BADGE
#define PROC_EINK_SET_DISPLAY_ORIENTATION  14   // FBIO_EINK_SET_DISPLAY_ORIENTATION
#define PROC_EINK_RESTORE_DISPLAY          15   // FBIO_EINK_RESTORE_DISPLAY
#define PROC_EINK_SET_SLEEP_BEHAVIOR       16   // FBIO_EINK_SET_SLEEP_BEHAVIOR
#define PROC_EINK_PROGRESSBAR_BACKGROUND   17   // FBIO_EINK_PROGRESSBAR_BACKGROUND
#define PROC_EINK_UPDATE_DISPLAY_WHICH     18   // FBIO_EINK_UPDATE_DISPLAY

//#define PROC_EINK_FAKE_PNLCD_TEST       100   // Programmatically drive FBIO_EINK_FAKE_PNLCD (not implemented).
#define PROC_EINK_GRAYSCALE_TEST          101   // Fills display with white-to-black ramp at current bit depth.

// Inter-module/inter-driver eink ioctl access.
//
extern int fiona_eink_ioctl_stub(unsigned int cmd, unsigned long arg);

#define eink_sys_ioctl(cmd, arg)            (get_fb_ioctl() ? (*get_fb_ioctl())((unsigned int)cmd, (unsigned long)arg)      \
                                                            : fiona_eink_ioctl_stub((unsigned int)cmd, (unsigned long)arg))

#endif // _EINKFB_H
