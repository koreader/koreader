#!/system/bin/sh

## This script is executed every time koreader starts.
## The log is written to scripts.done. This file is important!
## If the log does not exist, it is the first start after an update of the apk.

## On the first start of koreader, two directories on the SDCard are checked.
## If they do not exist the get populated with an example to update 
## hyphen patterns from /sdcard/koreader/hyph/*.pattern

## The scripts in /sdcard/koreader/scripts.afterupdate are only executed on the first
## start after an update of the apk

## The scripts in /sdcard/koreader/scripts.always are executed on every start
## (also on the first one).


# $1 is the koreader user directory

CUT="busybox cut"
REV="busybox rev"

# system dir of koreader
SYSTEM_DIR=$PWD

# ./scripts.done does not exist after apk update
if [ ! -f ./scripts.done ]; then
  # if scripts.afterupdate does not exist, create and populate it
  if [ ! -d "$1"/scripts.afterupdate ]; then
    mkdir "$1"/scripts.afterupdate
    echo "#place *.sh scripts here, which should be executed after an update of koreader" > "$1"/scripts.afterupdate/README
    echo "#you could overwrite hyphenation patterns with your own ones" >> "$1"/scripts.afterupdate/README

   cp "$SYSTEM_DIR"/scripts/*afterupdate.sh "$1"/scripts.afterupdate/ 
  fi

  # if scripts.always does not exist, create and populate it
  if [ ! -d "$1"/scripts.always ]; then
    mkdir "$1"/scripts.always
    echo "#place *.sh scripts here, which should be executed everytime koreader starts" > "$1"/scripts.always/README
    echo "#you could update the hyphenation patterns with new ones" >> "$1"/scripts.always/README
  
  cp "$SYSTEM_DIR"/scripts/*update.sh "$1"/scripts.always/
  fi

  # execute all scripts in scripts.afterupdate	
  for script in $(ls "$1"/scripts.afterupdate/*.sh); do
    [[ -e "$script" ]] || break
    echo "execute: sh $script $1 $SYSTEM_DIR" >> ./scripts.done
    sh "$script" "$1" "$SYSTEM_DIR"
  done
  echo "scripts afterupdate done" >> ./scripts.done
else
  rm ./scripts.done
fi

if [ -d "$1"/scripts.always ]; then
  # execute all scripts in scripts.always	
  for script in $(ls "$1"/scripts.always/*.sh); do
    [[ -e "$script" ]] || break
    echo "execute: sh $script $1 $SYSTEM_DIR" >> ./scripts.done
    sh "$script" "$1" "$SYSTEM_DIR"
  done
fi

echo "scripts update done" >> ./scripts.done
