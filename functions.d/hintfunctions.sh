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
# $1 = itemid
# Return status:
# 0 = skipped
# 1 = not skipped
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"

  # called before parse_hints runs, so check the file directly:
  SKIPFILE="$SR_HINTS"/"$itemdir"/"$itemprgnam".skipme
  if [ ! -f "$SKIPFILE" ]; then
    return 1
  fi
  log_warning -n "SKIPPED $itemid due to hint"
  cat "$SKIPFILE"
  SKIPPEDLIST+=( "$itemid" )
  return 0
}

#-------------------------------------------------------------------------------

function do_hint_uidgid
# If there is a uidgid hint for this item, set up the uidgid.
# The prgnam.uidgid file should contain
# *either* an assignment of UIDGIDNUMBER and (optionally) UIDGIDNAME,
#          UIDGIDCOMMENT, UIDGIDDIR, UIDGIDSHELL
# *or* a script to make the UID and/or the GID, if it's not straightforward.
# $1 = itemid
# Return status:
# 0 = There is a uidgid hint, and an attempt was made to process it
# 1 = There is no uidgid hint
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"

  [ -n "${HINT_uidgid[$itemid]}" ] || return 1

  unset UIDGIDNUMBER
  log_verbose "Hint: $itemprgnam: setup uid/gid"
  . "${HINT_uidgid[$itemid]}"
  [ -n "$UIDGIDNUMBER" ] || return 0
  UIDGIDNAME="${UIDGIDNAME:-$itemprgnam}"
  if ! getent group "$UIDGIDNAME" | grep -q "^${UIDGIDNAME}:" 2>/dev/null ; then
    groupadd -g "$UIDGIDNUMBER" "$UIDGIDNAME"
  fi
  if ! getent passwd "$UIDGIDNAME" | grep -q "^${UIDGIDNAME}:" 2>/dev/null ; then
    useradd \
      -u "$UIDGIDNUMBER" \
      -c "${UIDGIDCOMMENT:-$UIDGIDNAME}" \
      -d "${UIDGIDDIR:-/dev/null}" \
      -s "${UIDGIDSHELL:-/bin/false}" \
      -g "$UIDGIDNAME" \
      "$UIDGIDNAME"
  fi
  return 0
}
