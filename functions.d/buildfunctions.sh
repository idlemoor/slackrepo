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
# $1 = itemname
# The built package goes into $SR_TMPOUT, but function build_ok then stores it elsewhere
# Return status:
# 0 = total success, world peace and happiness
# 1 = build failed
# 2 = download failed
# 3 = checksum failed
# 5 = skipped by hint, or unsupported on this arch
# 6 = SlackBuild returned 0 status, but nothing in $SR_TMPOUT
# 7 = excessively dramatic qa test fail
{
  local itemname="$1"
  local prg=$(basename $itemname)

  if hint_skipme $prg; then
    SKIPPEDLIST="$SKIPPEDLIST $itemname"
    return 5
  fi

  rm -f $SR_LOGDIR/$prg.log

  SR_TMPIN=$SR_TMP/slackrepo_IN
  rm -rf $SR_TMPIN
  cp -a $SR_GITREPO/$itemname $SR_TMPIN

  if [ "$PROCMODE" = 'test' ]; then
    qa_sbfiles $itemname || return 7
  fi

  # Load up the .info
  unset PRGNAM VERSION DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH}
  . $SR_TMPIN/$prg.info

  # Fiddle with $VERSION -- usually doomed to failure, but not always ;-)
  unset NEWVERSION
  hint_version $itemname
  if [ -n "$NEWVERSION" ]; then
    sed -i -e "s/$VERSION/$NEWVERSION/g" "$SR_TMPIN/$prg.info"
    sed -i -e "s/^VERSION=.*/VERSION=$NEWVERSION/" "$SR_TMPIN/$prg.SlackBuild"
    # reread the .info to pick up amended VERSION and downloads
    . $SR_TMPIN/$prg.info
    # (but also leave $NEWVERSION set, to inform verify_src that we upversioned)
  fi

  # Get the source (including check for unsupported/untested)
  verify_src $itemname
  case $? in
    0) # already got source, and it's good
       ;;
  1|2) # already got source, but it's bad => get it
       log_verbose "Note: cached source is bad"
       download_src $itemname
       verify_src $itemname || { log_error "${itemname}: Downloaded source is bad"; save_bad_src $itemname; build_failed $itemname; return 3; }
       ;;
    3) # not got source => get it
       download_src $itemname
       verify_src $itemname || { log_error "${itemname}: Downloaded source is bad"; save_bad_src $itemname; build_failed $itemname; return 3; }
       ;;
    4) # wrong version => get it
       download_src $itemname
       verify_src $itemname || { log_error "${itemname}: Downloaded source is bad"; save_bad_src $itemname; build_failed $itemname; return 3; }
       ;;
    5) # unsupported/untested
       SKIPPEDLIST="$SKIPPEDLIST $itemname"
       return 5
       ;;
  esac

  # Symlink the source into the temporary SlackBuild directory
  ln -sf -t $SR_TMPIN/ $DOWNDIR/*

  # Work out BUILD
  # Get the value from the SlackBuild
  unset BUILD
  buildassign=$(grep '^BUILD=' $SR_TMPIN/$prg.SlackBuild)
  if [ -z "$buildassign" ]; then
    buildassign="BUILD=1"
    log_warning "${itemname}: \"BUILD=\" not found in SlackBuild; using 1"
  fi
  eval $buildassign
  if [ "$OP" = 'add' -o "$PROCMODE" = 'test' ]; then
    # just use the SlackBuild's BUILD
    SR_BUILD="$BUILD"
  else
    # increment the existing BUILD or use the SlackBuild's (whichever is greater)
    oldbuild=$(ls $SR_PKGREPO/$itemname/*.t?z 2>/dev/null | sed -e 's/^.*-//' -e 's/[^0-9]*$//' )
    nextbuild=$(( ${oldbuild:-0} + 1 ))
    if [ "$nextbuild" -gt "$BUILD" ]; then
      SR_BUILD="$nextbuild"
    else
      SR_BUILD="$BUILD"
    fi
  fi

  # Get other hints for the build (uidgid, options, makeflags, answers)
  hint_uidgid $itemname
  tempmakeflags="$(hint_makeflags $itemname)"
  [ -n "$tempmakeflags" ] && log_verbose "Hint: $tempmakeflags"
  options="$(hint_options $itemname)"
  [ -n "$options" ] && log_verbose "Hint: options=\"$options\""
  SLACKBUILDCMD="env $tempmakeflags $options sh ./$prg.SlackBuild"
  if [ -f $SR_HINTS/$itemname.answers ]; then
    log_verbose "Hint: supplying answers from $SR_HINTS/$itemname.answers"
    SLACKBUILDCMD="cat $SR_HINTS/$itemname.answers | $SLACKBUILDCMD"
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
  log_normal "Running $prg.SlackBuild ..."
  ( cd $SR_TMPIN; eval $SLACKBUILDCMD ) >>$SR_LOGDIR/$prg.log 2>&1
  stat=$?
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS
  if [ $stat != 0 ]; then
    log_error "${itemname}: $prg.SlackBuild failed (status $stat)"
    build_failed $itemname
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=$(ls $SR_TMPOUT/*.t?z 2>/dev/null)
  if [ -z "$pkglist" ]; then
    log_error "${itemname}: No packages were created in $SR_TMPOUT"
    build_failed $itemname
    return 6
  fi

  if [ "$PROCMODE" = 'test' ]; then
    qa_package $pkglist || { build_failed $itemname; return 7; }
  fi

  build_ok $itemname  # \o/
  return 0
}

#-------------------------------------------------------------------------------

function check_arch_is_supported
{
  local itemname="$1"
  local prg=$(basename $itemname)

  . $SR_GITREPO/$itemname/$prg.info
  case $SR_ARCH in
    i?86) DOWNLIST="$DOWNLOAD" ;;
  x86_64) DOWNLIST="${DOWNLOAD_x86_64:-$DOWNLOAD}" ;;
       *) DOWNLIST="$DOWNLOAD" ;;
  esac
  if [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ]; then
    log_warning -n ":-/ $itemname is $DOWNLIST on $SR_ARCH /-:"
    return 1
  fi
  return 0
}

#-------------------------------------------------------------------------------

function build_ok
{
  local itemname="$1"
  local prg=$(basename $itemname)

  rm -rf $SR_TMPIN

  if [ "$PROCMODE" = 'test' ]; then
    # put the package into the special test repo
    mkdir -p $SR_TESTREPO/$itemname
    rm -rf $SR_TESTTREPO/$itemname/*
    mv $SR_TMPOUT/* $SR_TESTREPO/$itemname/
    rm -rf $SR_TMPOUT
  else
    # put it into the real package repo
    mkdir -p $SR_PKGREPO/$itemname
    rm -rf $SR_PKGREPO/$itemname/*
    mv $SR_TMPOUT/* $SR_PKGREPO/$itemname/
    rm -rf $SR_TMPOUT
  fi

  # This won't always kill everything, but it's good enough for saving space
  rm -rf $SR_TMP/${prg}* $SR_TMP/package-${prg}

  msg="$OP OK"
  log_success ":-) $itemname $msg (-:"
  PASSEDLIST="$PASSEDLIST $itemname"
  return
}

#-------------------------------------------------------------------------------

function build_failed
{
  local itemname="$1"
  local prg=$(basename $itemname)

  rm -rf $SR_TMPIN $SR_TMPOUT
  # but don't remove files from $TMP, they can help to diagnose why it failed

  msg="$OP FAILED"
  log_error -n ":-( $itemname $msg )-:"
  log_error -n "See $SR_LOGDIR/$prg.log"
  FAILEDLIST="$FAILEDLIST $itemname"
  return
}
