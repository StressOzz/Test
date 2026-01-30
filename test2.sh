#!/bin/sh

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/main/ru/tcp-16-20/index.html"

curl -fsSL "$RAW" | \
grep 'url:' | \
sed -n 's/.*id: "\([^"]*\)".*url: "\([^"]*\)".*/\1|\2/p'
