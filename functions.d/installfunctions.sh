#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# installfunctions.sh - package install functions for sboggit:
#   in_outrepo_and_uptodate
#   install_from_outrepo
#   dotprofilizer
#   clean_outputdir
#-------------------------------------------------------------------------------

function in_outrepo_and_uptodate
{
  # Returns:
  # 1 - not found (or unstamped with git rev)
  # 2 - git thinks the directory has been modified locally
  # 3 - previous git rev != current git rev
  local p="${1:-$prg}"
  gitrevfilename=$(ls $SB_OUTPUT/$p/gitrev-* 2>/dev/null)
  pkglist=$(ls $SB_OUTPUT/$p/*$SB_TAG.t?z 2>/dev/null)
  if [ -z "$pkglist" -o $(echo $gitrevfilename | wc -w) != 1 ]; then
    echo "$p not found, needs to be built."
    return 1
  elif [ -n "$(cd $SB_REPO/*/$p; git status -s .)" ]; then
    echo "$p has been modified."
    # Note, if a tar.gz hint is identical to upstream git (eg. if merged),
    # git status won't know that the hint was applied.  This is a Good Thing.
    return 2
  else
    pkgrev=$(echo $gitrevfilename | sed 's/^.*gitrev-//')
    prgrev=$(git log -n 1 --format=format:%h $SB_REPO/*/$p)
    if [ $pkgrev = $prgrev ]; then
      echo "$p $pkgrev is up-to-date."
      return 0
    else
      echo "$p $pkgrev is not up-to-date ($SB_GITBRANCH is $prgrev)."
      return 3
    fi
  fi
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

function clean_outputdir
{
  echo "Cleaning output directory $SB_OUTPUT ..."
  for outpath in $(ls $SB_OUTPUT/* 2>/dev/null); do
    pkgname=$(basename $outpath)
    if [ ! -d "$(ls -d $SB_REPO/*/$pkgname 2>/dev/null)" ]; then
      rm -rf -v "$SB_OUTPUT/$pkgname"
    fi
  done
  echo "Finished cleaning output directory."
}
