
* KOReader version:
* Device:

#### Issue

#### Steps to reproduce

##### `crash.log` (if applicable)
`crash.log` is a file that is automatically created when KOReader crashes. It can
normally be found in the KOReader directory:

* `/mnt/private/koreader` for Cervantes
* `koreader/` directory for Kindle
* `.adds/koreader/` directory for Kobo
* `applications/koreader/` directory for Pocketbook

Android won't have a crash.log file because Google restricts what apps can log, so you'll need to obtain logs using `adb logcat KOReader:I ActivityManager:* AndroidRuntime:* *:F`.


Please try to include the relevant sections in your issue description.
You can upload the whole `crash.log` file on GitHub by dragging and
dropping it onto this textbox, or you can use one of these paste services.
Please don't forget to set a high expiration date if you do.
https://pastebin.com https://slexy.org https://paste2.org https://fpaste.org
http://ix.io https://paste.kde.org https://paste.debian.net.
