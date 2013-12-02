#!/bin/bash
#-------------------------------------------------------------------------------
# hintfunctions.sh - functions for SBoggit hints:
#   hint_uidgid
#   hint_options
#   hint_makeflags
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

function hint_uidgid
{
  local prg="$1"
  # Returns 1 if no hint found.
  # The prg.uidgid file should contain
  # *either* an assignment of UIDGIDNUMBER and (optionally) UIDGIDNAME,
  #          UIDGIDCOMMENT, UIDGIDDIR, UIDGIDSHELL
  # *or* a script to make the UID and/or the GID, if it's not straightforward.
  [ -f $HINTS/$prg.uidgid ] || return 1
  unset UIDGIDNUMBER
  echo "Hint: setup uid/gid for $prg"
  . $HINTS/$prg.uidgid
  [ -n "$UIDGIDNUMBER" ] || return 0
  UIDGIDNAME=${UIDGIDNAME:-$prg}
  if ! getent group $UIDGIDNAME | grep -q ^$UIDGIDNAME: 2>/dev/null ; then
    groupadd -g $UIDGIDNUMBER $UIDGIDNAME
  fi
  if ! getent passwd $UIDGIDNAME | grep -q ^$UIDGIDNAME: 2>/dev/null ; then
    useradd \
      -u $UIDGIDNUMBER \
      -c ${UIDGIDCOMMENT:-$UIDGIDNAME} \
      -d ${UIDGIDDIR:-/dev/null} \
      -s ${UIDGIDSHELL:-/bin/false} \
      -g $UIDGIDNAME \
      $UIDGIDNAME
  fi
  return 0
}

#-------------------------------------------------------------------------------

function hint_options
{
  local prg="$1"
  if [ -f $HINTS/$prg.options ]; then
    echo "$(cat $HINTS/$prg.options)"
  fi
}

#-------------------------------------------------------------------------------

function hint_makeflags
{
  local prg="$1"
  if [ -f $HINTS/$prg.makej1 ]; then
    echo "MAKEFLAGS='-j1'"
  fi
}
