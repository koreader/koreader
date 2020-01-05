# Building targets

KOReader is available for multiple platforms. Here are instructions to build installable packages for all these platforms.

These instructions are intended for a Linux OS. MacOS and Windows users are suggested to develop in a Linux VM.


## Prerequisites

This instructions asume that you [have a development environment ready to run](Building.md) KOReader. If not then please install common prerequisites first.

### A toolchain for your target.

Each target has its own architecture and you'll need to setup a proper cross-compile toolchain. Your GCC should be at least version 4.9.

#### for Android

A compatible version of the Android NDK and SDK will be downloaded automatically by `./kodev release android` if no NDK or SDK is provided in environment variables. For that purpose you can use:

```
NDK=/ndk/location SDK=/sdk/location ./kodev release android
```

If you want to use your own installed tools please make sure that you have the **NDKr15c** and the SDK for Android 9 (**API level 28**) already installed.

#### for embedded linux devices

Cross compile toolchains are available for Ubuntu users through these commands:

##### Kindle and Cervantes

```
sudo apt-get install gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
```

##### Kobo and Ubuntu Touch

```
sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
```

**NOTE 1:** The packages `pkg-config-arm-linux-gnueabihf` and `pkg-config-arm-linux-gnueabi` may
block you from building. Remove them if you get the following ld error

```
/usr/lib/gcc-cross/arm-linux-gnueabihf/4.8/../../../../arm-linux-gnueabihf/bin/ld: cannot find -lglib-2.0
```

**NOTE 2:** In the specific case of Cervantes, Kindle & Kobo targets, while we make some effort to support these Linaro/Ubuntu TCs,
they do *not* exactly target the proper devices. While your build will go fine, this may lead to runtime failure.
As time goes by, and/or the more bleeding-edge your distro is, the greater the risk for mismatch gets.
Thankfully, we have a distribution-agnostic solution for you: [koxtoolchain](https://github.com/koreader/koxtoolchain)!
This will allow you to build the *exact* same TCs used to build the nightlies, thanks to the magic of [crosstool-ng](https://github.com/crosstool-ng/crosstool-ng). These are also included precompiled in the Docker images for the respective targets.

**NOTE 3:** The vendor toolchain will be downloaded automatically by `./kodev release pocketbook`

### Additional packages

Some platforms will require additional packages:

#### for Android

Building for Android requires `openjdk-8-jdk` and `p7zip-full`.


For both Ubuntu and Debian, install the packages:

```
sudo apt-get install openjdk-8-jdk p7zip-full
```

#### for Debian

Building a debian package requires the `dpkg-deb` tool. It should be already installed if you're on a Debian/Ubuntu based distribution.

#### for Ubuntu Touch

Building for Ubuntu Touch requires the `click` package management tool.

Ubuntu users can install it with:

```
sudo apt-get install click
```

**NOTE**: The Ubuntu Touch build won't start anymore, and none of the currently active developers have any physical devices. Please visit [#4960](
https://github.com/koreader/koreader/issues/4960) if you want to help.

The Ubuntu Touch builds are therefore no longer published under releases on GitHub, but they are still available from [the nightly build server](http://build.koreader.rocks/download/nightly/).

## Building 

You can check out our [nightlybuild script][nb-script] to see how to build a
package from scratch.

### Android

```
./kodev release android
```

### Android (x86)

```
ANDROID_ARCH=x86 ./kodev release android
```

### Cervantes

```
./kodev release cervantes
```

### Desktop Linux

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

### Kindle

```
./kodev release kindle
```

### Kobo

```
./kodev release kobo
```

### Pocketbook

```
./kodev release pocketbook
```

### Ubuntu Touch

```
./kodev release ubuntu-touch
```


## Porting to a new target.

See [Porting.md](Porting.md)


[nb-script]:https://gitlab.com/koreader/nightly-builds/blob/master/build_release.sh
