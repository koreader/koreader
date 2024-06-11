#!/bin/sh -e
#
# open file in application based on file extension

mime_type=$(file -bi "$1")

case "${mime_type}" in
    application/x*)
        ./"$1"
        echo "Application done, hit enter to return"
        read -r REPLY
        exit
        ;;

    text/x-shellscript*)
        ./"$1"
        echo "Shellscript done, hit enter to return"
        read -r REPLY
        exit
        ;;
esac

case "$1" in
    *.sh)
        sh "$1"
        echo "Shellscript done, enter to return."
        read -r REPLY
        exit
        ;;

    # all other files
    *)
        "${EDITOR:=vi}" "$1"
        ;;
esac
