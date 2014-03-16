#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# srcfunctions.sh - source functions for slackrepo
#   verify_src
#   download_src
#   save_bad_src
#-------------------------------------------------------------------------------

function verify_src
# Verify item's source files in the source cache
# $1 = itempath
# Also uses variables $VERSION and $NEWVERSION set by build_package
# Return status:
# 0 - all files passed, or check suppressed
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

  if [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ]; then
    log_warning -n "$itempath is $DOWNLIST on $SR_ARCH"
    return 5
  elif [ ! -d $DOWNDIR ]; then
    return 3
  fi

  ( cd $DOWNDIR
    log_normal -p "Verifying source files ..."
    if [ "$VERSION" != "$(cat .version 2>/dev/null)" ]; then
      log_verbose -p "Note: removing old source files"
      find . -maxdepth 1 -type f -exec rm -f {} \;
      return 4
    fi
    numgot=$(find . -maxdepth 1 -type f -print 2>/dev/null| grep -v '.version' | wc -l)
    numwant=$(echo $MD5LIST | wc -w)
    [ $numgot = $numwant ] || { log_verbose -p "Note: need $numwant source files, but have $numgot"; return 2; }
    hint_md5ignore $itempath && return 0
    # also ignore md5sum if we upversioned
    [ -n "$NEWVERSION" ] && { log_verbose -p "Note: not checking md5sums due to version hint"; return 0; }
    allok='y'
    for f in *; do
      # check that it's a file (arch-specific subdirectories may exist)
      if [ -f "$f" ]; then
        mf=$(md5sum "$f" | sed 's/ .*//')
        ok='n'
        # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
        for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
        [ "$ok" = 'y' ] || { log_verbose -p "Note: failed md5sum: $f"; allok='n'; }
      fi
    done
    [ "$allok" = 'y' ] || { return 1; }
    ##### Would it be nice to remove _BAD if all files passed?
  )
  return $?  # status comes directly from subshell
}

#-------------------------------------------------------------------------------

function download_src
# Download the sources for itempath into the cache, and stamp the cache with a .version file
# $1 = itempath
# Also uses variables $DOWNDIR and $DOWNLIST previously set by verify_src,
# and $VERSION set by build_package
# Return status:
# 1 - wget failed
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  mkdir -p $DOWNDIR
  find $DOWNDIR -maxdepth 1 -type f -exec rm {} \;
  log_normal -p "Downloading source files ..."
  ( cd $DOWNDIR
    for src in $DOWNLIST; do
      log_verbose -p "wget $src ..."
      wget --no-check-certificate --content-disposition --tries=2 -T 240 "$src" >> $SR_LOGDIR/$itempath.log 2>&1
      wstat=$?
      if [ $wstat != 0 ]; then
        log_error -p "Download failed (wget status $wstat)"
        return 1
      fi
    done
    echo "$VERSION" > .version
  )
  return 0
}

#-------------------------------------------------------------------------------

function save_bad_src
# Move $SR_SRCREPO/<itempath>/[<arch>/] to $SR_SRCREPO/<itempath>_BAD/[<arch>/],
# in case it's useful for diagnostic purposes or can be resurrected.
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  baddir=$SR_SRCREPO/${itempath}_BAD
  # remove any previous bad sources
  rm -rf $baddir
  # remove empty directories
  find $SR_SRCREPO/${itempath} -depth -type d -exec rmdir --ignore-fail-on-non-empty {} \;
  # save whatever survives
  if [ -d $SR_SRCREPO/${itempath}/$SR_ARCH ]; then
    mkdir -p $baddir
    mv $SR_SRCREPO/${itempath}/$SR_ARCH $baddir/
    log_normal -p "Note: bad sources saved in $baddir/$SR_ARCH"
    # if there's stuff from other arches, leave it
    rmdir --ignore-fail-on-non-empty $SR_SRCREPO/${itempath}
  elif [ -d $SR_SRCREPO/${itempath} ]; then
    # this isn't perfect, but it'll do ###### need arch code
    mv $SR_SRCREPO/${itempath} $baddir
    log_normal -p "Note: bad sources saved in $baddir"
  fi
  return 0
}
