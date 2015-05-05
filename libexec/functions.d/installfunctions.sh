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
  local itemid="$1"
  local mydep

  if [ -n "${FULLDEPS[$itemid]}" ]; then
    [ "$OPT_CHROOT" != 'y' ] && log_normal -a "Uninstalling dependencies ..."
    for mydep in ${FULLDEPS[$itemid]}; do
      uninstall_packages "$mydep"
    done
  fi
  return 0
}

#-------------------------------------------------------------------------------

function install_packages
# Run installpkg if the package is not already installed
# $* = itemids and/or package pathnames
# Return status:
# 0 = installed ok or already installed
# 1 = any install failed or not found (bail out after first error)
{
  local arg
  for arg in $*; do

    if [ -f "$arg" ]; then
      pkgbase="${arg##*/}"
      pkgnam="${pkgbase%-*-*-*}"
      local -a pkgnams=( "$pkgnam" )
      local -a pkglist=( "$arg" )
      local itemid=$(db_get_pkgnam_itemid "${pkgnams[0]}")
    else
      local itemid="$arg"
      local itemdir="${ITEMDIR[$itemid]}"
      [ -z "$itemdir" ] && { log_error -a "install_packages cannot find item ${itemid}"; return 1; }
      local -a pkgnams=( $(db_get_itemid_pkgnams "$itemid") )
      local -a pkglist=()
      for pn in "${pkgnams[@]}"; do
        # Don't look in MYTMPOUT (if you want that, specify them as pathnames)
        if [ "$OPT_DRY_RUN" = 'y' ]; then
          for p in "$DRYREPO"/"$itemdir"/"${pn}"-*.t?z; do
            if [ -e "$p" ]; then
              # cross-check p's pkgnam against pn (e.g. the geany/geany-plugins problem)
              ppb="${p##*/}"
              ppn="${ppb%-*-*-*}"
              [ "$ppn" = "$pn" ] && pkglist+=( "$p" )
            fi
          done
        fi
        if [ "${#pkglist[@]}" = 0 ]; then
          for p in "$SR_PKGREPO"/"$itemdir"/"${pn}"-*.t?z; do
            if [ -e "$p" ]; then
              ppb="${p##*/}"
              ppn="${ppb%-*-*-*}"
              [ "$ppn" = "$pn" ] && pkglist+=( "$p" )
            fi
          done
        fi
      done
      if [ "${#pkglist[@]}" = 0 ]; then
        log_error -a "${itemid}: Can't find any packages to install"
        # if the packages have gone, we'd better wipe the db entries
        db_del_rev "${itemid}"
        db_del_itemid_pkgnam "$itemid"
        return 1
      fi
    fi

    if [ -n "${HINT_GROUPADD[$itemid]}" ] || [ -n "${HINT_USERADD[$itemid]}" ]; then
      log_info -a "Adding groups and users:"
      if [ -n "${HINT_GROUPADD[$itemid]}" ]; then
        log_info -a "  ${HINT_GROUPADD[$itemid]}"
        eval $(echo "${HINT_GROUPADD[$itemid]}" | sed "s#groupadd #${CHROOTCMD}${SUDO}groupadd #g")
      fi
      if [ -n "${HINT_USERADD[$itemid]}" ]; then
        log_info -a "  ${HINT_USERADD[$itemid]}"
        eval $(echo "${HINT_USERADD[$itemid]}" | sed "s#useradd #${CHROOTCMD}${SUDO}useradd #g")
      fi
    fi

    for pkgpath in "${pkglist[@]}"; do
      pkgbase="${pkgpath##*/}"
      pkgid="${pkgbase%.t?z}"
      pkgnam="${pkgbase%-*-*-*}"
      is_installed "$pkgpath"
      istat=$?
      if [ "$istat" = 0 ]; then
        # already installed, same version/arch/build/tag
        log_normal -a "$R_INSTALLED is already installed"
        KEEPINSTALLED[$pkgnam]="$pkgid"
      elif [ "$istat" = 2 ]; then
        # nothing similar currently installed
        set -o pipefail
        ROOT=${CHROOTDIR:-/} ${SUDO}installpkg --terse "$pkgpath" 2>&1 | tee -a "$MAINLOG" "$ITEMLOG"
        pstat=$?
        set +o pipefail
        [ "$pstat" = 0 ] || { log_error -a "${itemid}: installpkg $pkgbase failed (status $pstat)"; return 1; }
        dotprofilizer "$pkgpath"
        [ "$OPT_INSTALL" = 'y' -o "${HINT_INSTALL[$itemid]}" = 'y' ] && KEEPINSTALLED[$pkgnam]="$pkgid"
      else
        # istat=1 (already installed, different version/arch/build/tag)
        # or istat=3 (broken /var/log/packages) or istat=whatever
        [ "$istat" = 1 ] && log_normal -a "Upgrading $R_INSTALLED ..."
        [ "$istat" = 3 ] && log_warning -n "Attempting to upgrade or reinstall $R_INSTALLED ..."
        if [ "$OPT_VERBOSE" = 'y' ]; then
          set -o pipefail
          ROOT=${CHROOTDIR:-/} ${SUDO}upgradepkg --reinstall "$pkgpath" 2>&1 | tee -a "$ITEMLOG"
          pstat=$?
          set +o pipefail
        else
          ROOT=${CHROOTDIR:-/} ${SUDO}upgradepkg --reinstall "$pkgpath" >> "$ITEMLOG" 2>&1
          pstat=$?
        fi
        [ "$pstat" = 0 ] || { log_error -a "${itemid}: upgradepkg $pkgbase failed (status $pstat)"; return 1; }
        dotprofilizer "$pkgpath"
        KEEPINSTALLED[$pkgnam]="$pkgid"
      fi
    done

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
# If KEEPINSTALLED[pkgnam] is set, the package WILL NOT be removed UNLESS -f is specified.
# If there is an install hint, the packages WILL NOT be removed UNLESS -f is specified.
# If OPT_INSTALL is set, the packages WILL be removed.
# Extra cleanup is only performed for 'vanilla' uninstalls.
# If OPT_CHROOT is set, the packages will not be removed, but a bit of cleanup will be done.
{

  local force='n'
  if [ "$1" = '-f' ]; then
    force='y'
    shift
  fi

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"
  local -a pkglist
  local pkgpath
  local etcnewfiles etcdirs etcfile etcdir

  if [ "$OPT_CHROOT" = 'y' ]; then
    # don't bother uninstalling, the chroot has already been destroyed
    # just cherry pick 'depmod' out of the cleanup hints
    if [ -n "${HINT_CLEANUP[$itemid]}" ]; then
      IFS=';'
      for cleancmd in ${HINT_CLEANUP[$itemid]}; do
        if [ "${cleancmd:0:7}" = 'depmod ' ]; then
          eval "${SUDO}${cleancmd}" >> "$ITEMLOG" 2>&1
        elif [ "${cleancmd:0:6}" = 'unset ' ]; then
          eval "${cleancmd}"        >> "$ITEMLOG" 2>&1
        fi
      done
      unset IFS
    fi
    return 0
  fi

  # Don't remove a package that has an install hint, unless -f was specified.
  [ "${HINT_INSTALL[$itemid]}" = 'y' -a "$force" != 'y' ] && return 0

  # Look for the package(s).
  pkgnams=( $(db_get_itemid_pkgnams "$itemid") )

  for pkgnam in "${pkgnams[@]}"; do
    # we don't care about exact match so use a dummy -version-arch-build_tag
    is_installed "$pkgnam"-v-a-b_t
    istat=$?
    if [ "$istat" = 2 ]; then
      # Not installed, carry on quietly
      continue
    else
      # Don't remove a package flagged with KEEPINSTALLED, unless -f was specified.
      [ -n "${KEEPINSTALLED[$pkgnam]}" -a "$force" != 'y' ] && continue

      if [ "$OPT_INSTALL" = 'y' ] || [ -n "${KEEPINSTALLED[$pkgnam]}" ] || \
         [ "$force" = 'y' ] || [ "${HINT_INSTALL[$itemid]}" = 'y' ]; then
        # Conventional gentle removepkg :-)
        log_normal -a "Uninstalling $R_INSTALLED ..."
        ROOT=${CHROOTDIR:-/} ${SUDO}removepkg "$R_INSTALLED" >> "$ITEMLOG" 2>&1
      else
        # Violent removal :D
        # Save a list of potential detritus in /etc
        etcnewfiles=$(grep '^etc/.*\.new$' "${CHROOTDIR}"/var/log/packages/"$R_INSTALLED")
        etcdirs=$(grep '^etc/.*/$' "${CHROOTDIR}"/var/log/packages/"$R_INSTALLED")
        # Run removepkg
        log_normal -a "Uninstalling $R_INSTALLED ..."
        #### if very verbose, we should really splurge this
        ROOT=${CHROOTDIR:-/} ${SUDO}removepkg "$R_INSTALLED" >> "$ITEMLOG" 2>&1
        # Remove any surviving detritus (do nothing if not root)
        for etcfile in $etcnewfiles; do
          rm -f /"$etcfile" /"${etcfile%.new}" 2>/dev/null
        done
        for etcdir in $etcdirs; do
          if [ -d /"$etcdir" ]; then
            find /"$etcdir" -type d -depth -exec rmdir --ignore-fail-on-non-empty {} \; 2>/dev/null
          fi
        done
        # Do this last so it can mend things the package broke.
        # The cleanup hint can contain any required shell commands, for example:
        #   * Reinstalling Slackware packages that conflict with the item's packages
        #     (use the provided helper script: s_reinstall pkgnam...)
        #   * Unsetting environment variables set in an /etc/profile.d script
        #     (e.g. unset LD_PRELOAD)
        #   * Removing specific files and directories that removepkg doesn't remove
        #   * Running depmod to remove references to removed kernel modules
        #   * Running sed -i (e.g. to remove entries from /etc/shells, ld.so.conf)
        #   * Running ldconfig
        # Be very careful with semicolons, IFS splitting is dumb.
        if [ -n "${HINT_CLEANUP[$itemid]}" ]; then
          IFS=';'
          for cleancmd in ${HINT_CLEANUP[$itemid]}; do
            if [ "${cleancmd:0:6}" = 'unset ' ]; then
              # unset has to be run in this process (obvsly)
              eval "${cleancmd}" >> "$ITEMLOG" 2>&1
            else
              # Everything else will need sudo if you're not root.
              eval "${SUDO}${cleancmd}" >> "$ITEMLOG" 2>&1
            fi
          done
          unset IFS
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
  local pkgbase="${1##*/}"
  local pkgid="${pkgbase%.t?z}"
  local pkgnam="${pkgbase%-*-*-*}"
  R_INSTALLED=''
  if ls "${CHROOTDIR}"/var/log/packages/"$pkgnam"-* 1>/dev/null 2>/dev/null; then
    for instpkg in "${CHROOTDIR}"/var/log/packages/"$pkgnam"-*; do
      instid="${instpkg##*/}"
      instnam="${instid%-*-*-*}"
      if [ "$instnam" = "$pkgnam" ]; then
        if [ -n "$R_INSTALLED" ]; then
          log_warning "Your /var/log/packages is broken."
          log_warning -n "Please review these files:"
          log_warning -n "  $instpkg"
          log_warning -n "  /var/log/packages/$R_INSTALLED"
          return 3
        fi
        R_INSTALLED="$instid"
      elif [ "${instid%-upgraded}" != "$instid" ]; then
        log_warning "Your /var/log/packages is broken."
        log_warning -n "Please review these files:"
        log_warning -n "  $instpkg"
      fi
    done
    [ "$R_INSTALLED" = "$pkgid" ] && return 0
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
  local pkgpath="$1"
  local varlogpkg script
  # examine /var/log/packages/xxxx because it's quicker than looking inside a .t?z
  varlogpkg="${CHROOTDIR}"/var/log/packages/$(basename "${pkgpath/%.t?z/}")
  if grep -q -E '^etc/profile\.d/.*\.sh(\.new)?' "$varlogpkg"; then
    while read script; do
      if [ -f "${CHROOTDIR}"/"$script" ]; then
        log_info -a "  Running profile script: /$script"
        . "${CHROOTDIR}"/"$script"
      elif [ -f "${CHROOTDIR}"/"$script".new ]; then
        log_info -a "  Running profile script: /$script.new"
        . "${CHROOTDIR}"/"$script".new
      fi
    done < <(grep '^etc/profile\.d/.*\.sh' "$varlogpkg" | sed 's/.new$//')
  fi
  return
}
