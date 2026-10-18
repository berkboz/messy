#!/bin/sh
# Renders the launch film in English and Turkish, 4K.
set -e
cd "$(dirname "$0")"
node set-lang.mjs en && npx hyperframes render --resolution landscape-4k -o renders/messy-launch-en.mp4 .
node set-lang.mjs tr && npx hyperframes render --resolution landscape-4k -o renders/messy-launch-tr.mp4 .
node set-lang.mjs en
