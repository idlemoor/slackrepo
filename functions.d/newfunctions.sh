#!/bin/bash
#-------------------------------------------------------------------------------
# newfunctions.sh - rewritten functions for SBoggit clean building:
#   list_direct_deps
#   build_with_deps
#   check_package
#   install_with_deps
#   install_prebuilt_packages
#   install_package
#   uninstall_with_deps
#   uninstall_package
#   arch_unsupported
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
  # Check the package contents
  if tar tf $pkgpath | grep -q -v -E '^(bin)|(etc)|(lib)|(opt)|(sbin)|(usr)|(var)|(install)|(./$)'; then
    echo_yellow "WARNING: $pkgpath installs some weird shit"
  fi
}

#-------------------------------------------------------------------------------

function install_with_deps
{
  local me="$1"
  :
}

#-------------------------------------------------------------------------------

function install_prebuilt_packages
{
  local p="$1"
  c=$(cd $SBOREPO/*/$p/..; basename $(pwd))
  echo_lined "$c/$p"
  pkglist=$(ls $OUTREPO/$p/*$TAG.t?z 2>/dev/null)
  for pkgpath in $pkglist; do
    pkgid=$(echo $(basename $pkgpath) | sed "s/$TAG\.t.z\$//")
    if [ -e /var/log/packages/$pkgid ]; then
      echo_yellow "WARNING: $p is already installed:" $(ls /var/log/packages/$pkgid)
    else
      install_package $pkgpath || return 1
    fi
  done
}

#-------------------------------------------------------------------------------

function install_package
{
  local pkgpath="$1"
  echo "Installing $pkgpath ..."
  installpkg --terse $pkgpath
  stat=$?
  if [ $stat != 0 ]; then
    echo "ERROR: installpkg $pkgpath failed (status $stat)"
    itfailed
    return 1
  fi
  dotprofilizer $pkgpath
  return 0   # ignore any dotprofilizer problems, probably doesn't matter ;-)
}

#-------------------------------------------------------------------------------

function uninstall_with_deps
{
  local me="$1"
  :
}

#-------------------------------------------------------------------------------

function uninstall_package
{
  local prg="$1"
  # filter out false matches in /var/log/packages
  plist=$(ls /var/log/packages/$prg-*$TAG 2>/dev/null)
  pkgid=''
  for ppath in $plist; do
    p=$(basename $ppath)
    if [ "$(echo $p | rev | cut -f4- -d- | rev)" = "$prg" ]; then
      pkgid=$p
      break
    fi
  done
  [ -n "$pkgid" ] || { echo "Not removing $prg (not installed)"; return 1; }
  # Save a list of potential detritus in /etc
  etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/$pkgid)
  etcdirs=$(grep '^etc/.*/$' /var/log/packages/$pkgid)
  echo "Removing $pkgid"
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

function arch_unsupported
{
  local prg="$1"
  . $SBOREPO/*/$prg/$prg.info
  case $SLKARCH in
    i?86) DOWNLIST="$DOWNLOAD" ;;
  x86_64) DOWNLIST="${DOWNLOAD_x86_64:-$DOWNLOAD}" ;;
       *) DOWNLIST="$DOWNLOAD" ;;
  esac
  if [ "$DOWNLIST" != "UNSUPPORTED" -a "$DOWNLIST" != "UNTESTED" ]; then
    return 1
  fi
  echo_yellow "$prg is $DOWNLIST on $SLKARCH"
  return 0
}
