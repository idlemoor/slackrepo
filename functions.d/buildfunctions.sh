#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for slackrepo
#   build_package
#   check_arch_is_supported
#   build_ok
#   build_failed
#-------------------------------------------------------------------------------

function build_package
# Build the package for an item
# $1 = itempath
# The built package goes into $SR_TMPOUT, but function build_ok then stores it elsewhere
# Return status:
# 0 = total success, world peace and happiness
# 1 = build failed
# 2 = download failed
# 3 = checksum failed
# 4 = [not used]
# 5 = skipped by hint, or unsupported on this arch
# 6 = SlackBuild returned 0 status, but nothing in $SR_TMPOUT
# 7 = excessively dramatic qa test fail
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if hint_skipme $itempath; then
    SKIPPEDLIST="$SKIPPEDLIST $itempath"
    return 5
  fi

  rm -f $SR_LOGDIR/$prgnam.log

  SR_TMPIN=$SR_TMP/slackrepo_IN
  rm -rf $SR_TMPIN
  cp -a $SR_GITREPO/$itempath $SR_TMPIN

  if [ "$OPT_TEST" = 'y' ]; then
    qa_slackbuild $itempath || return 7
  fi

  # Fiddle with $VERSION -- usually doomed to failure, but not always ;-)
  VERSION="${INFOVERSION[$itempath]}"
  hint_version $itempath
  if [ -n "$NEWVERSION" ]; then
    sed -i -e "s/^VERSION=.*/VERSION=$NEWVERSION/" "$SR_TMPIN/$prgnam.SlackBuild"
    verpat="$(echo ${INFOVERSION[$itempath]} | sed 's/\./\\\./g')"
    INFODOWNLIST[$itempath]="$(echo "${INFODOWNLIST[$itempath]}" | sed "s/$verpat/$NEWVERSION/g")"
    VERSION="$NEWVERSION"
    # (but also leave $NEWVERSION set, to inform verify_src that we upversioned)
  fi

  # Get the source (including check for unsupported/untested)
  verify_src $itempath
  case $? in
    0) # already got source, and it's good
       ;;
  1|2) # already got source, but it's bad => get it
       log_verbose "Note: cached source is bad"
       download_src $itempath
       verify_src $itempath || { log_error "${itempath}: Downloaded source is bad"; save_bad_src $itempath; build_failed $itempath; return 3; }
       ;;
    3) # not got source => get it
       download_src $itempath
       verify_src $itempath || { log_error "${itempath}: Downloaded source is bad"; save_bad_src $itempath; build_failed $itempath; return 3; }
       ;;
    4) # wrong version => get it
       download_src $itempath
       verify_src $itempath || { log_error "${itempath}: Downloaded source is bad"; save_bad_src $itempath; build_failed $itempath; return 3; }
       ;;
    5) # unsupported/untested
       SKIPPEDLIST="$SKIPPEDLIST $itempath"
       return 5
       ;;
  esac

  # Symlink the source into the temporary SlackBuild directory
  ln -sf -t $SR_TMPIN/ ${SRCDIR[$itempath]}/*

  # Work out BUILD
  # Get the value from the SlackBuild
  unset BUILD
  buildassign=$(grep '^BUILD=' $SR_TMPIN/$prgnam.SlackBuild)
  if [ -z "$buildassign" ]; then
    buildassign="BUILD=1"
    log_warning "${itempath}: \"BUILD=\" not found in SlackBuild; using 1"
  fi
  eval $buildassign
  if [ "$OP" = 'add' -o "$OPT_DRYRUN" = 'y' ]; then
    # just use the SlackBuild's BUILD
    SR_BUILD="$BUILD"
  else
    # increment the existing BUILD or use the SlackBuild's (whichever is greater)
    oldbuild=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null | sed -e 's/^.*-//' -e 's/[^0-9]*$//' )
    nextbuild=$(( ${oldbuild:-0} + 1 ))
    if [ "$nextbuild" -gt "$BUILD" ]; then
      SR_BUILD="$nextbuild"
    else
      SR_BUILD="$BUILD"
    fi
  fi

  # Get other hints for the build (uidgid, options, makeflags, answers)
  hint_uidgid $itempath
  tempmakeflags="$(hint_makeflags $itempath)"
  [ -n "$tempmakeflags" ] && log_verbose "Hint: $tempmakeflags"
  options="$(hint_options $itempath)"
  [ -n "$options" ] && log_verbose "Hint: options=\"$options\""
  SLACKBUILDCMD="env $tempmakeflags $options sh ./$prgnam.SlackBuild"
  if [ -f $SR_HINTS/$itempath.answers ]; then
    log_verbose "Hint: supplying answers from $SR_HINTS/$itempath.answers"
    SLACKBUILDCMD="cat $SR_HINTS/$itempath.answers | $SLACKBUILDCMD"
  fi

  # Build it
  SR_TMPOUT=$SR_TMP/slackrepo_OUT
  rm -rf $SR_TMPOUT
  mkdir -p $SR_TMPOUT
  export \
    ARCH=$SR_ARCH \
    BUILD=$SR_BUILD \
    TAG=$SR_TAG \
    TMP=$SR_TMP \
    OUTPUT=$SR_TMPOUT \
    PKGTYPE=$SR_PKGTYPE \
    NUMJOBS=$SR_NUMJOBS
  log_normal "Running $prgnam.SlackBuild ..."
  ( cd $SR_TMPIN; eval $SLACKBUILDCMD ) >>$SR_LOGDIR/$prgnam.log 2>&1
  stat=$?
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS
  if [ $stat != 0 ]; then
    log_error "${itempath}: $prgnam.SlackBuild failed (status $stat)"
    build_failed $itempath
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=$(ls $SR_TMPOUT/*.t?z 2>/dev/null)
  if [ -z "$pkglist" ]; then
    log_error "${itempath}: No packages were created in $SR_TMPOUT"
    build_failed $itempath
    return 6
  fi

  if [ "$OPT_TEST" = 'y' ]; then
    qa_package $itempath $pkglist || { build_failed $itempath; return 7; }
  fi

  build_ok $itempath  # \o/
  return 0
}

#-------------------------------------------------------------------------------

function check_arch_is_supported
# Check whether the .info file says this item is unsupported on this arch
# $1 = itempath
# Return status:
# 0 = supported
# 1 = unsupported
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  downlist="${INFODOWNLIST[$itempath]}"
  if [ "$downlist" = "UNSUPPORTED" -o "$downlist" = "UNTESTED" ]; then
    log_warning -n ":-/ $itempath is $downlist on $SR_ARCH /-:"
    return 1
  fi
  return 0
}

#-------------------------------------------------------------------------------

function build_ok
# Log, cleanup and store the packages for a build that has succeeded
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  rm -rf $SR_TMPIN

  if [ "$OPT_DRYRUN" = 'y' ]; then
    # put the package into the special dryrun repo
    mkdir -p $SR_DRYREPO/$itempath
    rm -rf $SR_DRYREPO/$itempath/*
    mv $SR_TMPOUT/* $SR_DRYREPO/$itempath/
  else
    # put it into the real package repo
    mkdir -p $SR_PKGREPO/$itempath
    rm -rf $SR_PKGREPO/$itempath/*
    mv $SR_TMPOUT/* $SR_PKGREPO/$itempath/
  fi
  rm -rf $SR_TMPOUT

  # This won't always kill everything, but it's good enough for saving space
  rm -rf $SR_TMP/${prgnam}* $SR_TMP/package-${prgnam}

  msg="$OP OK"
  log_success ":-) $itempath $msg (-:"
  PASSEDLIST="$PASSEDLIST $itempath"
  return 0
}

#-------------------------------------------------------------------------------

function build_failed
# Log and cleanup for a build that has failed
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  rm -rf $SR_TMPIN $SR_TMPOUT
  # but don't remove files from $TMP, they can help to diagnose why it failed

  msg="$OP FAILED"
  log_error -n ":-( $itempath $msg )-:"
  log_error -n "See $SR_LOGDIR/$prgnam.log"
  FAILEDLIST="$FAILEDLIST $itempath"
  return 0
}
