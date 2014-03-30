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

function set_hints
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  gothints=''

  FLAGHINTS="skipme md5ignore makej1 no_uninstall cleanup uidgid answers"
  # Yeah, uidgid, cleanup and answers are not flags, but it's not useful to have
  # their contents in variables.
  for hint in $FLAGHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itemname]='y'
    else
      eval HINT_$hint[$itemname]=''
    fi
  done

  VARHINTS="options optdeps readmedeps version"
  for hint in $VARHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itemname]="$(cat $SR_HINTS/$itempath.$hint)"
    else
      eval HINT_$hint[$itemname]=''
    fi
  done

  if [ -n "$gothints" ]; then
    log_normal "Hints for $itemname:$gothints"
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
