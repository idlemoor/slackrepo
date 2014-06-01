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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"
  local -a pkglist
  local pkgpath pkgbase pkgid stat

  # Look for the package(s).
  # Start with the temp output dir
  pkglist=( $(ls "$MYTMPOUT"/*.t?z 2>/dev/null) )
  # If nothing there, look in the dryrun repo
  [ "${#pkglist[@]}" = 0 -a "$OPT_DRY_RUN" = 'y' ] &&
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
          log_normal -a "A previous instance of $pkgid is already installed; upgrading ..."
          if [ "$OPT_VERY_VERBOSE" = 'y' ]; then
            /sbin/upgradepkg --reinstall "$pkgpath" 2>&1 | tee -a "$ITEMLOG"
            stat=$?
          else
            /sbin/upgradepkg --reinstall "$pkgpath" >> "$ITEMLOG" 2>&1
            stat=$?
          fi
          [ "$stat" = 0 ] || { log_error -a "${itemid}: upgradepkg $pkgbase failed (status $stat)"; return 1; }
          dotprofilizer "$pkgpath"
          break
        fi
      done
    else
      if [ "$OPT_VERBOSE" = 'y' -o "$OPT_INSTALL" = 'y' ]; then
        /sbin/installpkg --terse "$pkgpath" 2>&1 | tee -a "$MAINLOG" "$ITEMLOG"
        stat=$?
      else
        /sbin/installpkg --terse "$pkgpath" >> "$ITEMLOG" 2>&1
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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"
  local -a pkglist
  local pkgpath pkgbase pkgid
  local etcnewfiles etcdirs etcfile etcdir

  [ "${HINT_INSTALL[$itemid]}" = 'y' ] && return 0

  # Look for the package(s).
  # Start with the temp output dir
  pkglist=( $(ls "$MYTMPOUT"/*.t?z 2>/dev/null) )
  # If nothing there, look in the dryrun repo
  [ "${#pkglist[@]}" = 0 -a "$OPT_DRY_RUN" = 'y' ] &&
    pkglist=( $(ls "$DRYREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  # Finally, look in the proper package repo
  [ "${#pkglist[@]}" = 0 ] && \
    pkglist=( $(ls "$SR_PKGREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  # oh well, never mind -- return quietly
  [ "${#pkglist[@]}" = 0 ] && return 0

  for pkgpath in "${pkglist[@]}"; do
    pkgbase=$(basename "$pkgpath" | sed 's/\.t.z$//')
    pkgid=$(echo "$pkgbase" | rev | cut -f4- -d- | rev )

    # Is it installed?
    if [ -f /var/log/packages/"$pkgbase" ]; then

      if [ "$OPT_INSTALL" = 'y' ]; then
        # Conventional gentle removepkg :-)
        log_normal -a "Uninstalling $pkgbase ..."
        /sbin/removepkg "$pkgbase" >> "$ITEMLOG" 2>&1
      else
        # Violent removal :D
        # Save a list of potential detritus in /etc
        etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/"$pkgbase")
        etcdirs=$(grep '^etc/.*/$' /var/log/packages/"$pkgbase")
        # Run removepkg
        log_verbose -a "Uninstalling $pkgbase ..."
        /sbin/removepkg "$pkgbase" >> "$ITEMLOG" 2>&1
        # Remove any surviving detritus
        for etcfile in $etcnewfiles; do
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
        if [ -n "${HINT_CLEANUP[$itemid]}" ]; then
          eval "${HINT_CLEANUP[$itemid]}" >> "$ITEMLOG" 2>&1
        fi
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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local pkgpath="$1"
  local varlogpkg script
  # examine /var/log/packages/xxxx because it's quicker than looking inside a .t?z
  varlogpkg=/var/log/packages/$(basename "$pkgpath" | sed 's/\.t.z$//')
  if grep -q -E 'etc/profile\.d/.*\.sh(\.new)?' "$varlogpkg"; then
    for script in $(grep 'etc/profile\.d/.*\.sh' "$varlogpkg" | sed 's/.new$//'); do
      if [ -f /"$script" ]; then
        log_verbose -a "  Running profile script /$script"
        . /"$script"
      elif [ -f /"$script".new ]; then
        log_verbose -a "  Running profile script /$script.new"
        . /"$script".new
      fi
    done
  fi
  return
}
