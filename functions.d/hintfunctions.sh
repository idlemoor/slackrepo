#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# hintfunctions.sh - functions for SBoggit hints:
#   hint_skipme
#   hint_md5ignore
#   hint_uidgid
#   hint_options
#   hint_makeflags
#   hint_cleanup
#-------------------------------------------------------------------------------

function hint_skipme
{
  local prg="$1"
  # Note the return status: 0 = skip, 1 = do not skip
  if [ ! -f $SB_HINTS/$prg.skipme ]; then
    return 1
  fi
  category=$(cd $SB_REPO/*/$prg/..; basename $(pwd))
  echo_yellow "SKIPPED $category/$prg due to hint"
  cat $SB_HINTS/$prg.skipme
  return 0
}

#-------------------------------------------------------------------------------

function hint_md5ignore
{
  local prg="$1"
  # Note the return status: 0 = skip, 1 = do not skip
  if [ ! -f $SB_HINTS/$prg.md5ignore ]; then
    return 1
  fi
  echo "Hint: ignoring md5sums for $prg"
  cat $SB_HINTS/$prg.md5ignore
  return 0
}

#-------------------------------------------------------------------------------

function hint_uidgid
{
  local prg="$1"
  # Returns 1 if no hint found.
  # The prg.uidgid file should contain
  # *either* an assignment of UIDGIDNUMBER and (optionally) UIDGIDNAME,
  #          UIDGIDCOMMENT, UIDGIDDIR, UIDGIDSHELL
  # *or* a script to make the UID and/or the GID, if it's not straightforward.
  [ -f $SB_HINTS/$prg.uidgid ] || return 1
  unset UIDGIDNUMBER
  echo "Hint: setup uid/gid for $prg"
  . $SB_HINTS/$prg.uidgid
  [ -n "$UIDGIDNUMBER" ] || return 0
  UIDGIDNAME=${UIDGIDNAME:-$prg}
  if ! getent group $UIDGIDNAME | grep -q ^$UIDGIDNAME: 2>/dev/null ; then
    groupadd -g $UIDGIDNUMBER $UIDGIDNAME
  fi
  if ! getent passwd $UIDGIDNAME | grep -q ^$UIDGIDNAME: 2>/dev/null ; then
    useradd \
      -u $UIDGIDNUMBER \
      -c ${UIDGIDCOMMENT:-$UIDGIDNAME} \
      -d ${UIDGIDDIR:-/dev/null} \
      -s ${UIDGIDSHELL:-/bin/false} \
      -g $UIDGIDNAME \
      $UIDGIDNAME
  fi
  return 0
}

#-------------------------------------------------------------------------------

function hint_options
{
  local prg="$1"
  # Prints options to standard output, so don't display any messages here!
  if [ -f $SB_HINTS/$prg.options ]; then
    echo "$(cat $SB_HINTS/$prg.options)"
  fi
}

#-------------------------------------------------------------------------------

function hint_makeflags
{
  local prg="$1"
  # Prints makeflags to standard output, so don't display any messages here!
  # Currently handles only -j1 (no real requirement for anything else).
  if [ -f $SB_HINTS/$prg.makej1 ]; then
    echo "MAKEFLAGS='-j1'"
  fi
}

#-------------------------------------------------------------------------------

function hint_cleanup
{
  local prg="$1"
  # Returns 1 if no hint found.
  # The prg.cleanup file can contain any required shell commands, for example:
  #   * Reinstalling Slackware packages that conflict with prg
  #   * Unsetting any environment variables set in prg's /etc/profile.d script
  #   * Removing specific files and directories that removepkg doesn't remove
  #   * Running depmod to remove references to removed kernel modules
  [ -f $SB_HINTS/$prg.cleanup ] || return 1
  echo "Hint: running $SB_HINTS/$prg.cleanup ..."
  . $SB_HINTS/$prg.cleanup >>$SB_LOGDIR/$prg.log 2>&1
  return 0
}
