#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#
# errorscan_itemlog contains code and concepts from 'checkpkg' 1.32
#   Copyright 2014-2017 Eric Hameleers, Eindhoven, The Netherlands
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#   http://www.slackware.com/~alien/tools/checkpkg
#
#-------------------------------------------------------------------------------
# logfunctions.sh - logging functions for slackrepo
# Progress:
#   log_normal
#   log_verbose
#   log_info
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
# Monitoring:
#   resource_monitor
#   resource_report
#-------------------------------------------------------------------------------

# Globals:
PADBLANK="                                                                                "
PADLINE="--------------------------------------------------------------------------------"
DBLLINE="================================================================================"
LINEWIDTH=80
LINEUSABLE=$(( LINEWIDTH - 9 ))    # 9 is the length of <space>HH:MM:SS

#-------------------------------------------------------------------------------
# PROGRESS MESSAGES
#-------------------------------------------------------------------------------

function log_normal
# Log a message to standard output, with an optional second message to the right.
# Typically the second message will be the current time, or a time estimate.
# Log a message to ITEMLOG if '-a' is specified.
# If the message ends with "... " (note the space), no newline is written.
# Usage: log_normal [-a] messagestring [leftmessagestring]
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  if [ -z "$2" ]; then
    nonewline=''
    [ "${1: -4:4}" = '... ' ] && nonewline='-n'
    echo -e $nonewline "${NL}${1}"
    [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}" >> "$ITEMLOG"
    if [ "$nonewline" = '-n' ]; then
      NL='\n'
    else
      NL=''
    fi
  else
    if [ $(( ${#1} + ${#2} )) -lt "$LINEWIDTH" ]; then
      read -r llen plen rlen < <(format_left_right "$1" "$2")
      echo -e "${NL}${1:0:$llen}${PADBLANK:0:$plen}${2:0:$rlen}"
      [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${NL}${1}${PADBLANK:0:$plen}${2}" >> "$ITEMLOG"
    else
      echo -e "${NL}${1}\n${PADBLANK:0:$(( LINEWIDTH - ${#2} ))}${2}"
      [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${NL}${1}\n${PADBLANK:0:$(( LINEWIDTH - ${#2} ))}${2}" >> "$ITEMLOG"
    fi
    NL=''
  fi
  return 0
}

#-------------------------------------------------------------------------------

function log_verbose
# Log an informational message to standard output if OPT_VERBOSE is set.
# Log a message to ITEMLOG if '-a' is specified.
# Usage: log_verbose [-a] messagestring
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  [ "$OPT_VERBOSE" = 'y' ] && echo -e "${colour_info}${1}${colour_normal}"
  [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}" >> "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function log_info
# Log an informational message to standard output.
# If '-t' is specified, truncate it at 3000 chars unless OPT_VERBOSE is set.
# Log a message to ITEMLOG if '-a' is specified.
# Usage: log_info [-a] messagestring
# Return status: always 0
{
  T='n'
  A='n'
  while [ $# != 0 ]; do
    case "$1" in
    '-t') T='y';  shift; continue ;;
    '-a') A='y'; shift; continue ;;
    *)    break ;;
    esac
  done
  infostuff="$1"
  [ -z "$infostuff" ] && return 0
  [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}" >> "$ITEMLOG"
  if [ "$OPT_VERBOSE" != 'y' ]; then
    [ "$T" = 'y' ] && [ ${#infostuff} -gt 3000 ] && infostuff="${infostuff:0:3000}\n[...]"
  fi
  echo -e "${NL}${colour_info}${infostuff}${colour_normal}"
  NL=''
  return 0
}

#-------------------------------------------------------------------------------

function log_important
# Log a message to standard output in white highlight, with an optional second
# message to the right.
# Typically the second message will be the current time, or a time estimate.
# Log a message to ITEMLOG if '-a' is specified.
# Usage: log_important [-a] messagestring [leftmessagestring]
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  if [ -z "${2}" ]; then
    echo -e "${NL}${colour_important}${1}${colour_normal}"
    [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}" >> "$ITEMLOG"
  else
    if [ $(( ${#1} + ${#2} )) -lt "$LINEWIDTH" ]; then
      read -r llen plen rlen < <(format_left_right "$1" "$2")
      echo -e "${NL}${colour_important}${1:0:$llen}${colour_normal}${PADBLANK:0:$plen}${2:0:$rlen}"
      [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}${PADBLANK:0:$plen}${2}" >> "$ITEMLOG"
    else
      echo -e "${NL}${colour_important}${1}${colour_normal}\n${PADBLANK:0:$(( LINEWIDTH - ${#2} ))}${2}"
      [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}\n${PADBLANK:0:$(( LINEWIDTH - ${#2} ))}${2}" >> "$ITEMLOG"
    fi
  fi
  NL=''
  return 0
}

#-------------------------------------------------------------------------------

function log_warning
# Log a message to standard output in magenta highlight.
# Log a message to ITEMLOG if '-a' is specified.
# Message is prefixed with 'WARNING' (unless '-n' is specified).
# Message is remembered in the array WARNINGLIST (unless '-n' is specified).
# But!!  If '-s' is specified, and the message matches a regex in
# ${HINT_NOWARNING[$itemid]}, the message is not shown -- it isn't logged
# to standard output, and isn't remembered in WARNINGLIST.
# Usage: log_warning [-a] [-n] [-s] messagestring
# Return status: 0 = ok, 1 = message was suppressed
{
  W='WARNING: '
  A='n'
  S='n'
  while [ $# != 0 ]; do
    case "$1" in
    '-a') A='y'; shift; continue ;;
    '-n') W='';  shift; continue ;;
    '-s') S='y'; shift; continue ;;
    *)    break ;;
    esac
  done
  show='y'
  if [ "$S" = 'y' ] && [ -n "${HINT_NOWARNING[$itemid]:-${OPT_NOWARNING}}" ]; then
    if echo "$1" | grep -q "${HINT_NOWARNING[$itemid]:-${OPT_NOWARNING}}"; then
      show='n'
    fi
  fi
  [ "$show" = 'y' ] && echo -e "${NL}${colour_warning}${W}${1}${colour_normal}"
  [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${W}${1}" >> "$ITEMLOG"
  NL=''
  [ "$show" = 'y' ] && [ -n "$W" ] && WARNINGLIST+=( "${1}" ) && return 0
  return 1
}

#-------------------------------------------------------------------------------

function log_error
# Log a message to standard output in red highlight, with an optional second
# message to the right.
# Typically the second message will be the current time.
# Log a message to ITEMLOG if '-a' is specified.
# Message is prefixed with 'ERROR: ' (unless '-n' is specified).
# Usage: log_error [-a] [-n] messagestring
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
  if [ -z "${2}" ]; then
    echo -e "${NL}${colour_error}${E}${1}${colour_normal}"
    [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${E}${1}" >> "$ITEMLOG"
  else
    if [ $(( ${#1} + ${#2} )) -lt "$LINEWIDTH" ]; then
      read -r llen plen rlen < <(format_left_right "$1" "$2")
      echo -e "${NL}${colour_error}${1:0:$llen}${colour_normal}${PADBLANK:0:$plen}${2:0:$rlen}"
      [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}${PADBLANK:0:$plen}${2}" >> "$ITEMLOG"
    else
      echo -e "${NL}${colour_error}${1}${colour_normal}\n${PADBLANK:0:$(( LINEWIDTH - ${#2} ))}${2}"
      [ "$A" = 'y' ] && [ -n "$ITEMLOG" ] && echo -e "${1}\n${PADBLANK:0:$(( LINEWIDTH - ${#2} ))}${2}" >> "$ITEMLOG"
    fi
  fi
  NL=''
  return 0
}

#-------------------------------------------------------------------------------

function log_done
# Log the message "done." or a similar message to standard output (but not ITEMLOG).
# Usage: log_done [message]
# $1 = optional message to substitute for "done."
# Return status: always 0
{
  [ -n "${NL}" ] && echo "${1:-done.}" && NL=''
  return 0
}

#-------------------------------------------------------------------------------
# START AND FINISH MESSAGES
# note that these functions set various globals etc
#-------------------------------------------------------------------------------

function log_start
# Log the start of a top level item on standard output.
# The current time is shown on the right (possibly truncating the message).
# Usage: log_start messagestring
# Return status: always 0
{
  msg="${1}                                                                         "
  echo "${DBLLINE:0:$LINEWIDTH}"
  echo "${msg:0:$LINEUSABLE} $(date +%T)"
  echo "${DBLLINE:0:$LINEWIDTH}"
  echo ""
  return 0
}

#-------------------------------------------------------------------------------

function log_itemstart
# Log the start of an item on standard output.
# This is where we start logging to ITEMLOG, which is set here, using $itemid set by our caller.
# (At any time only one ITEMLOG can be active.)
# If the optional message is not specified, don't print anything - just setup the itemlog.
# Usage: log_itemstart itemid [messagestring]
# Return status: always 0
{
  local itemid="$1"
  local message="$2"

  if [ -n "$message" ]; then
    # Impose a minimum 5 chars of padding
    if [ $(( ${#message} + 5 )) -gt "$LINEUSABLE" ]; then
      echo -e "${PADLINE:0:$LINEUSABLE} $(date +%T)\n${colour_important}${message}${colour_normal}"
    else
      padlen=$(( LINEUSABLE - ${#message} - 1 ))
      echo "${colour_important}${message}${colour_normal} ${PADLINE:0:$padlen} $(date +%T)"
    fi
  fi
  if [ -n "$itemid" ] && [ -n "${ITEMDIR[$itemid]}" ]; then
    ITEMLOGDIR="$SR_LOGDIR"/"${ITEMDIR[$itemid]}"
    mkdir -p "$ITEMLOGDIR"
    ITEMLOG="$ITEMLOGDIR"/"$CMD".log
    if [ -f "$ITEMLOG" ]; then
      oldlog="${ITEMLOG%.log}.1.log"
      mv "$ITEMLOG" "$oldlog"
      gzip -f "$oldlog" &
      rm -f config.log 2>/dev/null
    fi
    echo "${message} $(date '+%F %T')"  > "$ITEMLOG"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function log_itemfinish
# Log the finish of an item to standard output, and to ITEMLOG
# Usage: log_itemfinish itemid result [messagestring] [additionalmessagestring]
# $1 = itemid
# $2 = result ('ok', 'warning', 'skipped', 'unsupported', 'failed', 'aborted', or 'bad')
# $3 = message (optional)
# $4 = additional message for display on the next line (optional)
# Return status: always 0
{
  local itemid="$1"
  local result="${2^^}"
  local message="$itemid"
  case "$result" in
    'OK') message="$itemid" ;;
    'WARNING') message="$itemid" ;;
    'SKIPPED') message="$itemid SKIPPED" ;;
    'UNSUPPORTED') message="$itemid is UNSUPPORTED" ;;
    'FAILED') message="$itemid FAILED" ;;
    'ABORTED') message="$itemid ABORTED" ;;
    'BAD') message="BAD ARGUMENT '$itemid'" ;;
  esac
  [ -n "$3" ] && message="$message $3"

  addmessage=""
  [ -n "$4" ] && addmessage=$'\n'"$4"
  if [ -z "$ITEMLOG" ]; then
    # I know it's over, and it never really began,
    log_itemstart "$itemid"
    # but in my heart it was so real
  fi
  case "$result" in
    'OK')
      echo -e "${colour_success}:-) $message (-:${addmessage}${colour_normal}\n"
      [ -n "$ITEMLOG" ] && echo -e ":-) $message (-:${addmessage}\n" >> "$ITEMLOG"
      ;;
    'WARNING' | 'SKIPPED' | 'UNSUPPORTED')
      echo -e "${colour_warning}:-/ $message /-:${addmessage}${colour_normal}\n"
      [ -n "$ITEMLOG" ] && echo -e ":-/ $message /-:${addmessage}\n" >> "$ITEMLOG"
      ;;
    'FAILED' | 'ABORTED' | 'BAD')
      echo -e "${colour_error}:-( $message )-:${addmessage}${colour_normal}\n"
      [ -n "$ITEMLOG" ] && echo -e ":-( $message )-:${addmessage}\n" >> "$ITEMLOG"
      ;;
  esac
  # WARNINGLIST is populated by grepping the log, so don't set it here
  [ "$result" != 'WARNING' ] && eval "${result}LIST+=( ${itemid} )"
  if [ "$CMD" = 'build' ] || [ "$CMD" = 'update' ] || [ "$CMD" = 'rebuild' ]; then
    db_set_buildresults "$itemid" "$2"
  fi
  unset ITEMLOG
  return 0
}

#-------------------------------------------------------------------------------
# UTILITY FUNCTIONS
#-------------------------------------------------------------------------------

function init_colour
# Set up console logging colours
# Return status:
# 0 = imax
# 1 = 405 lines
{
  DOCOLOUR='n'
  [ "$OPT_COLOR" = 'always' ] && DOCOLOUR='y'
  [ "$OPT_COLOR" = 'auto' ] && [ -t 1 ] && DOCOLOUR='y'
  if [ "$DOCOLOUR" = 'n' ]; then
    colour_error=""
    colour_warning=""
    colour_success=""
    colour_important=""
    colour_normal=""
    colour_info=""
    colour_ok=""
    colour_build=""
    colour_skip=""
    colour_fail=""
    colour_updated=""
    return 1
  fi
  # we used to use tput, but apparently everything from ls to gcc has abandoned
  # the wisdom of the old ones and just assumes ansi :-/
  csi=$'\x1b['
  colour_error="${csi}1;31m"
  colour_warning="${csi}1;35m"
  colour_success="${csi}1;32m"
  colour_important="${csi}1m"
  colour_normal="${csi}0m"
  colour_info="${csi}22;36m"
  colour_ok="${csi}0m"
  colour_build="${csi}22;32m"
  colour_skip="${csi}22;35m"
  colour_fail="${csi}22;31m"
  colour_updated="${csi}22;36m"
  for c in $(echo "${SLACKREPO_COLORS}" | sed 's/:/ /g'); do
    cname="${c/=*/}"
    cvalue="${c/*=/}"
    eval "colour_${cname}=\"${csi}${cvalue}m\""
  done
  [ -z "$GCC_COLORS" ] && export GCC_COLORS="error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01"
  echo -n "${colour_normal}"
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
  # now updated w.r.t. checkpkg v. 1.32
  grep -E \
    "aborted!|[[:space:]]too[[:space:]]old|FAIL|[[:space:]]hunk[[:space:]]ignored|[^A-Z]Error[[:space:]]|[^A-Z]ERROR[[:space:]]|Error:|error:|errors[[:space:]]occurred|ved[[:space:]]symbol|ndefined[[:space:]]reference[[:space:]]to|ost[[:space:]]recent[[:space:]]call[[:space:]]first|ot[[:space:]]found|annot[[:space:]]find[[:space:]]-l|make:[[:space:]]\*\*\*[[:space:]]No[[:space:]]|kipping[[:space:]]patch|skipping[[:space:]]incompatible[[:space:]]|t[[:space:]]seem[[:space:]]to[[:space:]]find[[:space:]]a[[:space:]]patch|[[:space:]]not[[:space:]]supported|^Usage:[[:space:]]|option[[:space:]]requires[[:space:]]|memory[[:space:]]exhausted|cannot[[:space:]]stat[[:space:]]|SlackBuild:[[:space:]]line|No[[:space:]]such[[:space:]]file|[Uu]nrecognised[[:space:]]xattr|[Uu]nknown[[:space:]]option" \
    "$ITEMLOG"
  return 0
}

#-------------------------------------------------------------------------------

function format_left_right
# Calculate, and print on standard output, the string lengths necessary to
# format $1 on the left, padding in the middle, and $2 on the right.
# $1 = left hand message
# $2 = right hand message
# Return status: always 0
{
  local lmsg="${1}"
  local rmsg="${2}"
  local lmin=1  # minimum width of left part
  local pmin=1  # minimum amount of padding
  local llen=${#lmsg}
  local plen=$pmin
  local rlen=${#rmsg}
  # If rlen is too long, reduce it:
  [ "$rlen" -gt $(( LINEWIDTH - lmin - pmin )) ] && rlen=$(( LINEWIDTH - lmin - pmin ))
  # If llen is too long, reduce it:
  [ "$llen" -gt $(( LINEWIDTH - pmin - rlen )) ] && llen=$(( LINEWIDTH - pmin - rlen ))
  # If llen is too short, increase the padding:
  [ $(( llen + plen + rlen )) -lt "$LINEWIDTH" ] && plen=$(( LINEWIDTH - llen - rlen ))
  echo $llen $plen $rlen
  return 0
}

#-------------------------------------------------------------------------------

function resource_monitor
# Log disk, memory and load average until killed
# $1 = pathname of the log file
# $2 = logging interval in seconds, default 10
# $BUILDSTARTTIME should have been set by the caller
{
  resourcelog="$1"
  sleepsecs="${2:-10}"
  printf '%10s %10s %10s %10s\n' elapsed loadavg memused tmpused > "$resourcelog"
  [ -z "$BUILDSTARTTIME" ] && BUILDSTARTTIME="$(date '+%s')"
  while true; do
    elapsed=$(( $(date '+%s') - BUILDSTARTTIME ))
    loadavg=$(cut -f1 -d' ' < /proc/loadavg)
    memused=$(awk '/MemTotal:/ {mt=$2} /MemAvailable:/ {ma=$2} END {print mt-ma}' /proc/meminfo)
    bigtmpsz=$(df "$BIGTMP" --output=used | tail -n +2)
    printf '%10s %10s %10s %10s\n' "$elapsed" "$loadavg" "$memused" "$bigtmpsz" >> "$resourcelog"
    sleep "$sleepsecs"
  done
}

#-------------------------------------------------------------------------------

function resource_report
# Log peak disk, memory and load average from the resource log file
# (obviously, depending on other activity, these numbers may be completely bogus)
# Don't report if the build lasted less than 60 sec
# $1 = pathname of the resource log file
# $BUILDELAPSED should have been set by the caller
{
  resourcelog="$1"
  read -r lavgpeak mempeak tmppeak < <(tail -n +2 "$resourcelog" | \
    awk '{ linect+=1;
           if ($2 > lmax) lmax=$2;
           if ($3 > mmax) mmax=$3; if (linect == 1) mstart=$3;
           if ($4 > tmax) tmax=$4; if (linect == 1) tstart=$4; }
         END {print lmax,(mmax-mstart)/1024,(tmax-tstart)/1024}')
  if [ -n "$lavgpeak" ] && [ -n "$BUILDELAPSED" ]; then
    if [ "$BUILDELAPSED" -ge 600 ]; then
      log_info -a "Build time $(( BUILDELAPSED / 60 )) min, peak load $lavgpeak, peak memory ${mempeak%.*}M, peak tmp ${tmppeak%.*}M"
    elif [ "$BUILDELAPSED" -ge 60 ]; then
      log_info -a "Build time $BUILDELAPSED sec, peak load $lavgpeak, peak memory ${mempeak%.*}M, peak tmp ${tmppeak%.*}M"
    fi
  fi
  return 0
}
