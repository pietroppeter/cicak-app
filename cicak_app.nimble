# Package

version       = "0.1.0"
author        = "Pietro Peterlongo"
description   = "A playground for cicak, the Nim REPL: run predefined cells in a live Nim process"
license       = "MIT"
srcDir        = "src"
bin           = @["cicak_app"]

# Dependencies

requires "nim >= 2.4.0"
requires "mummy >= 0.4.0"
