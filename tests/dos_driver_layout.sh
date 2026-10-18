#!/bin/sh

set -eu

driver=${1:-build/dos/ASPITAP.SYS}

read_hex()
{
    od -An -v -tx1 -j "$2" -N "$3" "$1" | tr -d ' \n'
}

test "$(read_hex "$driver" 0 4)" = "12000000"
test "$(read_hex "$driver" 4 2)" = "4080"
test "$(read_hex "$driver" 10 8)" = "524d543020202020"
test "$(read_hex "$driver" 18 4)" = "ffffffff"
test "$(read_hex "$driver" 22 2)" = "4080"
test "$(read_hex "$driver" 28 8)" = "4e524d5430202020"

echo 'OpenASPI DOS device-header layout tests passed'
