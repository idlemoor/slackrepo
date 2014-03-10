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
#   hint_no_uninstall
#   hint_version
#-------------------------------------------------------------------------------

function hint_skipme
# Is there a skipme hint for this item?
# $1 = itemname
# Return status:
# 0 = skip
# 1 = do not skip
{
  local itemname="$1"
  local prg=${itemname##*/}

  if [ ! -f $SR_HINTS/$itemname.skipme ]; then
    return 1
  fi
  log_warning -n "SKIPPED $itemname due to hint"
  cat $SR_HINTS/$itemname.skipme
  return 0
}

#-------------------------------------------------------------------------------

function hint_md5ignore
# Is there an md5ignore hint for this item?
# $1 = itemname
# Return status:
# 0 = ignore md5sum
# 1 = do not ignore md5sum
{
  local itemname="$1"
  local prg=${itemname##*/}

  if [ ! -f $SR_HINTS/$itemname.md5ignore ]; then
    return 1
  fi
  log_verbose "Hint: $prg: ignoring md5sums"
  return 0
}

#-------------------------------------------------------------------------------

function hint_uidgid
# If there is a uidgid hint for this item, set up the uidgid.
# The prg.uidgid file should contain
# *either* an assignment of UIDGIDNUMBER and (optionally) UIDGIDNAME,
#          UIDGIDCOMMENT, UIDGIDDIR, UIDGIDSHELL
# *or* a script to make the UID and/or the GID, if it's not straightforward.
# $1 = itemname
# Return status:
# 0 = There is a uidgid hint, and an attempt was made to process it
# 1 = There is no uidgid hint
{
  local itemname="$1"
  local prg=${itemname##*/}

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
  return 0
}

#-------------------------------------------------------------------------------

function hint_options
# Prints options to standard output, if there is an options hint
# $1 = itemname
# Return status: always 0
{
  local itemname="$1"
  local prg=${itemname##*/}

  if [ -f $SR_HINTS/$itemname.options ]; then
    echo "$(cat $SR_HINTS/$itemname.options)"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function hint_makeflags
# Prints makeflags to standard output according to hints.  Currently handles
# only makej1 hint file and -j1 flag (no requirement for anything else atm).
# $1 = itemname
# Return status: always 0
{
  local itemname="$1"
  local prg=${itemname##*/}

  if [ -f $SR_HINTS/$itemname.makej1 ]; then
    echo "MAKEFLAGS='-j1'"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function hint_cleanup
# Execute any cleanup hint file.
# The prg.cleanup file can contain any required shell commands, for example:
#   * Reinstalling Slackware packages that conflict with prg
#   * Unsetting any environment variables set in prg's /etc/profile.d script
#   * Removing specific files and directories that removepkg doesn't remove
#   * Running depmod to remove references to removed kernel modules
# $1 = itemname
# Return status:
# 0 = cleanup hint found and executed
# 1 = no hint found
{
  local itemname="$1"
  local prg=${itemname##*/}

  [ -f $SR_HINTS/$itemname.cleanup ] || return 1
  log_verbose "Hint: $prg: running $SR_HINTS/$itemname.cleanup ..."
  . $SR_HINTS/$itemname.cleanup >>$SR_LOGDIR/$prg.log 2>&1
  ###### handle errors
  return 0
}

#-------------------------------------------------------------------------------

function hint_no_uninstall
# Is there a no_uninstall hint for this item?
# $1 = itemname
# Return status:
# 0 = hint found, don't uninstall
# 1 = no hint found, do uninstall
{
  local itemname="$1"
  local prg=${itemname##*/}

  [ -f $SR_HINTS/$itemname.no_uninstall ] || return 1
  log_verbose "Hint: $prg: not uninstalling"
  return 0
}

#-------------------------------------------------------------------------------

function hint_version
# Is there a version hint for this item?
# $1 = itemname
# Returns these global variables:
# $NEWVERSION (empty if no hint or no actual version change: see below)
# Return status: always 0
{
  local itemname="$1"
  local prg=${itemname##*/}
  NEWVERSION=''
  if [ -f $SR_HINTS/$itemname.version ]; then
    NEWVERSION=$(cat $SR_HINTS/$itemname.version)
    OLDVERSION="$VERSION"  ########### this may not be right :-(
    if [ "$NEWVERSION" = "$OLDVERSION" ]; then
      log_verbose "Hint: $prg.version: current version is already $OLDVERSION"
      NEWVERSION=''
    else
      log_verbose "Hint: $prg: setting VERSION=$NEWVERSION (was $OLDVERSION)"
    fi
  fi
  return 0
}
