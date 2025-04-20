# Before reporting

Before opening a new ticket, take some time to review the existing issues (and pull requests) to ensure your issue or request hasn't been already reported, requested or resolved.

If your current issue hasn't been already reported, make sure you are running the latest available version (ideally the latest nightly) and that you can replicate it with verbose logs on.

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
