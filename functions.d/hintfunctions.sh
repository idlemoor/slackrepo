#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# hintfunctions.sh - functions for slackrepo hints:
#   do_hint_skipme
#   do_hint_uidgid
# If you're looking for parse_hints, it's in parsefunctions.sh ;-)
#-------------------------------------------------------------------------------

function do_hint_skipme
# Is there a skipme hint for this item?
# $1 = itempath
# Return status:
# 0 = skipped
# 1 = not skipped
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  # called before parse_hints runs, so check the file directly:
  if [ ! -f $SR_HINTS/$itempath.skipme ]; then
    return 1
  fi
  log_warning -n "SKIPPED $itempath due to hint"
  cat $SR_HINTS/$itempath.skipme
  SKIPPEDLIST="$SKIPPEDLIST $itempath"
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
