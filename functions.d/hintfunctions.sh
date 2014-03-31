#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# hintfunctions.sh - functions for slackrepo hints:
#   set_hints
#   hint_skipme
#   do_hint_uidgid
#   do_hint_version
#-------------------------------------------------------------------------------

function set_hints
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  gothints=''

  FLAGHINTS="skipme md5ignore makej1 no_uninstall"
  # These are Boolean hints.
  # Query them like this: '[ "${HINT_xxx[$itempath]}" = 'y' ]'
  for hint in $FLAGHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itempath]='y'
    else
      eval HINT_$hint[$itempath]=''
    fi
  done

  FILEHINTS="cleanup uidgid answers"
  # These are hints where the file contents will be executed or piped.
  # Query them like this: '[ -n "${HINT_xxx[$itempath]}" ]'
  for hint in $FILEHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itempath]="$SR_HINTS/$itempath.$hint"
    else
      eval HINT_$hint[$itempath]=''
    fi
  done

  VARHINTS="options optdeps readmedeps version"
  # These are hints where the file contents will be used by slackrepo itself.
  # '%NONE%' indicates the file doesn't exist (vs. readmedeps exists and is empty).
  # Query them like this: '[ "${HINT_xxx[$itempath]}" != '%NONE%' ]'
  for hint in $VARHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itempath]=\"$(cat $SR_HINTS/$itempath.$hint)\"
    else
      eval HINT_$hint[$itempath]='%NONE%'
    fi
  done

  # Log hints, unless skipme is set (in which case we are about to bail out noisily).
  if [ "${HINT_skipme[$itempath]}" != 'y' -a -n "$gothints" ]; then
    log_normal "Hints for ${itempath}:"
    log_normal " $gothints"
  fi

  return 0

}

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

function do_hint_uidgid
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

  [ -n "${HINT_uidgid[$itempath]}" ] || return 1

  unset UIDGIDNUMBER
  log_verbose "Hint: $prgnam: setup uid/gid"
  . ${HINT_uidgid[$itempath]}
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

function do_hint_version
# Is there a version hint for this item?
# $1 = itempath
# Returns these global variables:
# $NEWVERSION (empty if no hint or no actual version change: see below)
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  NEWVERSION=''
  if [ -n "${HINT_version[$itempath]}" -a "${HINT_version[$itempath]}" != '%NONE%' ]; then
    NEWVERSION=${HINT_version[$itempath]}
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
