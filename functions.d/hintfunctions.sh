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
# $1 = itempath
# Return status:
# 0 = skip
# 1 = do not skip
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ ! -f $SR_HINTS/$itempath.skipme ]; then
    return 1
  fi
  log_warning -n "SKIPPED $itempath due to hint"
  cat $SR_HINTS/$itempath.skipme
  return 0
}

#-------------------------------------------------------------------------------

function hint_md5ignore
# Is there an md5ignore hint for this item?
# $1 = itempath
# Return status:
# 0 = ignore md5sum
# 1 = do not ignore md5sum
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ ! -f $SR_HINTS/$itempath.md5ignore ]; then
    return 1
  fi
  log_verbose "Hint: $prgnam: ignoring md5sums"
  return 0
}

#-------------------------------------------------------------------------------

function hint_uidgid
# If there is a uidgid hint for this item, set up the uidgid.
# The prgnam.uidgid file should contain
# *either* an assignment of UIDGIDNUMBER and (optionally) UIDGIDNAME,
#          UIDGIDCOMMENT, UIDGIDDIR, UIDGIDSHELL
# *or* a script to make the UID and/or the GID, if it's not straightforward.
# $1 = itempath
# Return status:
# 0 = There is a uidgid hint, and an attempt was made to process it
# 1 = There is no uidgid hint
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  [ -f $SR_HINTS/$itempath.uidgid ] || return 1

  unset UIDGIDNUMBER
  log_verbose "Hint: $prgnam: setup uid/gid"
  ####### trap errors!!!
  . $SR_HINTS/$itempath.uidgid
  [ -n "$UIDGIDNUMBER" ] || return 0
  UIDGIDNAME=${UIDGIDNAME:-$prgnam}
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
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ -f $SR_HINTS/$itempath.options ]; then
    echo "$(cat $SR_HINTS/$itempath.options)"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function hint_makeflags
# Prints makeflags to standard output according to hints.  Currently handles
# only makej1 hint file and -j1 flag (no requirement for anything else atm).
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ -f $SR_HINTS/$itempath.makej1 ]; then
    echo "MAKEFLAGS='-j1'"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function hint_cleanup
# Execute any cleanup hint file.
# The prgnam.cleanup file can contain any required shell commands, for example:
#   * Reinstalling Slackware packages that conflict with prgnam
#   * Unsetting any environment variables set in prgnam's /etc/profile.d script
#   * Removing specific files and directories that removepkg doesn't remove
#   * Running depmod to remove references to removed kernel modules
# $1 = itempath
# Return status:
# 0 = cleanup hint found and executed
# 1 = no hint found
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  [ -f $SR_HINTS/$itempath.cleanup ] || return 1
  log_verbose "Hint: $prgnam: running $SR_HINTS/$itempath.cleanup ..."
  . $SR_HINTS/$itempath.cleanup >>$SR_LOGDIR/$itempath.log 2>&1
  ###### handle errors
  return 0
}

#-------------------------------------------------------------------------------

function hint_no_uninstall
# Is there a no_uninstall hint for this item?
# $1 = itempath
# Return status:
# 0 = hint found, don't uninstall
# 1 = no hint found, do uninstall
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  [ -f $SR_HINTS/$itempath.no_uninstall ] || return 1
  log_verbose "Hint: $prgnam: not uninstalling"
  return 0
}

#-------------------------------------------------------------------------------

function hint_version
# Is there a version hint for this item?
# $1 = itempath
# Returns these global variables:
# $NEWVERSION (empty if no hint or no actual version change: see below)
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  NEWVERSION=''
  if [ -f $SR_HINTS/$itempath.version ]; then
    NEWVERSION=$(cat $SR_HINTS/$itempath.version)
    if [ -f $SR_PKGREPO/$itempath/$prgnam-*.t?z ]; then
      OLDVERSION=$(echo $SR_PKGREPO/$itempath/$prgnam-*.t?z | rev | cut -f3 -d- | rev)
    else
      OLDVERSION="${INFOVERSION[$itempath]}"
    fi
    if [ "$NEWVERSION" = "$OLDVERSION" ]; then
      log_verbose "Hint: $prgnam.version: current version is already $OLDVERSION"
      NEWVERSION=''
    else
      log_verbose "Hint: $prgnam: setting VERSION=$NEWVERSION (was $OLDVERSION)"
    fi
  fi
  return 0
}
