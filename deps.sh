#!/bin/sh
# Clones the pinned dependencies into deps/ (paths in nim.cfg), so builds need
# neither nimble nor atlas. Bump a version here and in cicak_app.nimble together.
set -e
cd "$(dirname "$0")"
mkdir -p deps
get() { # name repo tag
  [ -d "deps/$1" ] || git -c advice.detachedHead=false clone -q --depth 1 -b "$3" "https://github.com/$2" "deps/$1"
}
get mummy   guzba/mummy     0.4.8
get webby   treeform/webby  0.2.1
get zippy   guzba/zippy     0.10.20
get crunchy guzba/crunchy   0.1.11
get nimsimd guzba/nimsimd   1.3.2
