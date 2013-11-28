#!/bin/bash
#-------------------------------------------------------------------------------
# srcfunctions.sh - source functions for SBoggit:
#   downloadsrc
#   checksrc
#   savebadsrc
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

function downloadsrc
{
  # Returns:
  # 1 - wget failed
  # 2 - UNSUPPORTED or UNTESTED in .info
  local p="${1:-$prg}"
  # This function also uses global variables DOWNLOAD* previously read from .info
  case $SLKARCH in
    i486) DOWNLIST="$DOWNLOAD" ;;
  x86_64) DOWNLIST="${DOWNLOAD_x86_64:-$DOWNLOAD}" ;;
       *) DOWNLIST="$DOWNLOAD" ;;
  esac
  if [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ]; then
    echo "$DOWNLIST ON $SLKARCH"
    echo "$DOWNLIST ON $SLKARCH" > $HINTS/$p.skipme
    return 2
  fi
  rm -rf $SRCDIR/$p
  mkdir -p $SRCDIR/$p
  echo "Downloading ..."
  ( cd $SRCDIR/$p
    for src in $DOWNLIST; do
      echo "wget $src ..."
      wget --no-check-certificate --content-disposition --tries=2 -T 240 "$src" >> $LOGDIR/$p.log 2>&1
      wstat=$?
      if [ $wstat != 0 ]; then
        echored "ERROR: wget error (status $wstat)"
        return 1
      fi
    done
  )
  return 0
}

#-------------------------------------------------------------------------------

function checksrc
{
  # Returns:
  # 1 - one or more files had a bad md5sum
  # 2 - no. of files != no. of md5sums
  local p="${1:-$prg}"
  # This function also uses global variables MD5SUM* previously read from .info
  ( cd $SRCDIR/${p}
    case $SLKARCH in
      i486) MD5LIST="$MD5SUM" ;;
    x86_64) MD5LIST="${MD5SUM_x86_64:-$MD5SUM}" ;;
         *) MD5LIST="$MD5SUM" ;;
    esac
    echo "Checking source files ..."
    numgot=$(ls 2>/dev/null| wc -l)
    numwant=$(echo $MD5LIST | wc -w)
    [ $numgot = $numwant ] || { echo "ERROR: want $numwant source files but got $numgot"; return 2; }
    allok='y'
    for f in *; do
      mf=$(md5sum "$f" | sed 's/ .*//')
      ok='n'
      # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
      for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
      [ "$ok" = 'y' ] || { echo "ERROR: Failed md5sum: '$f'"; allok='n'; }
    done
    [ "$allok" = 'y' ] || { return 1; }
  )
  return $?  # status comes from subshell
}

#-------------------------------------------------------------------------------

function savebadsrc
{
  local p="${1:-$prg}"
  [ -d $SRCDIR/${p} ] && rmdir --ignore-fail-on-non-empty $SRCDIR/${p}
  if [ -d $SRCDIR/${p} ]; then
    baddir=$SRCDIR/${p}_BAD
    rm -rf $baddir
    mv $SRCDIR/$p $baddir
    echo "Note: bad sources saved in $baddir"
  fi
}

