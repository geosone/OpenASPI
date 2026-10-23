#!/bin/sh
# ASPIDSK.SYS / ASPIFDD.SYS: a DOS block device header (32-bit sectors,
# open/close/removable); the unit count is filled in at INIT

set -eu

driver=$1

read_hex()
{
    od -An -v -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'
}

test "$(read_hex "$driver" 0 4)" = "ffffffff"
test "$(read_hex "$driver" 4 2)" = "c208"
test "$(read_hex "$driver" 10 1)" = "00"

echo "OpenASPI $(basename "$driver") device-header layout tests passed"
