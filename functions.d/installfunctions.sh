#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# installfunctions.sh - package install functions for slackrepo
#   install_packages
#   uninstall_packages
#   dotprofilizer
#-------------------------------------------------------------------------------

function install_packages
# Run installpkg if the package is not already installed,
# finding the package in either the package or the dryrun repository
# $1 = itemid
# Return status:
# 0 = installed ok or already installed
# 1 = install failed or not found
{
  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"
  local -a pkglist
  local pkgpath pkgbase pkgid stat

  # Look for the package(s).
  # Start with the temp output dir
  pkglist=( $(ls "$SR_TMPOUT"/*.t?z 2>/dev/null) )
  # If nothing there, look in the dryrun repo
  [ "${#pkglist[@]}" = 0 -a "$OPT_DRYRUN" = 'y' ] &&
    pkglist=( $(ls "$DRYREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  # Finally, look in the proper package repo
  [ "${#pkglist[@]}" = 0 ] && \
    pkglist=( $(ls "$SR_PKGREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  # should have something by now!
  [ "${#pkglist[@]}" = 0 ] && \
    { log_error -a "${itemid}: Can't find any packages to install"; return 1; }

  for pkgpath in "${pkglist[@]}"; do
    pkgbase=$(basename "$pkgpath" | sed 's/\.t.z$//')
    pkgid=$(echo "$pkgbase" | rev | cut -f4- -d- | rev )
    # Is it already installed? Find it in /var/log/packages
    if [ -f /var/log/packages/"$pkgbase" ]; then
      log_verbose -a "$pkgbase is already installed"
    elif ls /var/log/packages/"$pkgid"-* 1>/dev/null 2>/dev/null; then
      for instpkg in /var/log/packages/"$pkgid"-*; do
        if [ "$(basename "$instpkg" | rev | cut -f4- -d- | rev)" = "$pkgid" ]; then
          log_verbose -a "A previous instance of $pkgid is already installed; upgrading ..."
          if [ "$OPT_VERBOSE" = 'y' ]; then
            upgradepkg --reinstall "$pkgpath" 2>&1 | tee -a "$MAINLOG" "$ITEMLOG"
            stat=$?
          else
            upgradepkg --reinstall "$pkgpath" >> "$ITEMLOG" 2>&1
            stat=$?
          fi
          [ "$stat" = 0 ] || { log_error -a "${itemid}: upgradepkg $pkgbase failed (status $stat)"; return 1; }
          dotprofilizer "$pkgpath"
          break
        fi
      done
    else
      if [ "$OPT_VERBOSE" = 'y' ]; then
        installpkg --terse "$pkgpath" 2>&1 | tee -a "$MAINLOG" "$ITEMLOG"
        stat=$?
      else
        installpkg --terse "$pkgpath" >> "$ITEMLOG" 2>&1
        stat=$?
      fi
      [ "$stat" = 0 ] || { log_error -a "${itemid}: installpkg $pkgbase failed (status $stat)"; return 1; }
      dotprofilizer "$pkgpath"
    fi
  done
  return 0
}

#-------------------------------------------------------------------------------

function uninstall_packages
# Run removepkg, and do extra cleanup
# $1 = itemid
# Return status: always 0
{
  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"
  local -a pkglist
  local pkgpath pkgbase pkgid
  local etcnewfiles etcdirs etcfile etcdir

  [ "$OPT_INSTALL" = 'y' ] && return 0
  [ "${HINT_no_uninstall[$itemid]}" = 'y' ] && return 0

  # Look for the package(s).
  # Start with the temp output dir
  pkglist=( $(ls "$SR_TMPOUT"/*.t?z 2>/dev/null) )
  # If nothing there, look in the dryrun repo
  [ "${#pkglist[@]}" = 0 -a "$OPT_DRYRUN" = 'y' ] &&
    pkglist=( $(ls "$DRYREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  # Finally, look in the proper package repo
  [ "${#pkglist[@]}" = 0 ] && \
    pkglist=( $(ls "$SR_PKGREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  # should have something by now!
  [ "${#pkglist[@]}" = 0 ] && \
    { log_error -a "${itemid}: Can't find any packages to uninstall"; return 1; }

  for pkgpath in "${pkglist[@]}"; do
    pkgbase=$(basename "$pkgpath" | sed 's/\.t.z$//')
    pkgid=$(echo "$pkgbase" | rev | cut -f4- -d- | rev )
    # Is it installed?
    if [ -f /var/log/packages/"$pkgbase" ]; then

      # Save a list of potential detritus in /etc
      etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/"$pkgbase")
      etcdirs=$(grep '^etc/.*/$' /var/log/packages/"$pkgbase")

      log_verbose -a "Uninstalling $pkgbase ..."
      removepkg "$pkgbase" >> "$ITEMLOG" 2>&1

      # Remove any surviving detritus
      for etcfile in $etcnewfiles; do
        # (this is why we shouldn't run on an end user system!)
        rm -f /"$etcfile" /"$(echo "$etcfile" | sed 's/\.new$//')"
      done
      for etcdir in $etcdirs; do
        if [ -d "$etcdir" ]; then
          find "$etcdir" -type d -depth -exec rmdir --ignore-fail-on-non-empty {} \;
        fi
      done

      # Do this last so it can mend things the package broke.
      # The cleanup file can contain any required shell commands, for example:
      #   * Reinstalling Slackware packages that conflict with the item's packages
      #   * Unsetting environment variables set in an /etc/profile.d script
      #   * Removing specific files and directories that removepkg doesn't remove
      #   * Running depmod to remove references to removed kernel modules
      if [ -n "${HINT_cleanup[$itemid]}" ]; then
        . "${HINT_cleanup[$itemid]}" >> "$ITEMLOG" 2>&1
      fi

    fi
  done

  return 0
}

#-------------------------------------------------------------------------------

function dotprofilizer
# Execute the /etc/profile.d scriptlets that came with a specific package
# $1 = path of package
# Return status: always 0
{
  local pkgpath="$1"
  local varlogpkg script
  # examine /var/log/packages/xxxx because it's quicker than looking inside a .t?z
  varlogpkg=/var/log/packages/$(basename "$pkgpath" | sed 's/\.t.z$//')
  if grep -q -E 'etc/profile\.d/.*\.sh(\.new)?' "$varlogpkg"; then
    for script in $(grep 'etc/profile\.d/.*\.sh' "$varlogpkg" | sed 's/.new$//'); do
      if [ -f /"$script" ]; then
        log_verbose -a "Running profile script /$script"
        . /"$script"
      elif [ -f /"$script".new ]; then
        log_verbose -a "Running profile script /$script.new"
        . /"$script".new
      fi
    done
  fi
  return
}
