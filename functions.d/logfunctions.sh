#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# logfunctions.sh - logging and display functions for sboggit:
#   log_start
#   log_depstart
#   log_normal
#   log_success
#   log_warning
#   log_error
#-------------------------------------------------------------------------------

function log_start
{
  msg="${*}                                                                      "
  echo "==============================================================================="
  echo "! ${msg:0:66} $(date +%T) !"
  echo "==============================================================================="
  echo ""
}

function log_depstart
{
  msg="--${*}------------------------------------------------------------------------------"
  echo "${msg:0:79}"
}

#-------------------------------------------------------------------------------

function log_normal
{ echo "$@"; }

function log_success
{ tput bold; tput setaf 2; echo "$@"; tput sgr0; }

function log_warning
{ tput bold; tput setaf 3; echo "$@"; tput sgr0; }

function log_error
{ tput bold; tput setaf 1; echo "$@"; tput sgr0; }

#-------------------------------------------------------------------------------

function log_pass
{
  local c="$1" p="$2"
  log_success ":-) PASS (-: $c/$p"
  echo "$c/$p" >> $SB_LOGDIR/PASSLIST
  mv $SB_LOGDIR/$p.log $SB_LOGDIR/PASS/
  if [ "$SB_USE_WEBPAGE" = 1 ]; then
    :
  fi
}

function log_fail
{
  local c="$1" p="$2"
  log_error ":-( FAIL )-: $c/$p"
  grep -q "^$c/$p\$" $SB_LOGDIR/FAILLIST || echo "$c/$p" >> $SB_LOGDIR/FAILLIST
  # leave the wreckage in $TMP for investigation
  if [ -f $SB_LOGDIR/$p.log ]; then
    mv $SB_LOGDIR/$p.log $SB_LOGDIR/FAIL/$p.log
    log_error "See $SB_LOGDIR/FAIL/$p.log"
  fi
  if [ "$SB_USE_WEBPAGE" = 1 ]; then
    :
  fi
}
