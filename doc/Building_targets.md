# Building targets

KOReader is available for multiple platforms. Here are instructions to build installable packages for all these platforms.

These instructions are intended for a Linux OS. MacOS and Windows users are suggested to develop in a Linux VM.

## Prerequisites

These instructions assume that you [have a development environment ready to run](Building.md) KOReader. If not then please install common prerequisites first.

### A toolchain for your target.

Each target has its own architecture and you'll need to setup a proper cross-compile toolchain. Your GCC should be at least version 4.9.

#### for Android

If you want to use your own NDK / SDK installs, the build system honor the standard environment variables:
- NDK location: `ANDROID_NDK_HOME` or `ANDROID_NDK_ROOT`
- SDK location: `ANDROID_HOME` or `ANDROID_SDK_ROOT`

Otherwise, compatible versions of the Android NDK and SDK will be downloaded and setup automatically (under `base/toolchain`) as part of the build.

NOTE: If you want to use your own installed tools, please make sure to use the following supported versions: **NDKr23c** and the SDK for Android 9 (**API level 28**).

#### for embedded Linux devices

Cross compile toolchains are available for Ubuntu users through these commands:

##### e-Ink devices (e.g., Kindle, Kobo, Cervantes, reMarkable, PocketBook)

**NOTE:** While, for some targets (specifically, Cervantes, Kindle & Kobo), we make *some* effort to support Linaro/Ubuntu TCs,
they do *not* exactly target the proper devices. While your build *may* go fine, this will *probably* lead to runtime failure.  
As time goes by, and/or the more bleeding-edge your distro is, the greater the risk for mismatch gets.  

Which means, that, unless you are *very* sure you know what you're doing, you'll want to use the exact same TCs we do, ones that target their respective platforms properly.  
We have a distribution-agnostic solution to make that mostly painless: [koxtoolchain](https://github.com/koreader/koxtoolchain)!  
This will allow you to build the *exact* same TCs used to build the nightlies, thanks to the magic of [crosstool-ng](https://github.com/crosstool-ng/crosstool-ng). These are also included precompiled in the Docker images for the respective targets.  


### Additional packages

Some platforms will require additional packages:

#### for Android

Building for Android requires `openjdk-17-jdk-headless` and `p7zip-full`.


For both Ubuntu and Debian, install the packages:

```
sudo apt-get install openjdk-17-jdk-headless p7zip-full
```

#### for Debian

Building a debian package requires the `dpkg-deb` tool. It should be already installed if you're on a Debian/Ubuntu based distribution.

## Building 

You can check out our [nightlybuild script][nb-script] to see how to build a package from scratch.

### Android

```
./kodev release ANDROID_TARGET
```

Where `ANDROID_TARGET` is one of the supported targets:
- `android-arm`
- `android-arm64`
- `android-x86`
- `android-x86_64`

### Desktop Linux

#### Emulator

See [Building](https://github.com/koreader/koreader/blob/master/doc/Building.md).

#### AppImage (x86_64)

```
./kodev release appimage
```

#### Debian (x86_64)

```
./kodev release debian
```

#### Debian (armel)

```
./kodev release debian-armel
```

#### Debian (armhf)

```
./kodev release debian-armhf
```

### Desktop macOS

```
./kodev release macos
```

### e-Ink devices

#### Cervantes

```
./kodev release cervantes
```

#### Kindle

```
./kodev release kindle
```

#### Kobo

```
./kodev release kobo
```

#### Pocketbook

```
./kodev release pocketbook
```

#### reMarkable

```
./kodev release remarkable
```

## Porting to a new target.

See [Porting.md](Porting.md)

[nb-script]:https://gitlab.com/koreader/nightly-builds/blob/master/build_release.sh
