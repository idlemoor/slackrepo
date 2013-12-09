#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# testfunctions.sh - functions for various tests:
#   test_package_is_sane
#   test_package_is_uptodate
#   test_arch_is_supported
#-------------------------------------------------------------------------------

function test_package_is_sane
{
  local pkgpath=$1
  local pkgname=$(basename $pkgpath)
  # Check the package name
  case $pkgname in
    $PRGNAM-${VERSION}-$SB_ARCH-$BUILD$SB_TAG.t?z | \
    $PRGNAM-${VERSION}-noarch-$BUILD$SB_TAG.t?z | \
    $PRGNAM-${VERSION}_*-$SB_ARCH-$BUILD$SB_TAG.t?z | \
    $PRGNAM-${VERSION}_*-noarch-$BUILD$SB_TAG.t?z )
      : ;;
    *)
      echo_yellow "WARNING: abnormal package name $pkgname"
      pprgnam=$(echo $pkgname | rev | cut -f4- -d- | rev)
      pversion=$(echo $pkgname | rev | cut -f3 -d- | rev)
      parch=$(echo $pkgname | rev | cut -f2 -d- | rev)
      pbuild=$(echo $pkgname | rev | cut -f1 -d- | rev | sed 's/[^0-9]*$//')
      ptag=$(echo $pkgname | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
      pext=$(echo $pkgname | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
      [  "$pprgnam" != "$PRGNAM"  ] && echo_yellow "PRGNAM is $pprgnam not $PRGNAM"
      [ "$pversion" != "$VERSION" ] && echo_yellow "VERSION is $pversion not $VERSION"
      [    "$parch" != "$SB_ARCH" -a "$parch" != "noarch" ] && \
        echo_yellow "ARCH is $parch not $SB_ARCH or noarch"
      [   "$pbuild" != "$BUILD"   ] && echo_yellow "BUILD is $pbuild not $BUILD"
      [     "$ptag" != "$SB_TAG"     ] && echo_yellow "TAG is $ptag not $SB_TAG"
      [ "$pext" != 'tgz' -a "$pext" != 'tbz' -a "$pext" != 'tlz' -a "$pext" != 'txz' ] && \
        echo_yellow "Suffix .$pext is not .t[gblx]z"
      ;;
    esac
  # Check the package contents
  if tar tf $pkgpath | grep -q -v -E '^(bin)|(etc)|(lib)|(opt)|(sbin)|(usr)|(var)|(install)|(./$)'; then
    echo_yellow "WARNING: $pkgpath installs some weird shit"
  fi
}

#-------------------------------------------------------------------------------

function test_package_is_uptodate
{
  # Returns:
  # 1 - not found (or unstamped with git rev)
  # 2 - git thinks the directory has been modified locally
  # 3 - previous git rev != current git rev
  local p="${1:-$prg}"
  gitrevfilename=$(ls $SB_OUTPUT/$p/gitrev-* 2>/dev/null)
  pkglist=$(ls $SB_OUTPUT/$p/*$SB_TAG.t?z 2>/dev/null)
  if [ -z "$pkglist" -o $(echo $gitrevfilename | wc -w) != 1 ]; then
    echo "$p not found, needs to be built."
    return 1
  elif [ -n "$(cd $SB_REPO/*/$p; git status -s .)" ]; then
    echo "$p has been modified."
    # Note, if a tar.gz hint is identical to upstream git (eg. if merged),
    # git status won't know that the hint was applied.  This is a Good Thing.
    return 2
  else
    pkgrev=$(echo $gitrevfilename | sed 's/^.*gitrev-//')
    prgrev=$(git log -n 1 --format=format:%h $SB_REPO/*/$p)
    if [ $pkgrev != $prgrev ]; then
      echo "$p $pkgrev is not up-to-date ($SB_GITBRANCH is $prgrev)."
      return 3
    else
      echo "$p $pkgrev is up-to-date."
      return 0
    fi
  fi
}

#-------------------------------------------------------------------------------

function test_arch_is_supported
{
  local prg="$1"
  . $SB_REPO/*/$prg/$prg.info
  case $SB_ARCH in
    i?86) DOWNLIST="$DOWNLOAD" ;;
  x86_64) DOWNLIST="${DOWNLOAD_x86_64:-$DOWNLOAD}" ;;
       *) DOWNLIST="$DOWNLOAD" ;;
  esac
  if [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ]; then
    echo_yellow "$prg is $DOWNLIST on $SB_ARCH"
    return 1
  fi
  return 0
}
