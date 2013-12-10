#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# srcfunctions.sh - source functions for sboggit:
#   check_src
#   download_src
#   save_bad_src
#   clean_srcdir
#-------------------------------------------------------------------------------

function check_src
{
  local p="${1:-$prg}"
  # This function also uses global variables MD5SUM* previously read from .info
  # Returns:
  # 1 - one or more files had a bad md5sum
  # 2 - no. of files != no. of md5sums
  # 3 - directory not found => not yet downloaded
  # 4 - unsupported/untested
  if [ -n "$(eval echo \$DOWNLOAD_$SB_ARCH)" ]; then
    DOWNDIR=$SB_SRC/$p/$SB_ARCH
    DOWNLIST="$(eval echo \$DOWNLOAD_$SB_ARCH)"
    MD5LIST="$(eval echo \$MD5SUM_$SB_ARCH)"
  else
    DOWNDIR=$SB_SRC/$p
    DOWNLIST="$DOWNLOAD"
    MD5LIST="$MD5SUM"
  fi
  if [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ]; then
    log_warning "$prg is $DOWNLIST on $SB_ARCH"
    return 4
  elif [ ! -d $DOWNDIR ]; then
    return 3
  fi
  ( cd $DOWNDIR
    echo "Checking source files ..."
    numgot=$(find . -maxdepth 1 -type f -print 2>/dev/null| wc -l)
    numwant=$(echo $MD5LIST | wc -w)
    [ $numgot = $numwant ] || { echo "ERROR: want $numwant source files but got $numgot"; return 2; }
    hint_md5ignore $prg && return 0
    allok='y'
    for f in *; do
      # check that it's a file (arch-specific subdirectories may exist)
      if [ -f "$f" ]; then
        mf=$(md5sum "$f" | sed 's/ .*//')
        ok='n'
        # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
        for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
        [ "$ok" = 'y' ] || { echo "ERROR: Failed md5sum: '$f'"; allok='n'; }
      fi
    done
    [ "$allok" = 'y' ] || { return 1; }
  )
  return $?  # status comes from subshell
}

#-------------------------------------------------------------------------------

function download_src
{
  local p="${1:-$prg}"
  # This function also uses global variables DOWNLOAD* previously read from .info
  # and DOWNDIR/DOWNLIST previously set by check_src
  # Returns:
  # 1 - wget failed
  mkdir -p $DOWNDIR
  find $DOWNDIR -maxdepth 1 -type f -exec rm {} \;
  echo "Downloading ..."
  ( cd $DOWNDIR
    for src in $DOWNLIST; do
      echo "wget $src ..."
      wget --no-check-certificate --content-disposition --tries=2 -T 240 "$src" >> $SB_LOGDIR/$p.log 2>&1
      wstat=$?
      if [ $wstat != 0 ]; then
        log_error "ERROR: wget error (status $wstat)"
        return 1
      fi
    done
  )
  return 0
}

#-------------------------------------------------------------------------------

function save_bad_src
{
  local p="${1:-$prg}"
  baddir=$SB_SRC/${p}_BAD
  # remove any previous bad sources
  rm -rf $baddir
  # remove empty directories
  find $SB_SRC/${p} -depth -type d -exec rmdir --ignore-fail-on-non-empty {} \;
  # save whatever survives
  if [ -d $SB_SRC/${p}/$SB_ARCH ]; then
    mkdir -p $baddir
    mv $SB_SRC/${p}/$SB_ARCH $baddir/
    echo "Note: bad sources saved in $baddir/$SB_ARCH"
    # if there's stuff from other arches, leave it
    rmdir --ignore-fail-on-non-empty $SB_SRC/${p}
  elif [ -d $SB_SRC/${p} ]; then
    # this isn't perfect, but it'll do
    mv $SB_SRC/${p} $baddir
    echo "Note: bad sources saved in $baddir"
  fi
}

#-------------------------------------------------------------------------------

function clean_srcdir
{
  # will remove *_BAD directories as well as obsolete/removed directories :-)
  echo "Cleaning source directory $SB_SRC ..."
  for srcpath in $(ls $SB_SRC/* 2>/dev/null); do
    pkgname=$(basename $srcpath)
    if [ ! -d "$(ls -d $SB_REPO/*/$pkgname 2>/dev/null)" ]; then
      rm -rf -v "$SB_SRC/$pkgname"
    fi
  done
  echo "Finished cleaning source directory."
}
