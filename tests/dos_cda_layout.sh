#!/bin/sh
# ASPICDA.SYS: a DOS CD-ROM device header (MSCDEX driver interface)

set -eu

driver=${1:-build/dos/ASPICDA.SYS}

read_hex()
{
    od -An -v -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'
}

test "$(read_hex "$driver" 0 4)" = "ffffffff"
test "$(read_hex "$driver" 4 2)" = "00c8"
test "$(read_hex "$driver" 10 8)" = "4153504943444130"
test "$(read_hex "$driver" 18 4)" = "00000000"

echo 'OpenASPI ASPICDA device-header layout tests passed'
