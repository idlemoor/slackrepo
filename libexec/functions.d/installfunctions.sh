#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# installfunctions.sh - package install functions for slackrepo
#   install_deps
#   uninstall_deps
#   install_packages
#   uninstall_packages
#   is_installed
#   dotprofilizer
#-------------------------------------------------------------------------------

function install_deps
# Install dependencies of $itemid (but NOT $itemid itself)
# $1 = itemid
# Return status:
# 0 = all installs succeeded
# 1 = any install failed
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local mydep
  local allinstalled='y'

  if [ -n "${FULLDEPS[$itemid]}" ]; then
    log_normal -a "Installing dependencies ..."
    for mydep in ${FULLDEPS[$itemid]}; do
      install_packages "$mydep" || allinstalled='n'
    done
    # If any installs failed, uninstall them all and return an error:
    if [ "$allinstalled" = 'n' ]; then
      for mydep in ${FULLDEPS[$itemid]}; do
        uninstall_packages "$mydep"
      done
      return 1
    fi
  fi

  return 0
}

#-------------------------------------------------------------------------------

function uninstall_deps
# Uninstall dependencies of $itemid (but NOT $itemid itself)
# $1 = itemid
# Return status always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local mydep

  if [ -n "${FULLDEPS[$itemid]}" ]; then
    log_normal -a "Uninstalling dependencies ..."
    for mydep in ${FULLDEPS[$itemid]}; do
      uninstall_packages "$mydep"
    done
  fi
  return 0
}

#-------------------------------------------------------------------------------

function install_packages
# Run installpkg if the package is not already installed,
# finding the package in either the package or the dryrun repository
# $1 = itemid
# Return status:
# 0 = installed ok or already installed
# 1 = install failed or not found
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"
  local -a pkglist
  local pkgpath pkgbase pkgid stat

  # Look for the package(s).
  # Start with the temp output dir
  [ -n "$MYTMPOUT" ] && pkglist=( "$MYTMPOUT"/*.t?z )
  # If nothing there, look in the dryrun repo
  [ ! -e "${pkglist[0]}" -a "$OPT_DRY_RUN" = 'y' ] &&
    pkglist=( "$DRYREPO"/"$itemdir"/*.t?z )
  # Finally, look in the proper package repo
  [ ! -e "${pkglist[0]}" ] && \
    pkglist=( "$SR_PKGREPO"/"$itemdir"/*.t?z )
  # should have something by now!
  [ ! -e "${pkglist[0]}" ] && \
    { log_error -a "${itemid}: Can't find any packages to install"; return 1; }

  for pkgpath in "${pkglist[@]}"; do
    pkgbase=$(basename "$pkgpath" | sed 's/\.t.z$//')
    pkgid=$(echo "$pkgbase" | rev | cut -f4- -d- | rev )
    is_installed "$pkgpath"
    istat=$?
    if [ "$istat" = 0 ]; then
      # already installed, same version/arch/build/tag
      log_verbose -a "$R_INSTALLED is already installed"
      KEEPINSTALLED[$pkgid]="$pkgbase"
    elif [ "$istat" = 2 ]; then
      # nothing similar currently installed
      if [ "$OPT_VERBOSE" = 'y' -o "$OPT_INSTALL" = 'y' ]; then
        set -o pipefail
        ${SUDO}installpkg --terse "$pkgpath" 2>&1 | tee -a "$MAINLOG" "$ITEMLOG"
        pstat=$?
        set +o pipefail
      else
        ${SUDO}installpkg --terse "$pkgpath" >> "$ITEMLOG" 2>&1
        pstat=$?
      fi
      [ "$pstat" = 0 ] || { log_error -a "${itemid}: installpkg $pkgbase failed (status $stat)"; return 1; }
      dotprofilizer "$pkgpath"
      [ "$OPT_INSTALL" = 'y' -o "${HINT_INSTALL[$itemid]}" = 'y' ] && KEEPINSTALLED[$pkgid]="$pkgbase"
    else
      # istat=1 (already installed, different version/arch/build/tag)
      # or istat=3 (broken /var/log/packages) or istat=whatever
      [ "$istat" = 1 ] && log_normal -a "Upgrading $R_INSTALLED ..."
      [ "$istat" = 3 ] && log_warning -n "Attempting to upgrade or reinstall $R_INSTALLED ..."
      if [ "$OPT_VERY_VERBOSE" = 'y' ]; then
        set -o pipefail
        ${SUDO}upgradepkg --reinstall "$pkgpath" 2>&1 | tee -a "$ITEMLOG"
        pstat=$?
        set +o pipefail
      else
        ${SUDO}upgradepkg --reinstall "$pkgpath" >> "$ITEMLOG" 2>&1
        pstat=$?
      fi
      [ "$pstat" = 0 ] || { log_error -a "${itemid}: upgradepkg $pkgbase failed (status $stat)"; return 1; }
      dotprofilizer "$pkgpath"
      KEEPINSTALLED[$pkgid]="$pkgbase"
    fi
  done
  return 0
}

#-------------------------------------------------------------------------------

function uninstall_packages
# Run removepkg, and do extra cleanup
# Usage: uninstall_packages [-f] itemid
#   -f = (optionally) force uninstall. This is intended for use prior to building.
#        (Many packages don't build properly if a prior version is installed.)
# Return status: always 0
# If KEEPINSTALLED[pkgid] is set, the package WILL NOT be removed UNLESS -f is specified.
# If there is an install hint, the packages WILL NOT be removed UNLESS -f is specified.
# If OPT_INSTALL is set, the packages WILL be removed.
# Extra cleanup is only performed for 'vanilla' uninstalls.
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local force='n'
  if [ "$1" = '-f' ]; then
    force='y'
    shift
  fi

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local -a pkglist
  local pkgpath
  local etcnewfiles etcdirs etcfile etcdir

  # Don't remove a package that has an install hint, unless -f was specified.
  [ "${HINT_INSTALL[$itemid]}" = 'y' -a "$force" != 'y' ] && return 0

  # Look for the package(s).
  # Start with the temp output dir
  [ -n "$MYTMPOUT" ] && \
    pkglist=( "$MYTMPOUT"/*.t?z )
  # If nothing there, look in the dryrun repo
  [ ! -e "${pkglist[0]}" -a "$OPT_DRY_RUN" = 'y' ] &&
    pkglist=( "$DRYREPO"/"$itemdir"/*.t?z )
  # Finally, look in the proper package repo
  [ ! -e "${pkglist[0]}" ] && \
    pkglist=( "$SR_PKGREPO"/"$itemdir"/*.t?z )
  # should have something by now!
  [ ! -e "${pkglist[0]}" ] && \
    # there's nothing in the repo, so synthesize a package name
    pkglist=( "${itemprgnam}-0-noarch-0" )

  for pkgpath in "${pkglist[@]}"; do
    is_installed "$pkgpath"
    istat=$?
    if [ "$istat" = 2 ]; then
      # Not installed, carry on quietly
      continue
    else

      pkgbase=$(basename "$pkgpath" | sed 's/\.t.z$//')
      pkgid=$(echo "$pkgbase" | rev | cut -f4- -d- | rev )
      # Don't remove a package flagged with KEEPINSTALLED, unless -f was specified.
      [ -n "${KEEPINSTALLED[$pkgid]}" -a "$force" != 'y' ] && continue

      if [ "$OPT_INSTALL" = 'y' ] || [ -n "${KEEPINSTALLED[$pkgid]}" ] || \
         [ "$force" = 'y' ] || [ "${HINT_INSTALL[$itemid]}" = 'y' ]; then
        # Conventional gentle removepkg :-)
        log_normal -a "Uninstalling $R_INSTALLED ..."
        ${SUDO}removepkg "$R_INSTALLED" >> "$ITEMLOG" 2>&1
      else
        # Violent removal :D
        # Save a list of potential detritus in /etc
        etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/"$R_INSTALLED")
        etcdirs=$(grep '^etc/.*/$' /var/log/packages/"$R_INSTALLED")
        # Run removepkg
        log_verbose -a "Uninstalling $R_INSTALLED ..."
        #### if very verbose, we should really splurge this
        ${SUDO}removepkg "$R_INSTALLED" >> "$ITEMLOG" 2>&1
        # Remove any surviving detritus (do nothing if not root)
        for etcfile in $etcnewfiles; do
          rm -f /"$etcfile" /"${etcfile%.new}"
        done
        for etcdir in $etcdirs; do
          if [ -d /"$etcdir" ]; then
            find /"$etcdir" -type d -depth -exec rmdir --ignore-fail-on-non-empty {} \;
          fi
        done
        # Do this last so it can mend things the package broke.
        # The cleanup hint can contain any required shell commands, for example:
        #   * Reinstalling Slackware packages that conflict with the item's packages
        #   * Unsetting environment variables set in an /etc/profile.d script
        #   * Removing specific files and directories that removepkg doesn't remove
        #   * Running depmod to remove references to removed kernel modules
        # But it can destroy live config, so don't do it if 
        if [ -n "${HINT_CLEANUP[$itemid]}" ]; then
          eval "${SUDO}${HINT_CLEANUP[$itemid]}" >> "$ITEMLOG" 2>&1
        fi
      fi
    fi
  done

  return 0
}

#-------------------------------------------------------------------------------

function is_installed
# Check whether a package is currently installed
# $1 = pathname of a package file
# Sets the installed package name/version/arch/build in R_INSTALLED
# Return status:
# 0 = installed, with same version/arch/build/tag
# 1 = installed, but with different version/arch/build/tag
# 2 = not installed
# 3 = /var/log/packages is broken (multiple packages)
{
  local pkgbase=$(basename "$1" | sed 's/\.t.z$//')
  local pkgid=$(echo "$pkgbase" | rev | cut -f4- -d- | rev )
  R_INSTALLED=''
  if ls /var/log/packages/"$pkgid"-* 1>/dev/null 2>/dev/null; then
    for instpkg in /var/log/packages/"$pkgid"-*; do
      instid=$(basename "$instpkg" | rev | cut -f4- -d- | rev)
      if [ "$instid" = "$pkgid" ]; then
        if [ -n "$R_INSTALLED" ]; then
          log_warning "Your /var/log/packages is broken."
          log_warning -n "Please review these files:"
          log_warning -n "  $instpkg"
          log_warning -n "  /var/log/packages/$R_INSTALLED"
          return 3
        fi
        R_INSTALLED="$(basename "$instpkg")"
      elif [ "${instid%-upgraded}" != "$instid" ]; then
        log_warning "Your /var/log/packages is broken."
        log_warning -n "Please review these files:"
        log_warning -n "  $instpkg"
      fi
    done
    [ "$R_INSTALLED" = "$pkgbase" ] && return 0
    [ -n "$R_INSTALLED" ] && return 1
  fi
  return 2
}

#-------------------------------------------------------------------------------

function dotprofilizer
# Execute the /etc/profile.d scriptlets that came with a specific package
# $1 = path of package
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local pkgpath="$1"
  local varlogpkg script
  # examine /var/log/packages/xxxx because it's quicker than looking inside a .t?z
  varlogpkg=/var/log/packages/$(basename "${pkgpath/%.t?z/}")
  if grep -q -E '^etc/profile\.d/.*\.sh(\.new)?' "$varlogpkg"; then
    while read script; do
      if [ -f /"$script" ]; then
        log_verbose -a "  Running profile script: /$script"
        . /"$script"
      elif [ -f /"$script".new ]; then
        log_verbose -a "  Running profile script: /$script.new"
        . /"$script".new
      fi
    done < <(grep '^etc/profile\.d/.*\.sh' "$varlogpkg" | sed 's/.new$//')
  fi
  return
}
