#!/bin/bash
#-------------------------------------------------------------------------------
# hintfunctions.sh - functions for SBoggit hints:
#   hint_skipme
#   hint_uidgid
#   hint_options
#   hint_makeflags
#   hint_cleanup
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

function hint_skipme
{
  local prg="$1"
  # Note the return status: 0 = skip, 1 = do not skip
  if [ ! -f $HINTS/$prg.skipme ]; then
    return 1
  fi
  category=$(cd $SBOREPO/*/$prg/..; basename $(pwd))
  echo_yellow "SKIPPED $category/$prg due to hint"
  cat $HINTS/$prg.skipme
  return 0
}

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
  # Prints options to standard output, so don't display any messages here!
  if [ -f $HINTS/$prg.options ]; then
    echo "$(cat $HINTS/$prg.options)"
  fi
}

#-------------------------------------------------------------------------------

function hint_makeflags
{
  local prg="$1"
  # Prints makeflags to standard output, so don't display any messages here!
  # Currently handles only -j1 (no real requirement for anything else).
  if [ -f $HINTS/$prg.makej1 ]; then
    echo "MAKEFLAGS='-j1'"
  fi
}

#-------------------------------------------------------------------------------

function hint_cleanup
{
  local prg="$1"
  # Returns 1 if no hint found.
  # The prg.cleanup file can contain any required shell commands, for example:
  #   * Reinstalling Slackware packages that conflict with prg
  #   * Unsetting any environment variables set in prg's /etc/profile.d script
  #   * Removing specific files and directories that removepkg doesn't remove
  #   * Running depmod to remove references to removed kernel modules
  [ -f $HINTS/$prg.cleanup ] || return 1
  echo "Hint: running $HINTS/$prg.cleanup..."
  . $HINTS/$prg.cleanup >>$LOGDIR/$prg.log 2>&1
  return 0
}
