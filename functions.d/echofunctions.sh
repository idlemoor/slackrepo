#!/bin/bash
#-------------------------------------------------------------------------------
# echofunctions.sh - fancy display functions for SBoggit:
#   echoinbox
#   echored
#   echogreen
#   echoyellow
#
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#-------------------------------------------------------------------------------

function echoinbox
{
  msg="${*}                                                                      "
  echo "==============================================================================="
  echo "! ${msg:0:66} $(date +%T) !"
  echo "==============================================================================="
  echo ""
}

function echored
{ tput bold; tput setaf 1; echo "$@"; tput sgr0; }

function echogreen
{ tput bold; tput setaf 2; echo "$@"; tput sgr0; }

function echoyellow
{ tput bold; tput setaf 3; echo "$@"; tput sgr0; }
