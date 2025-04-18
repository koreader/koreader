# Before reporting

A bug that's not reproducible on the latest **nightly** (or development branch) is not a bug anymore.

Please try to reproduce the issue on the latest **nightly** before submitting a bug preport. In case the bug is still there please make sure it isn't already reported. Please **do not open duplicates**

# How to report

1. please use english (you can use a translator if you wish)
2. please use a short, descriptive title.
3. fill device and version
4. add a short description of the issue and the steps required to reproduce it.
5. attach the `crash.log` from your device.

## Getting a `crash.log`

`crash.log` is a file that is automatically created by KOReader. It can normally be found in the KOReader directory:

* `/mnt/private/koreader` for Cervantes
* `koreader/` directory for Kindle
* `.adds/koreader/` directory for Kobo
* `applications/koreader/` directory for Pocketbook

Android logs are kept in memory. Please go to [Menu] → Help → Bug Report to save these logs to a file.

## Verbose logs

If the bug you're reporting is NOT a crash we'll need you to reproduce the issue with *verbose* debug logging enabled.
To do so, go to `Top menu → Hamburger menu → Help → Report a bug` and tap `Enable verbose logging`. Restart as requested, then repeat the steps for your issue.
