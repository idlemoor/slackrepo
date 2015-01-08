#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#
# Contains code and concepts from 'checkpkg' v1.15
#   Copyright 2014 Eric Hameleers, Eindhoven, The Netherlands
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#   http://www.slackware.com/~alien/tools/checkpkg
#
#-------------------------------------------------------------------------------
# logfunctions.sh - logging functions for slackrepo
#   changelog
#   log_start
#   log_itemstart
#   log_verbose
#   log_normal
#   log_always
#   log_important
#   log_success
#   log_warning
#   log_error
#   errorscan_itemlog
#   format_left_right
#-------------------------------------------------------------------------------

function changelog
# Append an entry to the main changelog and to the item's changelog
# $1    = itemid
# $2    = operation (e.g. "Updated for git 1a2b3c4")
# $3    = extrastuff (e.g. git commit message)
# $4... = package paths
# Return status: always 0
{
  itemid="$1"
  operation="$2"
  extrastuff="$3"
  shift 3

  if [ "$OPT_DRY_RUN" != 'y' ]; then
    echo "+--------------------------+"  > "$ITEMLOGDIR"/ChangeLog.new
    echo "$(LC_ALL=C date -u)"          >> "$ITEMLOGDIR"/ChangeLog.new
    if [ -n "$extrastuff" ]; then
      details="${operation}. LINEFEED ${extrastuff} NEWLINE"
    else
      details="${operation}. NEWLINE"
    fi
    while [ $# != 0 ]; do
      pkgbase=$(basename "$1")
      shift
      echo "${itemid}/${pkgbase}: ${operation}."   >> "$ITEMLOGDIR"/ChangeLog.new
      [ -n "$extrastuff" ] && echo "  $extrastuff" >> "$ITEMLOGDIR"/ChangeLog.new
      echo "${itemid}/${pkgbase}: ${details}" >> "$CHANGELOG"
    done
    if [ -f "$ITEMLOGDIR"/ChangeLog ]; then
      echo "" | cat - "$ITEMLOGDIR"/ChangeLog >> "$ITEMLOGDIR"/ChangeLog.new
    fi
    mv "$ITEMLOGDIR"/ChangeLog.new "$ITEMLOGDIR"/ChangeLog
  fi
  return 0
}

#-------------------------------------------------------------------------------

function log_start
# Log the start of a top level item on standard output.
# $* = message
# Return status: always 0
{
  msg="${*}                                                                      "
  line="==============================================================================="
  echo ""
  echo "$line"
  echo "! ${msg:0:66} $(date +%T) !"
  echo "$line"
  echo ""
  return 0
}

#-------------------------------------------------------------------------------

function log_itemstart
# Log the start of an item on standard output.
# This is where we start logging to ITEMLOG, which is set here, using $itemid set by our caller.
# (At any time only one ITEMLOG can be active.)
# $* = message
# Return status: always 0
{
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  [ "$itemid" != "$ITEMID" ] && ITEMTOTAL=$(( ITEMTOTAL + 1 ))

  [ "$OPT_VERY_VERBOSE" = 'y' ] && echo ""
  line="-------------------------------------------------------------------------------"
  [ "$DOCOLOUR" = 'y' ] && { tput bold; tput setaf 7; }
  if [ ${#1} -ge ${#line} ]; then
    echo "$*"
  else
    pad=$(( ${#line} - ${#1} - 1 ))
    echo "$* ${line:0:$pad}"
  fi
  [ "$DOCOLOUR" = 'y' ] && { tput sgr0; }
  if [ -n "$itemid" ]; then
    ITEMLOGDIR="$SR_LOGDIR"/"$itemdir"
    mkdir -p "$ITEMLOGDIR"
    ITEMLOG="$ITEMLOGDIR"/"$itemprgnam".log
    echo "$* $(date '+%F %T')"  > "$ITEMLOG"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function log_verbose
# Log a message to standard output if OPT_VERBOSE is set.
# Log a message to ITEMLOG if '-a' is specified.
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  [ "$OPT_VERBOSE" = 'y' ] && echo -e "$@"
  [ "$A" = 'y' ] && echo -e "$@" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_normal
# Log a message to standard output unless OPT_QUIET is set.
# Log a message to ITEMLOG if '-a' is specified.
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  [ "$OPT_QUIET" != 'y' ] && echo -e "$@"
  [ "$A" = 'y' ] && echo -e "$@" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_always
# Log a message to standard output.
# Log a message to ITEMLOG if '-a' is specified.
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  echo -e "$@"
  [ "$A" = 'y' ] && echo -e "$@" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_important
# Log a message to standard output in white highlight.
# Log a message to ITEMLOG if '-a' is specified.
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  [ "$DOCOLOUR" = 'y' ] && { tput bold; tput setaf 7; }
  echo -e "$@"
  [ "$DOCOLOUR" = 'y' ] && { tput sgr0; }
  [ "$A" = 'y' ] && echo -e "$@" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_success
# Log a message to standard output in green highlight.
# Log a message to ITEMLOG if '-a' is specified.
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  [ "$DOCOLOUR" = 'y' ] && { tput bold; tput setaf 2; }
  echo -e "$@"
  [ "$DOCOLOUR" = 'y' ] && { tput sgr0; }
  [ "$A" = 'y' ] && echo -e "$@" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_warning
# Log a message to standard output in yellow highlight.
# Log a message to ITEMLOG if '-a' is specified.
# Message is automatically prefixed with 'WARNING' (unless '-n' is specified).
# $* = message
# Return status: always 0
{
  W='WARNING: '
  A='n'
  while [ $# != 0 ]; do
    case "$1" in
    '-n') W='';  shift; continue ;;
    '-a') A='y'; shift; continue ;;
    *)    break ;;
    esac
  done
  [ "$DOCOLOUR" = 'y' ] && { tput bold; tput setaf 3; }
  echo -e "${W}$*"
  [ "$DOCOLOUR" = 'y' ] && { tput sgr0; }
  [ "$A" = 'y' ] && echo -e "${W}$*" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_error
# Log a message to standard output in red highlight.
# Log a message to ITEMLOG if '-a' is specified.
# Message is automatically prefixed with 'ERROR' (unless '-n' is specified).
# $* = message
# Return status: always 0
{
  E='ERROR: '
  A='n'
  while [ $# != 0 ]; do
    case "$1" in
    '-n') E='';  shift; continue ;;
    '-a') A='y'; shift; continue ;;
    *)    break ;;
    esac
  done
  [ "$DOCOLOUR" = 'y' ] && { tput bold; tput setaf 1; }
  echo -e "${E}$*"
  [ "$DOCOLOUR" = 'y' ] && { tput sgr0; }
  [ "$A" = 'y' ] && echo -e "${E}$*" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function errorscan_itemlog
# Print apparent errors in $ITEMLOG to standard output
# No parameters
# Return status: always 0
{
  # This is Alien Bob being awesome, as usual :D
  grep -E \
    "FAIL| hunk ignored|[^A-Z]Error |[^A-Z]ERROR |Error:|error:|errors occurred|ved symbol|ndefined reference to|ost recent call first|ot found|cannot operate on dangling|ot supported|annot find -l|make: \*\*\* No |kipping patch|t seem to find a patch|^Usage: |option requires |o such file or dir|SlackBuild: line" \
    "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function format_left_right
# Format a two-part message, with the first part right justified, and the second
# part left justified.  The formatted string is printed on standard output.
# $1 = first part
# $2 = second part (optional)
# Return status: always 0
{
  if [ -z "$2" ]; then
    # Don't muck about, just print $1:
    echo "$1"
    return 0
  fi

  lmsg="${1}"
  rmsg="${2}"
  pad="                                                                                "
  # Line width is hardcoded here:
  width=79
  # Minimum width of left part:
  lmin=1
  # Minimum amount of padding:
  pmin=1

  rlen=${#rmsg}
  llen=${#lmsg}
  plen=$pmin

  # If rlen is too long, reduce it:
  [ "$rlen" -gt $(( width - lmin - pmin )) ] && rlen=$(( width - lmin - pmin ))
  # If llen is too long, reduce it:
  [ "$llen" -gt $(( width - pmin - rlen )) ] && llen=$(( width - pmin - rlen ))
  # If llen is too short, increase the padding:
  [ $(( llen + plen + rlen )) -lt "$width" ] && plen=$(( width - llen - rlen ))
  # Ok, print it:
  echo "${lmsg:0:llen}${pad:0:plen}${rmsg:0:rlen}"
  return 0
}
