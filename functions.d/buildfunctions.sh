#!/bin/bash
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for SBoggit:
#   buildzilla
#
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#-------------------------------------------------------------------------------

function buildzilla
{
  # Returns:
  # 1 - build failed
  # 2 - download failed
  # 3 - checksum failed
  # 4 - installpkg returned nonzero
  # 5 - skipped by hint, or unsupported on this arch
  # 6 - build returned 0 but nothing in $OUTPUT
  prg="$1"
  category=$(cd $SBOREPO/*/$prg/..; basename $(pwd))
  . $SBOREPO/$category/$prg/$prg.info
  unset BUILD
  buildassign=$(grep '^BUILD=' $SBOREPO/*/$PRGNAM/$PRGNAM.SlackBuild)
  eval $buildassign
  # At this point we have a full set of environment variables for called functions to use:
  # PRGNAM VERSION SLKARCH BUILD TAG DOWNLOAD* MD5SUM* etc

  msg="--$category/$prg-----------------------------------------------------------------------------"
  echo "${msg:0:79}"
  rm -f $LOGDIR/$prg.log

  if [ "$PRGNAM" != "$prg" ]; then
    echoyellow "WARNING: PRGNAM in $SBOREPO/$category/$prg/$prg.info is '$PRGNAM', not $prg"
  fi

  # Check whether the item should be skipped
  if [ -f $HINTS/$prg.skipme ]; then
    echoyellow "SKIPPED $category/$prg due to hint"
    cat $HINTS/$prg.skipme
    return 5
  fi

  # Get the source and symlink it into the SlackBuild directory
  if [ -d $SRCCACHE/$prg ]; then
    if ! checksrc ; then
      echo "Note: bad checksums in cached source, will download again"
      downloadsrc
      case $? in
        0) checksrc || { savebadsrc; itfailed; return 3; } ;;
        2) rm -rf $SRCCACHE/$prg;  return 5 ;;
        *) savebadsrc; itfailed; return 2 ;;
      esac
    fi
  else
    downloadsrc
    case $? in
      0) checksrc || { savebadsrc; itfailed; return 3; } ;;
      2) rm -rf $SRCCACHE/$prg;  return 5 ;;
      *) savebadsrc; itfailed; return 2 ;;
    esac
  fi
  ln -sf -t $SBOREPO/$category/$prg/ $SRCCACHE/$prg/*

  # Get any hints for the build
  if [ -f $HINTS/$prg.options ]; then
    options="$(cat $HINTS/$prg.options)"
    echo "Hint: found options $options"
  fi
  tempmakeflags=''
  if [ -f $HINTS/$prg.makej1 ]; then
    tempmakeflags="MAKEFLAGS='-j1'"
    echo "Hint: setting $tempmakeflags"
  fi

  # Build it
  echo "SlackBuilding $prg.SlackBuild ..."
  export OUTPUT=$OUTREPO/$prg
  rm -rf $OUTPUT/*
  mkdir -p $OUTPUT
  ( cd $SBOREPO/$category/$prg; env $tempmakeflags $options sh ./$prg.SlackBuild ) >>$LOGDIR/$prg.log 2>&1
  stat=$?
  if [ $stat != 0 ]; then
    echo "ERROR: $prg.SlackBuild failed (status $stat)"
    itfailed
    return 1
  fi

  # Make sure we got something :-)
  pkglist=$(ls $OUTPUT/*.t?z 2>/dev/null)
  if [ -z "$pkglist" ]; then
    echo "ERROR: no packages found in $OUTPUT"
    itfailed
    return 6
  fi

  # Install the built packages
  # (this supports multiple output packages because some Slackware SlackBuilds do that)
  for pkgpath in $pkglist; do
    # This is our best chance to verify the package name:
    pkg=$(basename $pkgpath)
    case $pkg in
    $PRGNAM-${VERSION}-$SLKARCH-$BUILD$TAG.t?z | \
    $PRGNAM-${VERSION}-noarch-$BUILD$TAG.t?z | \
    $PRGNAM-${VERSION}_*-$SLKARCH-$BUILD$TAG.t?z | \
    $PRGNAM-${VERSION}_*-noarch-$BUILD$TAG.t?z )
      : ;;
    *)
      echoyellow "WARNING: abnormal package name $pkg"
      pprgnam=$(echo $pkg | rev | cut -f4- -d- | rev)
      pversion=$(echo $pkg | rev | cut -f3 -d- | rev)
      parch=$(echo $pkg | rev | cut -f2 -d- | rev)
      pbuild=$(echo $pkg | rev | cut -f1 -d- | rev | sed 's/[^0-9]*$//')
      ptag=$(echo $pkg | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
      pext=$(echo $pkg | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
      [  "$pprgnam" != "$PRGNAM"  ] && echoyellow "PRGNAM is $pprgnam not $PRGNAM"
      [ "$pversion" != "$VERSION" ] && echoyellow "VERSION is $pversion not $VERSION"
      [    "$parch" != "$SLKARCH" -a "$parch" != "noarch" ] && \
        echoyellow "ARCH is $parch not $SLKARCH or noarch"
      [   "$pbuild" != "$BUILD"   ] && echoyellow "BUILD is $pbuild not $BUILD"
      [     "$ptag" != "$TAG"     ] && echoyellow "TAG is $ptag not $TAG"
      [ "$pext" != 'tgz' -a "$pext" != 'tbz' -a "$pext" != 'tlz' -a "$pext" != 'txz' ] && \
        echoyellow "Suffix .$pext is not .t[gblx]z"
      ;;
    esac 
    echo "Installing $pkgpath ..."
    installpkg --terse $pkgpath
    stat=$?
    if [ $stat != 0 ]; then
      echo "ERROR: installpkg $pkgpath failed (status $stat)"
      itfailed
      return 4
    fi
    dotprofilizer $pkg
  done

  itpassed  # \o/
  return 0
}
