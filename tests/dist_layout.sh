#!/bin/sh
# Check the built distribution without invoking or modifying the shared GDI.
set -eu
dist=$1
shsucd=${2:-deps/shsucd}
for file in ASPITAP.SYS ASPIDSK.SYS ASPIFDD.SYS ASPICDA.SYS ASPISCAN.COM \
    TAPECTL.COM WINCHECK.COM WINCHECK.EXE INSTALL.EXE INSTALL.INI README.TXT \
    LICENSE.TXT SHSUCDX.COM CDAUDIO.COM SHSUCD.LIC SHSUCD.TXT; do
    test -s "$dist/$file"
done
cmp "$shsucd/LICENSE.txt" "$dist/SHSUCD.LIC"
cmp "$shsucd/readme.txt" "$dist/SHSUCD.TXT"
for file in SHSUCDX.COM CDAUDIO.COM SHSUCD.LIC SHSUCD.TXT; do
    grep -Fxq "$file" "$dist/INSTALL.INI"
done
echo 'OpenASPI distribution payload/license tests passed'
