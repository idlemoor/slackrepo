#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# logfunctions.sh - logging and display functions for sboggit:
#   log_start
#   log_depstart
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

function log_success
{ tput bold; tput setaf 2; echo "$@"; tput sgr0; }

function log_warning
{ tput bold; tput setaf 3; echo "$@"; tput sgr0; }

function log_error
{ tput bold; tput setaf 1; echo "$@"; tput sgr0; }
