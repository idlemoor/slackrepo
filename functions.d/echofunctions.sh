#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# echofunctions.sh - fancy display functions for sboggit:
#   echo_boxed
#   echo_lined
#   echo_red
#   echo_green
#   echo_yellow
#-------------------------------------------------------------------------------

function echo_boxed
{
  msg="${*}                                                                      "
  echo "==============================================================================="
  echo "! ${msg:0:66} $(date +%T) !"
  echo "==============================================================================="
  echo ""
}

function echo_lined
{
  msg="--${*}------------------------------------------------------------------------------"
  echo "${msg:0:79}"
}

function echo_red
{ tput bold; tput setaf 1; echo "$@"; tput sgr0; }

function echo_green
{ tput bold; tput setaf 2; echo "$@"; tput sgr0; }

function echo_yellow
{ tput bold; tput setaf 3; echo "$@"; tput sgr0; }
