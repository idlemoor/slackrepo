#!/bin/bash
#-------------------------------------------------------------------------------
# depfunctions.sh - dependency functions for SBoggit:
#   dependublaster2000
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

function dependublaster2000
{
  local me="$1"
  local prevdep mydeps moredeps dep readmedep
  for prevdep in $DEPLIST; do
    if [ "$prevdep" = "$me" ]; then
      # if I'm already on the list, then my deps must also be on the list
      # so nothing to do :-)
      return 0
    fi
  done
  if [ ! -d $SBOREPO/*/$me ]; then
    echo_yellow "WARNING: Dependency $me not found in $SBOREPO"
    return 0  # carry on regardless ;-)
  fi
  if [ -f $HINTS/$me.tar.gz ]; then
    echo "Hint: applying tarball for $me"
    ( cd $SBOREPO/*/$me/..; rm -rf $me/; tar xf $HINTS/$me.tar.gz )
  fi
  . $SBOREPO/*/$me/$me.info
  # ok, ready to go!  First, add my deps:
  mydeps="$REQUIRES"
  if [ -f $HINTS/$me.moredeps ]; then
    moredeps="$(cat $HINTS/$me.moredeps)"
    echo "Hint: adding more deps: $moredeps"
    mydeps="$mydeps $moredeps"
  fi
  for dep in $mydeps; do
    if [ $dep = '%README%' ]; then
      if [ -f $HINTS/$me.readmedeps ]; then
        echo "Hint: substituting '$(cat $HINTS/$me.readmedeps)' for %README%"
        for readmedep in $(cat $HINTS/$me.readmedeps); do 
          dependublaster2000 $readmedep
        done
      else
        echo_yellow "WARNING: %README% in $me.info but $HINTS/$me.readmedeps not found"
      fi
    else
      dependublaster2000 $dep
    fi
  done
  # then add me:
  DEPLIST="$DEPLIST $me"
  return 0
}
