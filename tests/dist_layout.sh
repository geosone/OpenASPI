#!/bin/sh
# Check the built distribution without invoking or modifying the shared GDI.
set -eu
dist=$1
shsucd=${2:-deps/shsucd}
ini_has()
{
    tr -d '\r' < "$dist/INSTALL.INI" | grep -Fxq "$1"
}
for file in ASPITAP.SYS ASPIDSK.SYS ASPIFDD.SYS ASPICDA.SYS ASPISCAN.COM ASPIMGR.EXE \
    ASPICTL.EXE EJECT.EXE CLOSE.EXE LOCK.EXE UNLOCK.EXE STATUS.EXE ASPIFMT.EXE ASPIDD.EXE ASPIDDG.EXE \
    TAPECTL.COM WINCHECK.COM WINCHECK.EXE INSTALL.EXE INSTALL.INI README.TXT \
    LICENSE.TXT SHSUCDX.COM CDAUDIO.COM SHSUCD.LIC SHSUCD.TXT; do
    test -s "$dist/$file"
done
cmp "$shsucd/LICENSE.txt" "$dist/SHSUCD.LIC"
cmp "$shsucd/readme.txt" "$dist/SHSUCD.TXT"
cmp "$dist/ASPICTL.EXE" "$dist/EJECT.EXE"
cmp "$dist/ASPICTL.EXE" "$dist/CLOSE.EXE"
for command in $(sed -n 's/^OA_COMMAND(\([A-Z0-9]*\)).*/\1/p' tools/aspictl/commands.def); do
    test "${#command}" -le 8
    cmp "$dist/ASPICTL.EXE" "$dist/$command.EXE"
    ini_has "$command.EXE"
done
for file in ASPIFMT.EXE ASPIDD.EXE ASPIDDG.EXE SHSUCDX.COM CDAUDIO.COM SHSUCD.LIC SHSUCD.TXT; do
    ini_has "$file"
done
echo 'OpenASPI distribution payload/license tests passed'
