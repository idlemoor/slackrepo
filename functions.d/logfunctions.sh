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
{
  PRG=${logprg:-$prg}
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
{
  PRG=${logprg:-$prg}
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
{
  PRG=${logprg:-$prg}
  if [ "$VERBOSE" = 'y' ]; then
    echo "$@"
  fi
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_normal
{
  PRG=${logprg:-$prg}
  echo "$@"
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_important
{
  PRG=${logprg:-$prg}
  tput bold; tput setaf 7
  echo "$@"
  tput sgr0
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_success
{
  PRG=${logprg:-$prg}
  tput bold; tput setaf 2
  echo "$@"
  tput sgr0
  echo "$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_warning
{
  if [ "$1" = '-n' ]; then
    W=''
    shift
  else
    W='WARNING: '
  fi
  PRG=${logprg:-$prg}
  tput bold; tput setaf 3
  echo "${W}$@"
  tput sgr0
  echo "${W}$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "${W}$@" >>$SR_LOGDIR/$PRG.log
}

#-------------------------------------------------------------------------------

function log_error
{
  if [ "$1" = '-n' ]; then
    E=''
    shift
  else
    E='ERROR: '
  fi
  PRG=${logprg:-$prg}
  tput bold; tput setaf 1
  echo "${E}$@"
  tput sgr0
  # We might be called before SR_LOGFILE is set (unlike the other log funcs)
  [ -z "$SR_LOGFILE" ] && return 0
  echo "${E}$@" >>$SR_LOGFILE
  [ -n "$PRG" ] && \
  echo "${E}$@" >>$SR_LOGDIR/$PRG.log
}
