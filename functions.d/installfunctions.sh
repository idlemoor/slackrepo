#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# installfunctions.sh - package install functions for slackrepo
#   install_package
#   uninstall_package
#   dotprofilizer
#-------------------------------------------------------------------------------

function install_package
# Run installpkg if the package is not already installed,
# finding the package in either the package or the dryrun repository
# $1 = itempath
# Return status:
# 0 = installed ok or already installed
# 1 = install failed or not found
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  # Is it already installed? Find it in /var/log/packages
  plist=$(ls /var/log/packages/$prgnam-* 2>/dev/null)
  # filter out false matches
  pkgid=''
  for ppath in $plist; do
    p=$(basename $ppath)
    if [ "$(echo $p | rev | cut -f4- -d- | rev)" = "$prgnam" ]; then
      pkgid=$p
      break
    fi
  done
  ###### check the version (might need upgradepkg)
  # If already installed, return
  [ -n "$pkgid" ] && return 0

  pkgpath=''
  # Look for the package.
  if [ "$OPT_DRYRUN" = 'y' ]; then
    # look in the dryrun repo
    pkgpath=$(ls $SR_DRYREPO/$itempath/$prgnam-*.t?z 2>/dev/null)
  fi
  # look in the temp output dir
  [ -z "$pkgpath" ] && \
    pkgpath=$(ls $SR_TMPOUT/$prgnam-*.t?z 2>/dev/null)
  # look in the proper package repo
  [ -z "$pkgpath" ] && \
    pkgpath=$(ls $SR_PKGREPO/$itempath/$prgnam-*.t?z 2>/dev/null)
  # should have it by now!
  [ -n "$pkgpath" ] || { log_error "${itempath}: Can't find any packages in $SR_PKGREPO/$itempath/"; return 1; }

  if [ "$OPT_VERBOSE" = 'y' ]; then
    installpkg --terse $pkgpath | tee -a $SR_LOGFILE
    stat=$?
  else
    installpkg --terse $pkgpath >>$SR_LOGFILE
    stat=$?
  fi
  if [ $stat != 0 ]; then
    log_error "${itempath}: installpkg $pkgpath failed (status $stat)"
    return 1
  fi
  dotprofilizer $pkgpath
  return 0   # ignore any dotprofilizer problems, probably doesn't matter ;-)
}

#-------------------------------------------------------------------------------

function uninstall_package
# Run removepkg, and do extra cleanup
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if hint_no_uninstall $itempath ; then return 0; fi

  # is it installed?
  plist=$(ls /var/log/packages/$prgnam-* 2>/dev/null)
  # filter out false matches
  pkgid=''
  for ppath in $plist; do
    p=$(basename $ppath)
    if [ "$(echo $p | rev | cut -f4- -d- | rev)" = "$prgnam" ]; then
      pkgid=$p
      break
    fi
  done
  if [ -z "$pkgid" ]; then return 0; fi

  # Save a list of potential detritus in /etc
  etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/$pkgid)
  etcdirs=$(grep '^etc/.*/$' /var/log/packages/$pkgid)

  log_verbose "Uninstalling $pkgid ..."
  removepkg $pkgid >/dev/null 2>&1

  # Remove any surviving detritus
  for f in $etcnewfiles; do
    # (this is why we shouldn't run on an end user system!)
    rm -f /"$f" /"$(echo "$f" | sed 's/\.new$//')"
  done
  for d in $etcdirs; do
    if [ -d "$d" ]; then
      find "$d" -type d -depth -exec rmdir --ignore-fail-on-non-empty {} \;
    fi
  done
  # Do this last so it can mend things the package broke
  # (e.g. by reinstalling a Slackware package)
  hint_cleanup $itempath

  return 0
}

#-------------------------------------------------------------------------------

function dotprofilizer
# Execute the /etc/profile.d scriptlets that came with a specific package
# $1 = path of package
# Return status: always 0
{
  local pkgpath="$1"
  # examine /var/log/packages/xxxx because it's quicker than looking inside a .t?z
  varlogpkg=/var/log/packages/$(basename $pkgpath | sed 's/\.t.z$//')
  if grep -q -E 'etc/profile\.d/.*\.sh(\.new)?' $varlogpkg; then
    for script in $(grep 'etc/profile\.d/.*\.sh' $varlogpkg | sed 's/.new$//'); do
      if [ -f /$script ]; then
        log_verbose "Running profile script /$script"
        . /$script
      elif [ -f /$script.new ]; then
        log_verbose "Running profile script /$script.new"
        . /$script.new
      fi
    done
  fi
  return
}
