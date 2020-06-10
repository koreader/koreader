#!/system/bin/sh

## This script is executed every time koreader starts.
## The log is written to scripts.done. This file is important!
## If the log does not exist, it is the first start after an update of the apk.

## On the first start of koreader, two directories on the SDCard are checked.
## If they do not exist the get populated with an example to update 
## hyphen patterns from /sdcard/koreader/hyph/*.pattern

## The scripts in /sdcard/koreader/scripts.once are only executed on the first
## start after an update of the apk

## The scripts in /sdcard/koreader/scripts.update are executed on every start
## (also on the first one).


# $1 is the koreader user directory

CUT="busybox cut"
REV="busybox rev"

# system dir of koreader
SYYTEM_DIR=$PWD

# ./scripts.done does not exist after apk update
if [ ! -f ./scripts.done ]; then
  # if scripts.once does not exist, create and populate it
  if [ ! -d "$1"/scripts.once ]; then
    mkdir "$1"/scripts.once
    echo "#place *.sh scripts here, which should be executed after an update of koreader" > "$1"/scripts.once/README
    echo "#you could overwrite hyphenation patterns with your own ones" >> "$1"/scripts.once/README

   cp "$SYSTEM_DIR"/scripts/*once.sh "$1"/scripts.once/ 
  fi

  # if scripts.update does not exist, create and populate it
  if [ ! -d "$1"/scripts.update ]; then
    mkdir "$1"/scripts.update
    echo "#place *.sh scripts here, which should be executed everytime koreader starts" > "$1"/scripts.update/README
    echo "#you could update the hyphenation patterns with new ones" >> "$1"/scripts.update/README
  
  cp "$SYSTEM_DIR"/scripts/*update.sh "$1"/scripts.update/
  fi

  # execute all scripts in scripts.once	
  for script in $(ls "$1"/scripts.once/*.sh); do
    echo "execute: sh $script $1 $SYSTEM_DIR" >> ./scripts.done
    sh "$script" "$1" "$SYSTEM_DIR"
  done
  echo "scripts once done" >> ./scripts.done
else
  rm ./scripts.done
fi

if [ -d "$1"/scripts.update ]; then
  # execute all scripts in scripts.update	
  for script in $(ls "$1"/scripts.update/*.sh); do
    echo "execute: sh $script $1 $SYSTEM_DIR" >> ./scripts.done
    sh "$script" "$1" "$SYSTEM_DIR"
  done
fi

echo "scripts update done" >> ./scripts.done
