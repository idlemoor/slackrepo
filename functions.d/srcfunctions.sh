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
# $1 = itemname
# Also uses global variables MD5SUM* previously read from .info
# Return status:
# 0 - all files passed, or check suppressed
# 1 - one or more files had a bad md5sum
# 2 - no. of files != no. of md5sums
# 3 - directory not found => not cached, need to download
# 4 - version mismatch, need to download new version
# 5 - .info says item is unsupported/untested on this arch
{
  local itemname="$1"
  local prg=$(basename $itemname)

  if [ -n "$(eval echo \$DOWNLOAD_$SR_ARCH)" ]; then
    DOWNDIR=$SR_SRCREPO/$itemname/$SR_ARCH
    DOWNLIST="$(eval echo \$DOWNLOAD_$SR_ARCH)"
    MD5LIST="$(eval echo \$MD5SUM_$SR_ARCH)"
  else
    DOWNDIR=$SR_SRCREPO/$itemname
    DOWNLIST="$DOWNLOAD"
    MD5LIST="$MD5SUM"
  fi
  if [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ]; then
    log_warning -n "$itemname is $DOWNLIST on $SR_ARCH"
    return 5
  elif [ ! -d $DOWNDIR ]; then
    return 3
  fi

  ( cd $DOWNDIR
    log_normal "Verifying source files ..."
    if [ "$VERSION" != "$(cat .version 2>/dev/null)" ]; then
      log_verbose "Note: removing old source files"
      find . -maxdepth 1 -type f -exec rm -f {} \;
      return 4
    fi
    numgot=$(find . -maxdepth 1 -type f -print 2>/dev/null| grep -v '.version' | wc -l)
    numwant=$(echo $MD5LIST | wc -w)
    [ $numgot = $numwant ] || { log_verbose "Note: need $numwant source files, but have $numgot"; return 2; }
    hint_md5ignore $itemname && return 0
    [ -n "$NEWVERSION" ] && { log_verbose "Note: not checking md5sums due to version hint"; return 0; }
    allok='y'
    for f in *; do
      # check that it's a file (arch-specific subdirectories may exist)
      if [ -f "$f" ]; then
        mf=$(md5sum "$f" | sed 's/ .*//')
        ok='n'
        # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
        for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
        [ "$ok" = 'y' ] || { log_verbose "Note: failed md5sum: $f"; allok='n'; }
      fi
    done
    [ "$allok" = 'y' ] || { return 1; }
    ##### Would it be nice to remove _BAD if all files passed?
  )
  return $?  # status comes directly from subshell
}

#-------------------------------------------------------------------------------

function download_src
# Download the sources for itemname into the cache, and stamp the cache with a .version file
# $1 = itemname
# Also uses global variables $DOWNLOAD* previously read from .info,
# and $DOWNDIR and $DOWNLIST previously set by verify_src
# Return status:
# 1 - wget failed
{
  local itemname="$1"
  local prg=$(basename $itemname)

  mkdir -p $DOWNDIR
  find $DOWNDIR -maxdepth 1 -type f -exec rm {} \;
  log_normal "Downloading source files ..."
  ( cd $DOWNDIR
    for src in $DOWNLIST; do
      log_verbose "wget $src ..."
      wget --no-check-certificate --content-disposition --tries=2 -T 240 "$src" >> $SR_LOGDIR/$prg.log 2>&1
      wstat=$?
      if [ $wstat != 0 ]; then
        log_error "Download failed (wget status $wstat)"
        return 1
      fi
    done
    echo "$VERSION" > .version
  )
  return 0
}

#-------------------------------------------------------------------------------

function save_bad_src
# Move $SR_SRCREPO/<itemname>/[<arch>/] to $SR_SRCREPO/<itemname>_BAD/[<arch>/],
# in case it's useful for diagnostic purposes or can be resurrected.
# $1 = itemname
# Return status: always 0
{
  local itemname="$1"
  local prg=$(basename $itemname)

  baddir=$SR_SRCREPO/${itemname}_BAD
  # remove any previous bad sources
  rm -rf $baddir
  # remove empty directories
  find $SR_SRCREPO/${itemname} -depth -type d -exec rmdir --ignore-fail-on-non-empty {} \;
  # save whatever survives
  if [ -d $SR_SRCREPO/${itemname}/$SR_ARCH ]; then
    mkdir -p $baddir
    mv $SR_SRCREPO/${itemname}/$SR_ARCH $baddir/
    log_normal "Note: bad sources saved in $baddir/$SR_ARCH"
    # if there's stuff from other arches, leave it
    rmdir --ignore-fail-on-non-empty $SR_SRCREPO/${itemname}
  elif [ -d $SR_SRCREPO/${itemname} ]; then
    # this isn't perfect, but it'll do
    mv $SR_SRCREPO/${itemname} $baddir
    log_normal "Note: bad sources saved in $baddir"
  fi
  return 0
}
