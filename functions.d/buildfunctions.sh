#!/bin/bash
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for SBoggit:
#   build_package
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

function build_package
{
  local prg="$1"
  # Returns:
  # 1 - build failed
  # 2 - download failed
  # 3 - checksum failed
  # 4 - installpkg returned nonzero
  # 5 - skipped by hint, or unsupported on this arch
  # 6 - build returned 0 but nothing in $OUTPUT

  local category=$(cd $SBOREPO/*/$prg/..; basename $(pwd))
  echo_lined "$category/$prg"
  rm -f $LOGDIR/$prg.log

  # Load up the .info (and BUILD from the SlackBuild)
  . $SBOREPO/$category/$prg/$prg.info
  if [ "$PRGNAM" != "$prg" ]; then
    echo_yellow "WARNING: PRGNAM in $SBOREPO/$category/$prg/$prg.info is '$PRGNAM', not $prg"
  fi
  unset BUILD
  buildassign=$(grep '^BUILD=' $SBOREPO/*/$PRGNAM/$PRGNAM.SlackBuild)
  eval $buildassign
  # At this point we have a full set of environment variables for called functions to use:
  # PRGNAM VERSION SLKARCH BUILD TAG DOWNLOAD* MD5SUM* etc

  arch_unsupported $prg && return 5
  hint_skipme $prg && return 5

  # Get the source and symlink it into the SlackBuild directory
  if [ -d $SRCCACHE/$prg ]; then
    if ! check_src ; then
      echo "Note: bad checksums in cached source, will download again"
      download_src
      case $? in
        0) check_src || { save_bad_src; itfailed; return 3; } ;;
        2) rm -rf $SRCCACHE/$prg;  return 5 ;;
        *) save_bad_src; itfailed; return 2 ;;
      esac
    fi
  else
    download_src
    case $? in
      0) check_src || { save_bad_src; itfailed; return 3; } ;;
      2) rm -rf $SRCCACHE/$prg;  return 5 ;;
      *) save_bad_src; itfailed; return 2 ;;
    esac
  fi
  ln -sf -t $SBOREPO/$category/$prg/ $SRCCACHE/$prg/*

  # Get any hints for the build
  hint_uidgid $prg
  tempmakeflags="$(hint_makeflags $prg)"
  [ -n "$tempmakeflags" ] && echo "Hint: $tempmakeflags"
  options="$(hint_options $prg)"
  [ -n "$options" ] && echo "Hint: options=\"$options\""
  BUILDCMD="env $tempmakeflags $options sh ./$prg.SlackBuild"
  if [ -f $HINTS/$prg.answers ]; then
    echo "Hint: supplying answers from $HINTS/$prg.answers"
    BUILDCMD="cat $HINTS/$prg.answers | $BUILDCMD"
  fi

  # Build it
  echo "SlackBuilding $prg.SlackBuild ..."
  export OUTPUT=$OUTREPO/$prg
  rm -rf $OUTPUT/*
  mkdir -p $OUTPUT
  ( cd $SBOREPO/$category/$prg; eval $BUILDCMD ) >>$LOGDIR/$prg.log 2>&1
  stat=$?
  if [ $stat != 0 ]; then
    echo "ERROR: $prg.SlackBuild failed (status $stat)"
    itfailed
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=$(ls $OUTPUT/*.t?z 2>/dev/null)
  if [ -z "$pkglist" ]; then
    echo "ERROR: no packages found in $OUTPUT"
    itfailed
    return 6
  fi

  # Install the built packages
  # (this supports multiple output packages because some Slackware SlackBuilds do that)
  for pkgpath in $pkglist; do
    check_package $pkgpath
    install_package $pkgpath || return 4
  done

  itpassed  # \o/
  return 0
}
