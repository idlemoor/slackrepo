#!/bin/bash
#-------------------------------------------------------------------------------
# installfunctions.sh - package install functions for SBoggit:
#   in_outrepo_and_uptodate
#   install_from_outrepo
#   dotprofilizer
#   clean_outrepo
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

function in_outrepo_and_uptodate
{
  # Returns:
  # 1 - not found (or unstamped with git rev)
  # 2 - git thinks the directory has been modified locally
  # 3 - previous git rev != current git rev
  local p="${1:-$prg}"
  gitrevfilename=$(ls $OUTREPO/$p/gitrev-* 2>/dev/null)
  pkglist=$(ls $OUTREPO/$p/*$TAG.t?z 2>/dev/null)
  if [ -z "$pkglist" -o $(echo $gitrevfilename | wc -w) != 1 ]; then
    echo "$p not found, needs to be built."
    return 1
  elif [ -n "$(cd $SBOREPO/*/$p; git status -s .)" ]; then
    echo "$p has been modified."
    # Note, if a tar.gz hint is identical to upstream git (eg. if merged),
    # git status won't know that the hint was applied.  This is a Good Thing.
    return 2
  else
    pkgrev=$(echo $gitrevfilename | sed 's/^.*gitrev-//')
    prgrev=$(git log -n 1 --format=format:%h $SBOREPO/*/$p)
    if [ $pkgrev = $prgrev ]; then
      echo "$p $pkgrev is up-to-date."
      return 0
    else
      echo "$p $pkgrev is not up-to-date ($GITBRANCH is $prgrev)."
      return 3
    fi
  fi
}

#-------------------------------------------------------------------------------

function install_from_outrepo
{
  local p="${1:-$prg}"
  c=$(cd $SBOREPO/*/$p/..; basename $(pwd))
  msg="--$c/$p-----------------------------------------------------------------------------"
  echo "${msg:0:79}"
  pkglist=$(ls $OUTREPO/$p/*$TAG.t?z 2>/dev/null)
  for pkgpath in $pkglist; do
    pkgid=$(echo $(basename $pkgpath) | sed "s/$TAG\.t.z\$//")
    if [ -e /var/log/packages/$pkgid ]; then
      echo_yellow "WARNING: $p is already installed:" $(ls /var/log/packages/$pkgid)
    else
      echo "Installing previously built $pkgpath ..."
      installpkg --terse $pkgpath
      stat=$?
      if [ $stat != 0 ]; then
        echo "ERROR: installpkg $pkgpath failed (status $stat)"
        itfailed
        return 1
      fi
      dotprofilizer $pkgpath  # ignore any problems, probably doesn't matter ;-)
    fi
  done
}

#-------------------------------------------------------------------------------

function dotprofilizer
{
  local p="${1:-$prg}"
  # examine /var/log/packages/xxxx because it's quicker than looking inside a .t?z
  varlogpkg=/var/log/packages/$(basename $p | sed 's/\.t.z$//')
  if grep -q -E 'etc/profile\.d/.*\.sh(\.new)?' $varlogpkg; then
    for script in $(grep 'etc/profile\.d/.*\.sh' $varlogpkg | sed 's/.new$//'); do
      if [ -f /$script ]; then
        echo "Running profile script /$script"
        . /$script
      elif [ -f /$script.new ]; then
        echo "Running profile script /$script.new"
        . /$script.new
      fi
    done
  fi
}

#-------------------------------------------------------------------------------

function clean_outrepo
{
  echo "Cleaning output repo $OUTREPO ..."
  for outpath in $(ls $OUTREPO/* 2>/dev/null); do
    pkgname=$(basename $outpath)
    if [ ! -d "$(ls -d $SBOREPO/*/$pkgname 2>/dev/null)" ]; then
      rm -rf -v "$OUTREPO/$pkgname"
    fi
  done
  echo "Finished cleaning output repo."
}
