#!/bin/bash
#-------------------------------------------------------------------------------
# newfunctions.sh - rewritten functions for SBoggit clean building:
#   list_direct_deps
#   build_with_deps
#   build_single_package
#   install_with_deps
#   install_single_package
#   uninstall_with_deps
#   uninstall_single_package
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

function list_direct_deps
{
  local prg="$1"
  local rdep
  . $SBOREPO/*/$prg/$prg.info
  for rdep in $REQUIRES; do
    echo $rdep
  done
}

#-------------------------------------------------------------------------------

function build_with_deps
{
  local me="$1"
  local mydeplist="$(list_direct_deps $me)"
  for mydep in $mydeplist; do
    build_with_deps $mydep
  done
  for mydep in $mydeplist; do
    install_with_deps $mydep
  done
  build_package $me
  for mydep in $mydeplist; do
    uninstall_with_deps $mydep
  done
}

#-------------------------------------------------------------------------------

function build_single_package
{
  local prg="$1"
  :
}

#-------------------------------------------------------------------------------

function install_with_deps
{
  local me="$1"
  :
}

#-------------------------------------------------------------------------------

function install_single_package
{
  local prg="$1"
  :
}

#-------------------------------------------------------------------------------

function uninstall_with_deps
{
  local me="$1"
  :
}

#-------------------------------------------------------------------------------

function uninstall_single_package
{
  local prg="$1"

  pkgid=$(basename /var/log/packages/$prg-*$TAG)
  # Save a list of potential detritus in /etc
  etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/$pkgid)
  etcdirs=$(grep '^etc/.*/$' /var/log/packages/$pkgid)
  echo "Removing package $pkgid ..."
  removepkg $pkgid >/dev/null 2>&1
  # Remove any surviving detritus
  for f in $etcnewfiles; do
    rm -f /"$f" /"$(echo "$f" | sed 's/\.new$//')"
  done
  for d in $etcnewdirs; do
    rmdir --ignore-fail-on-non-empty /"$d"
  done
  # Do this last so it can mend things we broke
  # (e.g. by reinstalling a Slackware package)
  hint_cleanup $prg
}

#-------------------------------------------------------------------------------

function check_package
{
  local pkgpath=$1
  local pkgname=$(basename $pkgpath)
  # Check the package name
  case $pkgname in
    $PRGNAM-${VERSION}-$SLKARCH-$BUILD$TAG.t?z | \
    $PRGNAM-${VERSION}-noarch-$BUILD$TAG.t?z | \
    $PRGNAM-${VERSION}_*-$SLKARCH-$BUILD$TAG.t?z | \
    $PRGNAM-${VERSION}_*-noarch-$BUILD$TAG.t?z )
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
      [    "$parch" != "$SLKARCH" -a "$parch" != "noarch" ] && \
        echo_yellow "ARCH is $parch not $SLKARCH or noarch"
      [   "$pbuild" != "$BUILD"   ] && echo_yellow "BUILD is $pbuild not $BUILD"
      [     "$ptag" != "$TAG"     ] && echo_yellow "TAG is $ptag not $TAG"
      [ "$pext" != 'tgz' -a "$pext" != 'tbz' -a "$pext" != 'tlz' -a "$pext" != 'txz' ] && \
        echo_yellow "Suffix .$pext is not .t[gblx]z"
      ;;
    esac 
  # Check the package contents [UNIMPLEMENTED]
}
