#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# srcfunctions.sh - source functions for slackrepo
#   verify_src
#   download_src
#-------------------------------------------------------------------------------

function verify_src
# Verify item's source files in the source cache
# $1 = itempath
# Also uses variables $VERSION and $NEWVERSION set by build_package
# Return status:
# 0 - all files passed, or check suppressed, or DOWNLIST is empty
# 1 - one or more files had a bad md5sum
# 2 - no. of files != no. of md5sums
# 3 - directory not found => not cached, need to download
# 4 - version mismatch, need to download new version
# 5 - .info says item is unsupported/untested on this arch
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  DOWNLIST="${INFODOWNLIST[$itempath]}"
  MD5LIST="${INFOMD5LIST[$itempath]}"
  DOWNDIR="${SRCDIR[$itempath]}"

  # return 0 if nothing to verify:
  [ -z "$DOWNLIST" -o -z "$DOWNDIR" ] && return 0

  if [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ]; then
    log_warning -n "$itempath is $DOWNLIST on $SR_ARCH"
    return 5
  elif [ ! -d "$DOWNDIR" ]; then
    return 3
  fi

  ( cd "$DOWNDIR"
    log_normal -a "Verifying source files ..."
    if [ "$VERSION" != "$(cat .version 2>/dev/null)" ]; then
      log_verbose -a "Note: removing old source files"
      find . -maxdepth 1 -type f -exec rm -f {} \;
      return 4
    fi
    numgot=$(find . -maxdepth 1 -type f -print 2>/dev/null| grep -v '^\./\.version$' | wc -l)
    numwant=$(echo $MD5LIST | wc -w)
    [ $numgot = $numwant ] || { log_verbose -a "Note: need $numwant source files, but have $numgot"; return 2; }
    [ "${HINT_md5ignore[$itempath]}" = 'y' ] && return 0
    # also ignore md5sum if we upversioned
    [ -n "$NEWVERSION" ] && { log_verbose -a "Note: not checking md5sums due to version hint"; return 0; }
    allok='y'
    for f in *; do
      # check that it's a file (arch-specific subdirectories may exist)
      if [ -f "$f" ]; then
        mf=$(md5sum "$f" | sed 's/ .*//')
        ok='n'
        # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
        for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
        [ "$ok" = 'y' ] || { log_verbose -a "Note: failed md5sum: $f"; allok='n'; }
      fi
    done
    [ "$allok" = 'y' ] || { return 1; }
  )
  return $?  # status comes directly from subshell
}

#-------------------------------------------------------------------------------

function download_src
# Download the sources for itempath into the cache
# $1 = itempath
# Also uses variables $DOWNDIR and $DOWNLIST previously set by verify_src,
# and $VERSION set by build_package
# Return status:
# 1 - curl failed
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ -n "$DOWNDIR" ]; then
    mkdir -p "$DOWNDIR"
    find "$DOWNDIR" -maxdepth 1 -type f -exec rm {} \;
    # stamp the cache with a .version file, even if there are no sources
    echo "$VERSION" > "$DOWNDIR"/.version
  fi

  [ -z "$DOWNLIST" -o -z "$DOWNDIR" ] && return 0

  log_normal -a "Downloading source files ..."
  ( cd "$DOWNDIR"
    if [ -n "$DOWNLIST" ]; then
      downargs=""
      for url in $DOWNLIST; do downargs="$downargs -O $url"; done
      curl -q -f '-#' -k --connect-timeout 120 --retry 2 -J -L $downargs >> $ITEMLOG 2>&1
      curlstat=$?
      if [ $curlstat != 0 ]; then
        log_error -a "Download failed (curl status $curlstat)"
        return 1
      fi
    fi
  )
  return 0
}
