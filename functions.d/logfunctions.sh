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
#   log_start
#   log_itemstart
#   log_verbose
#   log_normal
#   log_important
#   log_success
#   log_warning
#   log_error
#   errorscan_itemlog
#-------------------------------------------------------------------------------

function log_start
# Log the start of a top level item on standard output and in MAINLOG
# $* = message
# Return status: always 0
{
  msg="${*}                                                                      "
  line="==============================================================================="
  echo "$line"
  echo "! ${msg:0:66} $(date +%T) !"
  echo "$line"
  echo ""
  echo "$line"                        >>$MAINLOG
  echo "STARTING $@ $(date '+%F %T')" >>$MAINLOG
}

#-------------------------------------------------------------------------------

function log_itemstart
# Log the start of an item on standard output and in MAINLOG.
# This is where we start logging to ITEMLOG.
# ITEMLOG is set here, using $itempath set by our caller.
# (At any time only one ITEMLOG can be active.)
# $* = message
# Return status: always 0
{
  line="-------------------------------------------------------------------------------"
  tput bold; tput setaf 7
  if [ ${#1} -ge ${#line} ]; then
    echo "$@"
  else
    pad=$(( ${#line} - ${#1} - 1 ))
    echo "$@ ${line:0:$pad}"
  fi
  tput sgr0
  echo "$line"                 >>$MAINLOG
  echo "$@ $(date '+%F %T')"   >>$MAINLOG
  if [ -n "$itempath" ]; then
    mkdir -p $SR_LOGDIR/${itempath%/*}
    ITEMLOG="$SR_LOGDIR/$itempath.log"
    echo "$@ $(date '+%F %T')"  >$ITEMLOG
  fi
}

#-------------------------------------------------------------------------------

function log_verbose
# Log a message to MAINLOG, and also to standard output if OPT_VERBOSE is set
# (and ITEMLOG if '-a' is specified)
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  if [ "$OPT_VERBOSE" = 'y' ]; then
    echo "$@"
  fi
  echo "$@" >>$MAINLOG
  [ "$A" = 'y' ] && \
  echo "$@" >>$ITEMLOG
  return 0
}

#-------------------------------------------------------------------------------

function log_normal
# Log a message to MAINLOG, and also to standard output unless OPT_QUIET is set
# (and ITEMLOG if '-a' is specified)
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  if [ "$OPT_QUIET" != 'y' ]; then
    echo "$@"
  fi
  echo "$@" >>$MAINLOG
  [ "$A" = 'y' ] && \
  echo "$@" >>$ITEMLOG
  return 0
}

#-------------------------------------------------------------------------------

function log_important
# Log a message to standard output in white highlight, and log to MAINLOG
# (and ITEMLOG if '-a' is specified)
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  tput bold; tput setaf 7
  echo "$@"
  tput sgr0
  echo "$@" >>$MAINLOG
  [ "$A" = 'y' ] && \
  echo "$@" >>$ITEMLOG
  return 0
}

#-------------------------------------------------------------------------------

function log_success
# Log a message to standard output in green highlight, and log to MAINLOG
# (and ITEMLOG if '-a' is specified)
# $* = message
# Return status: always 0
{
  A='n'
  [ "$1" = '-a' ] && { A='y'; shift; }
  tput bold; tput setaf 2
  echo "$@"
  tput sgr0
  echo "$@" >>$MAINLOG
  [ "$A" = 'y' ] && \
  echo "$@" >>$ITEMLOG
  return 0
}

#-------------------------------------------------------------------------------

function log_warning
# Log a message to standard output in yellow highlight, and log to MAINLOG
# (and ITEMLOG if '-a' is specified)
# Message is automatically prefixed with 'WARNING' (unless '-n' is specified)
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
  tput bold; tput setaf 3
  echo "${W}$@"
  tput sgr0
  echo "${W}$@" >>$MAINLOG
  [ "$A" = 'y' ] && \
  echo "${W}$@" >>$ITEMLOG
  return 0
}

#-------------------------------------------------------------------------------

function log_error
# Log a message to standard output in red highlight, and log to MAINLOG
# (and ITEMLOG if '-a' is specified)
# Message is automatically prefixed with 'ERROR' (unless '-n' is specified)
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
  tput bold; tput setaf 1
  echo "${E}$@"
  tput sgr0
  # In case we are called before MAINLOG is set:
  [ -z "$MAINLOG" ] && return 0
  echo "${E}$@" >>$MAINLOG
  [ "$A" = 'y' ] && \
  echo "${E}$@" >>$ITEMLOG
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
    $ITEMLOG
  return 0
}
