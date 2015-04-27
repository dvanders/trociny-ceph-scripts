#!/bin/sh

awk '/'"$1"'/ {if (old) print $0, $'$2' - old; old = $'$2'}'
