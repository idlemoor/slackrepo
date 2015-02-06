#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#
# errorscan_itemlog contains code and concepts from 'checkpkg' v1.15
#   Copyright 2014 Eric Hameleers, Eindhoven, The Netherlands
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#   http://www.slackware.com/~alien/tools/checkpkg
#
#-------------------------------------------------------------------------------
# logfunctions.sh - logging functions for slackrepo
# Progress:
#   log_verbose
#   log_normal
#   log_always
#   log_important
#   log_warning
#   log_error
#   log_done
# Start and finish:
#   log_start
#   log_itemstart
#   log_itemfinish
# Utilities:
#   init_colour
#   changelog
#   errorscan_itemlog
#   format_left_right
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# PROGRESS
#-------------------------------------------------------------------------------

function log_verbose
# Log a message to standard output if OPT_VERBOSE is set.
# Log a message to ITEMLOG if '-a' is specified.
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  [ "$OPT_VERBOSE" = 'y' ] && echo -e "$*"
  [ "$A" = 'y' ] && echo -e "$*" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_normal
# Log a message to standard output unless OPT_QUIET is set.
# Log a message to ITEMLOG if '-a' is specified.
# If the message ends with "... " (note the space), no newline is written.
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  nonewline=''
  eval lastarg=\"\${$#}\"
  [ "${lastarg: -4:4}" = '... ' ] && { nonewline='-n'; NEEDNEWLINE='y'; }
  [ "$OPT_QUIET" != 'y' ] && echo -e $nonewline "$*"
  [ "$A" = 'y' ] && echo -e $nonewline "$*" >> "$ITEMLOG"
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
  echo -e "$*"
  [ "$A" = 'y' ] && echo -e "$*" >> "$ITEMLOG"
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
  echo -e "${tputwhite}$*${tputnormal}"
  [ "$A" = 'y' ] && echo -e "$*" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_warning
# Log a message to standard output in yellow highlight.
# Log a message to ITEMLOG if '-a' is specified.
# Message is prefixed with 'WARNING' (unless '-n' is specified).
# Message is remembered in the array WARNINGLIST (unless '-n' is specified).
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
  echo -e "${tputyellow}${W}$*${tputnormal}"
  [ "$A" = 'y' ] && echo -e "${W}$*" >> "$ITEMLOG"
  [ -n "$W" ] && WARNINGLIST+=( "$*" )
  return 0
}

#-------------------------------------------------------------------------------

function log_error
# Log a message to standard output in red highlight.
# Log a message to ITEMLOG if '-a' is specified.
# Message is prefixed with 'ERROR' (unless '-n' is specified).
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
  echo -e "${tputred}${E}$*${tputnormal}"
  [ "$A" = 'y' ] && echo -e "${E}$*" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_done
# Log the message "done" to standard output.
# Log the message "done" to ITEMLOG if '-a' is specified.
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  echo "done."
  [ "$A" = 'y' ] && echo "done." >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------
# START AND FINISH
# note that these functions set various globals etc
#-------------------------------------------------------------------------------

function log_start
# Log the start of a top level item on standard output.
# $* = message
# Return status: always 0
{
  msg="${*}                                                                        "
  line="==============================================================================="
  echo ""
  echo "$line"
  echo "${msg:0:70} $(date +%T)"
  echo "$line"
  echo ""
  return 0
}

#-------------------------------------------------------------------------------

function log_itemstart
# Log the start of an item on standard output.
# This is where we start logging to ITEMLOG, which is set here, using $itemid set by our caller.
# (At any time only one ITEMLOG can be active.)
# If the optional message is not specified, don't print the log - just setup the itemlog.
# $1 = itemid
# $2... = message (optional)
# Return status: always 0
{
  local itemid="$1"; shift
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  [ "$itemid" != "$ITEMID" ] && ITEMTOTAL=$(( ITEMTOTAL + 1 ))
  
  if [ -n "$itemid" ]; then
    if [ -n "$1" ]; then
      [ "$OPT_VERY_VERBOSE" = 'y' ] && echo ""
      line="-------------------------------------------------------------------------------"
      if [ ${#1} -ge ${#line} ]; then
        echo "${tputwhite}$*${tputnormal}"
      else
        pad=$(( ${#line} - ${#1} - 10 ))
        echo "${tputwhite}$*${tputnormal} ${line:0:$pad} $(date +%T)"
      fi
    fi
    ITEMLOGDIR="$SR_LOGDIR"/"$itemdir"
    mkdir -p "$ITEMLOGDIR"
    ITEMLOG="$ITEMLOGDIR"/"$itemprgnam".log
    if [ -f "$ITEMLOG" ]; then
      oldlog="${ITEMLOG%.log}.1.log"
      mv "$ITEMLOG" "$oldlog"
      gzip -f "$oldlog" &
      rm -f config.log 2>/dev/null
    fi
    echo "$* $(date '+%F %T')"  > "$ITEMLOG"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function log_itemfinish
# Log the finish of an item to standard output, and to ITEMLOG
# $1 = itemid
# $2 = result ('ok', 'skipped', 'failed', or 'aborted')
# $3 = message (optional)
# Return status: always 0
{
  local itemid="$1"
  local result="${2^^}"
  local message="$1"
  [ "$result" != 'OK' ] && message="$message $result"
  [ -n "$3" ] && message="$message $3"
  case "$result" in
    'OK')
      echo -e "${tputgreen}:-) $message (-:${tputnormal}"
      echo -e ":-) $message (-:" >> "$ITEMLOG"
      ;;
    'SKIPPED')
      echo -e "${tputyellow}:-/ $message /-:${tputnormal}"
      echo -e ":-/ $message /-:" >> "$ITEMLOG"
      ;;
    'FAILED' | 'ABORTED')
      echo -e "${tputred}:-( $message )-:${tputnormal}"
      echo -e ":-( $message )-:" >> "$ITEMLOG"
      ;;
  esac
  eval "${result}LIST+=( ${itemid} )"
  db_set_buildresults "$itemid" "$2"
  return 0
}

#-------------------------------------------------------------------------------
# UTILITIES
#-------------------------------------------------------------------------------

function init_colour
# Set up console logging colours
# Return status:
# 0 = imax
# 1 = 405 lines
{
  tputbold=''
  tputred=''
  tputgreen=''
  tputyellow=''
  tputwhite=''
  tputnormal=''
  DOCOLOUR='n'
  [ "$OPT_COLOR" = 'always'       ] && DOCOLOUR='y'
  [ "$OPT_COLOR" = 'auto' -a -t 1 ] && DOCOLOUR='y'
  [ "$DOCOLOUR" = 'n' ] && return 1
  tputbold="$(tput bold)"
  [ $? != 0 ] && { DOCOLOUR='n'; return 1; }
  tputred="$tputbold$(tput setaf 1)"
  [ $? != 0 ] && { DOCOLOUR='n'; return 1; }
  tputgreen="$tputbold$(tput setaf 2)"
  [ $? != 0 ] && { DOCOLOUR='n'; return 1; }
  tputyellow="$tputbold$(tput setaf 3)"
  [ $? != 0 ] && { DOCOLOUR='n'; return 1; }
  tputwhite="$tputbold$(tput setaf 7)"
  [ $? != 0 ] && { DOCOLOUR='n'; return 1; }
  tputnormal="$(tput sgr0)"
  [ $? != 0 ] && { DOCOLOUR='n'; return 1; }
  return 0
}

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
