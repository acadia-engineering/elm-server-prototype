#!/bin/bash

set -x -o errexit -o pipefail -o nounset



## FIND DEPENDENCIES

if command -v sha1sum; then
    SHASUM=sha1sum
elif command -v shasum; then
    SHASUM=shasum
else
    echo "unable to find 'shasum' program"
    exit 1
fi


## SETUP DIRECTORIES

TMP=gen/tmp
ASSETS=gen/assets

trap "rm -rf $TMP" EXIT

rm -rf $ASSETS
mkdir -p $ASSETS
mkdir -p $TMP


## BUILD

acadia make --gen-elm=gen/elm

printf "module Assets exposing (..)\n\ntype alias Elm = { name : String, hash : String }\n\n" > $TMP/Assets.elm
FILES=""
COMMA="type alias File = { tipe : String, hash : String, ext : String, path : String }\n\nfiles : List File\nfiles =\n  [ "

for file in src/client/Pages/*
do
    name="$(basename "$file" .elm)"
    elm make $file --optimize --output=$TMP/elm.js > /dev/null
    hash=$($SHASUM $TMP/elm.js | cut -f 1 -d " ")
    mv $TMP/elm.js "$ASSETS/$hash.js"
    lower="$(echo "${name:0:1}" | tr '[:upper:]' '[:lower:]')${name:1}"
    printf "${lower}_elm : Elm\n${lower}_elm = { name = \"$name\", hash = \"$hash\" }\n\n" >> $TMP/Assets.elm
    FILES+="$COMMA{ tipe = \"text/javascript\", hash = \"$hash\", ext = \"js\", path = \"$ASSETS/$hash.js\" }"
    COMMA="\n  , "
done

printf "$FILES\n  ]\n" >> $TMP/Assets.elm
mv $TMP/Assets.elm gen/elm/Assets.elm

elm make src/server/Main.elm --optimize --output=$ASSETS/elm.js

rm -rf $TMP


## SERVE

trap "exit" INT TERM
trap "kill 0" EXIT

acadia serve &
node ../elm-server/server.js

