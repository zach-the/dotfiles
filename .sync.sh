#!/bin/bash

echo_purple() { # all standard output from this script is purple, so it can be differentiated from the output of other scripts
     printf "\e[38;2;186;85;211m$1\e[0m\n"
}

if [[ -z $1 ]]; then
    echo "you need a commit message"
    exit
fi

echo_purple "pulling"
git pull
echo_purple "adding all"
git add --all
echo_purple "committing with message \"$1\""
git commit -m '$1'
echo_purple "pushing"
git push
