#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# logfunctions.sh - logging and web page functions for slackrepo
#   log_start
#   log_prgstart
#   log_verbose
#   log_normal
#   log_important
#   log_success
#   log_warning
#   log_error
#-------------------------------------------------------------------------------

function log_start
# Log the start of a top level item on screen and in logfile
# $* = message
# Return status: always 0
{
  PRG=${logprg:-$prgnam}
  msg="${*}                                                                      "
  line="==============================================================================="
  echo "$line"
  echo "! ${msg:0:66} $(date +%T) !"
  echo "$line"
  echo ""
  echo "$line"                      >>$SR_LOGFILE
  echo "STARTING $@ $(date '+%F %T')" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "STARTING $@ $(date '+%F %T')" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_prgstart
# Log the start of a sub-item on screen and in logfile
# $* = message
# Return status: always 0
{
  PRG=${logprg:-$prgnam}
  line="-------------------------------------------------------------------------------"
  pad=$(( ${#line} - ${#1} - 1 ))
  tput bold; tput setaf 7
  echo "$@ ${line:0:$pad}"
  tput sgr0
  echo "$line"          >>$SR_LOGFILE
  echo "$@ $(date '+%F %T')" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$line"          >>$SR_LOGDIR/$PRG.log
  [ -n "$PRG" ] && \
  echo "$@ $(date '+%F %T')" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_verbose
# Log a message to the logfile, and also to the screen if global variable
# VERBOSE is set.
# $* = message
# Return status: always 0
{
  PRG=${logprg:-$prgnam}
  if [ "$VERBOSE" = 'y' ]; then
    echo "$@"
  fi
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_normal
# Print message on screen, and log to logfile
# $* = message
# Return status: always 0
{
  PRG=${logprg:-$prgnam}
  echo "$@"
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_important
# Print message on screen in white highlight, and log to logfile
# $* = message
# Return status: always 0
{
  PRG=${logprg:-$prgnam}
  tput bold; tput setaf 7
  echo "$@"
  tput sgr0
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_success
# Print message on screen in green highlight, and log to logfile
# $* = message
# Return status: always 0
{
  PRG=${logprg:-$prgnam}
  tput bold; tput setaf 2
  echo "$@"
  tput sgr0
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_warning
# Print message on screen in yellow highlight, and log to logfile
# Message is automatically prefixed with 'WARNING', unless $1 = '-n'
# $* = message
# Return status: always 0
{
  if [ "$1" = '-n' ]; then
    W=''
    shift
  else
    W='WARNING: '
  fi
  PRG=${logprg:-$prgnam}
  tput bold; tput setaf 3
  echo "${W}$@"
  tput sgr0
  echo "${W}$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "${W}$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_error
# Print message on screen in red highlight, and log to logfile
# Message is automatically prefixed with 'ERROR', unless $1 = '-n'
# $* = message
# Return status: always 0
{
  if [ "$1" = '-n' ]; then
    E=''
    shift
  else
    E='ERROR: '
  fi
  PRG=${logprg:-$prgnam}
  tput bold; tput setaf 1
  echo "${E}$@"
  tput sgr0
  # In case we are called before SR_LOGFILE is set:
  [ -z "$SR_LOGFILE" ] && return 0
  echo "${E}$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "${E}$@" >>$SR_LOGDIR/$PRG.log
}
