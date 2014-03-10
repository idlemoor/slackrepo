#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# procfunctions.sh - processing functions for slackrepo
#   process_item
#   process_remove
#-------------------------------------------------------------------------------
# Note that we set the global variables $ITEMNAME and $PRG (upper case) so that
# other functions called recursively (which get $itemname and $prg as arguments)
# can test whether they are dealing with the top level item.
#-------------------------------------------------------------------------------

function process_item
# Either build or remove an item
# $1 = itemname
# Sets global variable ITEMNAME so the top level item can be identified
# Return status: always 0 -- if an error occurs, exit with status 4
{
  local ITEMNAME="$1"
  local PRG=$(basename $ITEMNAME)

  echo ""
  log_start "$ITEMNAME"

  case "$PROCMODE" in
  'add' | 'rebuild' | 'test')
    build_with_deps $ITEMNAME
    ;;
  'update')
    if [ -d $SR_GITREPO/$ITEMNAME/ ]; then
      build_with_deps $ITEMNAME
    else
      process_remove $ITEMNAME
    fi
    ;;
  'remove')
    process_remove $ITEMNAME
    ;;
  *)
    log_error "$(basename $0): Unrecognised PROCMODE = $PROCMODE" ; exit 4 ;;
  esac

  return
}

#-------------------------------------------------------------------------------

function process_remove
# Remove an item from the package repository and the source repository
# $1 = itemname
# Return status:
# 0 = item removed
# 1 = item was skipped
{
  local ITEMNAME="$1"
  local PRG=$(basename $ITEMNAME)

  # Don't remove if this is just an update and it's marked to be skipped
  if [ "$PROCMODE" = 'update' ]; then
    if hint_skipme $me; then
      SKIPPEDLIST="$SKIPPEDLIST $me"
      return 1
    fi
  fi

  if [ "$UPDATEDRYRUN" = 'y' ]; then
    log_important "$ITEMNAME would be removed"
    echo "$ITEMNAME would be removed" >> $SR_UPDATEFILE
  else
    log_important "Removing $ITEMNAME"
    rm -rf $SR_PKGREPO/$ITEMNAME/
    rm -rf $SR_SRCREPO/$ITEMNAME/ $SR_SRCREPO/${ITEMNAME}_BAD/
    echo "$ITEMNAME: Removed. NEWLINE" >>$SR_CHANGELOG
  fi
  return
}
