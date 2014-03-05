#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# hintfunctions.sh - functions for slackrepo hints:
#   hint_skipme
#   hint_md5ignore
#   hint_uidgid
#   hint_options
#   hint_makeflags
#   hint_cleanup
#   hint_nocleanup
#-------------------------------------------------------------------------------

function hint_skipme
# Note the return status: 0 = skip, 1 = do not skip
{
  local itemname="$1"
  local prg=$(basename $itemname)

  if [ ! -f $SR_HINTS/$itemname.skipme ]; then
    return 1
  fi
  log_warning -n "SKIPPED $itemname due to hint"
  cat $SR_HINTS/$itemname.skipme
  return 0
}

#-------------------------------------------------------------------------------

function hint_md5ignore
# Note the return status: 0 = skip, 1 = do not skip
{
  local itemname="$1"
  local prg=$(basename $itemname)

  if [ ! -f $SR_HINTS/$itemname.md5ignore ]; then
    return 1
  fi
  log_verbose "Hint: $prg: ignoring md5sums"
  return 0
}

#-------------------------------------------------------------------------------

function hint_uidgid
# Returns 1 if no hint found.
# The prg.uidgid file should contain
# *either* an assignment of UIDGIDNUMBER and (optionally) UIDGIDNAME,
#          UIDGIDCOMMENT, UIDGIDDIR, UIDGIDSHELL
# *or* a script to make the UID and/or the GID, if it's not straightforward.
{
  local itemname="$1"
  local prg=$(basename $itemname)

  [ -f $SR_HINTS/$itemname.uidgid ] || return 1
  unset UIDGIDNUMBER
  log_verbose "Hint: $prg: setup uid/gid"
  ####### trap errors!!!
  . $SR_HINTS/$itemname.uidgid
  [ -n "$UIDGIDNUMBER" ] || return 0
  UIDGIDNAME=${UIDGIDNAME:-$prg}
  if ! getent group $UIDGIDNAME | grep -q ^$UIDGIDNAME: 2>/dev/null ; then
    groupadd -g $UIDGIDNUMBER $UIDGIDNAME
  fi
  if ! getent passwd $UIDGIDNAME | grep -q ^$UIDGIDNAME: 2>/dev/null ; then
    useradd \
      -u $UIDGIDNUMBER \
      -c "${UIDGIDCOMMENT:-$UIDGIDNAME}" \
      -d ${UIDGIDDIR:-/dev/null} \
      -s ${UIDGIDSHELL:-/bin/false} \
      -g $UIDGIDNAME \
      $UIDGIDNAME
  fi
  return
}

#-------------------------------------------------------------------------------

function hint_options
# Prints options to standard output, so don't display any messages here!
{
  local itemname="$1"
  local prg=$(basename $itemname)

  if [ -f $SR_HINTS/$itemname.options ]; then
    echo "$(cat $SR_HINTS/$itemname.options)"
  fi
  return
}

#-------------------------------------------------------------------------------

function hint_makeflags
# Prints makeflags to standard output, so don't display any messages here!
# Currently handles only -j1 (no real requirement for anything else).
{
  local itemname="$1"
  local prg=$(basename $itemname)

  if [ -f $SR_HINTS/$itemname.makej1 ]; then
    echo "MAKEFLAGS='-j1'"
  fi
  return
}

#-------------------------------------------------------------------------------

function hint_cleanup
# The prg.cleanup file can contain any required shell commands, for example:
#   * Reinstalling Slackware packages that conflict with prg
#   * Unsetting any environment variables set in prg's /etc/profile.d script
#   * Removing specific files and directories that removepkg doesn't remove
#   * Running depmod to remove references to removed kernel modules
# Returns 1 if no hint found.
{
  local itemname="$1"
  local prg=$(basename $itemname)

  [ -f $SR_HINTS/$itemname.cleanup ] || return 1
  log_verbose "Hint: $prg: running $SR_HINTS/$itemname.cleanup ..."
  ####### trap errors!!!
  . $SR_HINTS/$itemname.cleanup >>$SR_LOGDIR/$prg.log 2>&1
  return 0
}

#-------------------------------------------------------------------------------

function hint_nocleanup
# Return status:
# 0 = hint found, don't do cleanup
# 1 = no hint found, do cleanup
{
  local itemname="$1"
  local prg=$(basename $itemname)

  [ -f $SR_HINTS/$itemname.nocleanup ] || return 1
  log_verbose "Hint: $prg: not doing cleanup"
  return 0
}

#-------------------------------------------------------------------------------

function hint_version
# Returns the global variable $NEWVERSION
# Return status: always 0
{
  local itemname="$1"
  local prg=$(basename $itemname)
  NEWVERSION=''
  if [ -f $SR_HINTS/$itemname.version ]; then
    NEWVERSION=$(cat $SR_HINTS/$itemname.version)
    log_verbose "Hint: $prg: setting VERSION=$NEWVERSION"
  fi
  return 0
}
