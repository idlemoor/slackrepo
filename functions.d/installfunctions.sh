#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# installfunctions.sh - package install functions for sboggit:
#   install_prebuilt_packages
#   install_package
#   uninstall_package
#   dotprofilizer
#   clean_outputdir
#-------------------------------------------------------------------------------

function install_prebuilt_packages
{
  local p="$1"
  c=$(cd $SB_REPO/*/$p/..; basename $(pwd))
  log_depstart "$c/$p"
  pkglist=$(ls $SB_OUTPUT/$p/*$SB_TAG.t?z 2>/dev/null)
  for pkgpath in $pkglist; do
    pkgid=$(echo $(basename $pkgpath) | sed "s/$SB_TAG\.t.z\$//")
    if [ -e /var/log/packages/$pkgid ]; then
      log_warning "WARNING: $p is already installed:" $(ls /var/log/packages/$pkgid)
    else
      install_package $pkgpath || return 1
    fi
  done
}

#-------------------------------------------------------------------------------

function install_package
{
  local pkgpath="$1"
  log_normal "Installing $pkgpath ..."
  installpkg --terse $pkgpath
  stat=$?
  if [ $stat != 0 ]; then
    log_error "ERROR: installpkg $pkgpath failed (status $stat)"
    itfailed
    return 1
  fi
  dotprofilizer $pkgpath
  return 0   # ignore any dotprofilizer problems, probably doesn't matter ;-)
}

#-------------------------------------------------------------------------------

function uninstall_package
{
  local prg="$1"
  # filter out false matches in /var/log/packages
  plist=$(ls /var/log/packages/$prg-*$SB_TAG 2>/dev/null)
  pkgid=''
  for ppath in $plist; do
    p=$(basename $ppath)
    if [ "$(echo $p | rev | cut -f4- -d- | rev)" = "$prg" ]; then
      pkgid=$p
      break
    fi
  done
  [ -n "$pkgid" ] || { log_normal "Not removing $prg (not installed)"; return 1; }
  # Save a list of potential detritus in /etc
  etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/$pkgid)
  etcdirs=$(grep '^etc/.*/$' /var/log/packages/$pkgid)
  log_normal "Removing $pkgid"
  removepkg $pkgid >/dev/null 2>&1
  # Remove any surviving detritus
  for f in $etcnewfiles; do
    rm -f /"$f" /"$(echo "$f" | sed 's/\.new$//')"
  done
  for d in $etcnewdirs; do
    rmdir --ignore-fail-on-non-empty /"$d"
  done
  # Do this last so it can mend things we broke
  # (e.g. by reinstalling a Slackware package)
  hint_cleanup $prg
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
        log_normal "Running profile script /$script"
        . /$script
      elif [ -f /$script.new ]; then
        log_normal "Running profile script /$script.new"
        . /$script.new
      fi
    done
  fi
}

#-------------------------------------------------------------------------------

function clean_outputdir
{
  log_normal "Cleaning output directory $SB_OUTPUT ..."
  for outpath in $(ls $SB_OUTPUT/* 2>/dev/null); do
    pkgname=$(basename $outpath)
    if [ ! -d "$(ls -d $SB_REPO/*/$pkgname 2>/dev/null)" ]; then
      rm -rf -v "$SB_OUTPUT/$pkgname"
    fi
  done
  log_normal "Finished cleaning output directory."
}
