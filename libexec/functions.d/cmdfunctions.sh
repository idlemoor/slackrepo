#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# cmdfunctions.sh - command functions for slackrepo
#   build_command   (see also build_item_packages in buildfunctions.sh)
#   rebuild_command
#   update_command
#   revert_command
#   remove_command
#   lint_command
#   info_command
#-------------------------------------------------------------------------------

function build_command
# Build an item and all its dependencies
# $1 = itemid
# Return status:
# 0 = build ok, or already up-to-date so not built, or preview, or dry run
# 1 = build failed, or sub-build failed => abort parent, or any other error
{
  [ -z "$1" ] && return 1

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  TODOLIST=()
  if [ -z "${STATUS[$itemid]}" ]; then
    log_normal "Calculating dependencies ... "
    DEPTREE=""
    calculate_deps_and_status "$itemid"
    if [ "${DIRECTDEPS[$itemid]}" = "" ]; then
      log_done "none."
    else
      log_normal "Dependency tree:"
      echo -n "$DEPTREE"
    fi
    log_normal ""
  elif [ "${STATUS[$itemid]}" = 'ok' ] || [ "${STATUS[$itemid]}" = 'updated' ]; then
    STATUS[$itemid]="ok"
    for depid in ${FULLDEPS[$itemid]}; do
      [ "${STATUS[$depid]}" = 'updated' ] && STATUS[$depid]='ok'
    done
    if [ "$CMD" = 'rebuild' ]; then
      found='n'
      for previously in "${OKLIST[@]}"; do
        if [ "$previously" = "$itemid" ]; then found='y'; break; fi
      done
      if [ "$found" = 'n' ]; then
        STATUS[$itemid]="rebuild"
        STATUSINFO[$itemid]="rebuild"
        TODOLIST=( "$itemid" )
      fi
    fi
  fi

  if [ "${OPT_PREVIEW}" = 'y' ]; then
    case "${STATUS[$itemid]}" in
      ok)
        log_important "$itemid is up-to-date (version ${INFOVERSION[$itemid]})." ;;
      add)
        log_important "$itemid would be added (version ${INFOVERSION[$itemid]})." ;;
      update)
        log_important "$itemid would be updated (version ${INFOVERSION[$itemid]})." ;;
      rebuild)
        log_important "$itemid would be rebuilt (version ${INFOVERSION[$itemid]})." ;;
      remove)
        log_important "$itemid would be removed (version ${INFOVERSION[$itemid]})." ;;
      skipped)
        log_important "$itemid would not be built." ;;
      aborted|unsupported)
        log_important "$itemid can not be built." ;;
      *)
        : ;;
    esac
    log_normal ""
    return 0
  fi

  if [ "${#TODOLIST[@]}" = 0 ]; then
    # Nothing is going to be built.  Log the final outcome.
    if [ "${STATUS[$itemid]}" = 'ok' ]; then
      # we still need to process --install
      log_important "$itemid is up-to-date (version ${INFOVERSION[$itemid]})."
      if [ "${HINT_INSTALL[$itemid]}" = 'y' ] || [ "$OPT_INSTALL" = 'y' -a "${HINT_INSTALL[$itemid]}" != 'n' ]; then
        log_normal ""
        CMD='install' log_itemstart "$itemid" "Installing $itemid"
        install_deps "$itemid" || { log_error "Failed to install dependencies of $itemid"; return 1; }
        install_packages "$itemid" || { log_error "Failed to install $itemid"; return 1; }
        log_important "Installing finished."
      fi
    elif [ "${STATUS[$itemid]}" = 'removed' ]; then
      log_important "$itemid has been removed."
    elif [ "${STATUS[$itemid]}" = 'skipped' ]; then
      log_warning -n "$itemid has been skipped."
    elif [ "${STATUS[$itemid]}" = 'unsupported' ]; then
      log_warning -n "$itemid is unsupported on ${SR_ARCH}."
    elif [ "${STATUS[$itemid]}" = 'failed' ]; then
      log_error "${itemid} has failed to build."
      [ -n "${STATUSINFO[$itemid]}" ] && log_normal "${STATUSINFO[$itemid]}"
    elif [ "${STATUS[$itemid]}" = 'aborted' ]; then
      log_error "Cannot build ${itemid}."
      [ -n "${STATUSINFO[$itemid]}" ] && log_normal "${STATUSINFO[$itemid]}"
    else
      log_warning -n "$itemid has unexpected status ${STATUS[$itemid]}"
    fi
    log_normal ""
  else
    # Process TODOLIST.
    for todo in "${TODOLIST[@]}"; do
      if [ "${STATUS[$todo]}" = 'removed' ]; then
        log_itemfinish "$todo" 'removed' '' "${STATUSINFO[$todo]}"
      elif [ "${STATUS[$todo]}" = 'skipped' ]; then
        log_itemfinish "$todo" 'skipped' '' "${STATUSINFO[$todo]}"
      elif [ "${STATUS[$todo]}" = 'unsupported' ]; then
        log_itemfinish "$todo" 'unsupported' "on ${SR_ARCH}" ''
      elif [ "${STATUS[$todo]}" = 'failed' ]; then
        log_error "${todo} has failed to build."
        [ -n "${STATUSINFO[$todo]}" ] && log_normal "${STATUSINFO[$todo]}"
        log_normal ""
      elif [ "${STATUS[$todo]}" = 'remove' ]; then
        remove_command "$todo"
        STATUS[$todo]='removed'
      else
        missingdeps=()
        unsupporteddeps=()
        for dep in ${DIRECTDEPS[$todo]}; do
          if [ "${STATUS[$dep]}" != 'ok' ] && [ "${STATUS[$dep]}" != 'updated' ]; then
            if [ "${STATUS[$dep]}" = 'unsupported' ] ; then
              unsupporteddeps+=( "$dep" )
            else
              missingdeps+=( "$dep" )
            fi
          fi
        done
        if [ "${#missingdeps[@]}" = '0' ] && [ "${#unsupporteddeps[@]}" = '0' ] ; then
          build_item_packages "$todo"
        else
          log_error "Cannot build ${todo}."

          if [ "${#missingdeps[@]}" = '1' ] && [ "${#unsupportedeps[@]}" = '0' ] ; then
            STATUSINFO[$todo]="Missing dependency: ${missingdeps[0]}"
          elif [ "${#missingdeps[@]}" = '0' ] && [ "${#unsupportedeps[@]}" = '1' ] ; then
            STATUSINFO[$todo]="Unsupported dependency: ${unsupporteddeps[0]}"
          else
            STATUSINFO[$todo]="Missing dependencies:\n$(printf '  %s\n' "${missingdeps[@]}")\nUnsupported dependencies:\n$(printf '  %s\n' "${unsupporteddeps[@]}")"
          fi

          if [ "${#unsupporteddeps[@]}" = '0' ] ; then
            STATUS[$todo]='aborted'
            log_itemfinish "$todo" "aborted" '' "${STATUSINFO[$todo]}"
          else
            STATUS[$todo]='unsupported'
            log_itemfinish "$todo" "unsupported" '' "${STATUSINFO[$todo]}"
          fi
        fi
      fi
    done
  fi

  return 0
}

#-------------------------------------------------------------------------------

function rebuild_command
# Implements the 'rebuild' command (by calling build_command)
# $1 = itemid
# Return status:
# 0 = ok, anything else = whatever was returned by build_command
{
  build_command "${1:-$ITEMID}"
  return $?
}

#-------------------------------------------------------------------------------

function update_command
# Implements the 'update' command:
# build or rebuild an item that exists, or remove packages for an item that doesn't exist
# $1 = itemid
# Return status:
# 0 = ok, anything else = whatever was returned by build_command or remove_command
{
  local itemid="${1:-$ITEMID}"
  local itemdir="${ITEMDIR[$itemid]}"
  if [ -n "$itemdir" ] && [ -d "$SR_SBREPO"/"$itemdir"/ ]; then
    build_command "$itemid"
    return $?
  else
    remove_command "$itemid"
    return $?
  fi
}

#-------------------------------------------------------------------------------

function revert_command
# Revert an item's package(s) and source from the backup repository
# (and send the current packages and source into the backup repository)
# $1 = itemid
# Return status:
# 0 = ok
# 1 = backups not configured
# Problems: (1) messes up build number, (2) messes up deps & dependers
{
  local itemid="${1:-$ITEMID}"
  local itemdir="${ITEMDIR[$itemid]}"

  packagedir="$SR_PKGREPO"/"$itemdir"
  backupdir="$SR_PKGBACKUP"/"$itemdir"
  backuprevfile="$backupdir"/revision
  backuptempdir="$backupdir".temp
  backuptemprevfile="$backuptempdir"/revision
  # We can't get these from parse_info_and_hints because the item's .info may have been removed:
  allsourcedir="$SR_SRCREPO"/"$itemdir"
  archsourcedir="$allsourcedir"/"$SR_ARCH"
  allsourcebackupdir="$backupdir"/source
  archsourcebackupdir="${allsourcebackupdir}_${SR_ARCH}"
  allsourcebackuptempdir="$backuptempdir"/source
  archsourcebackuptempdir="${allsourcebackuptempdir}_${SR_ARCH}"

  #### IMPORTANT #### repopulate 'packages' table after revert

  log_itemstart "$itemid"

  # Check that there is something to revert.
  extramsg=''
  [ "$OPT_DRY_RUN" = 'y' ] && extramsg="[dry run]"
  # preview is the same as dry run
  [ "$OPT_PREVIEW" = 'y' ] && extramsg="[preview]" && OPT_DRY_RUN='y'
  if [ -z "$SR_PKGBACKUP" ]; then
    log_error "No backup repository configured -- please set PKGBACKUP in your config file"
    log_itemfinish "$itemid" 'failed' "$extramsg"
    return 1
  elif [ ! -d "$backupdir" ]; then
    log_error "$itemid has no backup packages to be reverted"
    log_itemfinish "$itemid" 'failed' "$extramsg"
    return 1
  else
    for f in "$backupdir"/*.t?z; do
      [ -f "$f" ] && break
      log_error "$itemid has no backup packages to be reverted"
      log_itemfinish "$itemid" 'failed' "$extramsg"
      return 1
    done
  fi

  # Log a warning about any dependencies
  if [ -f "$backuprevfile" ]; then
    while read -r b_itemid b_depid b_deplist b_version b_built b_rev b_os b_hintcksum ; do
      if [ "${b_depid}" = '/' ]; then
        mybuildtime="${b_built}"
      else
        deprevdata=( $(db_get_rev "${b_depid}") )
        if [ "${deprevdata[2]:-0}" -gt "$mybuildtime" ]; then
          log_warning -s "${b_depid} may need to be reverted"
        fi
      fi
    done < "$backuprevfile"
  else
    log_error "There is no revision file in $backupdir"
    log_itemfinish "$itemid" 'failed' "$extramsg"
    return 1
  fi
  # Log a warning about any dependers
  dependers=$(db_get_dependers "$itemid")
  for depender in $dependers; do
    log_warning -s "$depender may need to be rebuilt or reverted"
  done
  # Log a warning about any packages that are installed
  packagelist=( "$packagedir"/*.t?z )
  if [ -f "${packagelist[0]}" ]; then
    for pkg in "${packagelist[@]}"; do
      is_installed "$pkg"
      istat=$?
      if [ "$istat" = 0 ] || [ "$istat" = 1 ]; then
        log_warning -s "$R_INSTALLED is installed, use removepkg to uninstall it"
      fi
    done
  fi

  if [ "$OPT_DRY_RUN" != 'y' ]; then
    # Actually perform the reversion!
    # With big packages this might take a while, so log a message
    log_normal "Reverting $itemid ... "
    # move the current package to a temporary backup directory
    if [ -d "$packagedir" ]; then
      mv "$packagedir" "$backuptempdir"
    else
      mkdir -p "$backuptempdir"
    fi
    # save the revision data to the revision file (in the temp dir)
    revdata=$(db_get_rev "$itemid")
    echo "$itemid / $revdata" > "$backuptemprevfile"
    if [ "${revdata[0]}" != '/' ]; then
      for depid in ${revdata[0]//,/ }; do
        echo "$itemid $depid $(db_get_rev "$itemid" "$depid")" >> "$backuptemprevfile"
      done
    fi
    # move the source files (for the correct arch) into a subdir of the temporary backup dir
    if [ -d "$archsourcedir" ]; then
      mkdir -p "$archsourcebackuptempdir"
      find "$archsourcedir" -type f -maxdepth 1 -exec mv {} "$archsourcebackuptempdir" \;
    elif [ -d "$allsourcedir" ]; then
      mkdir -p "$allsourcebackuptempdir"
      find "$allsourcedir" -type f -maxdepth 1 -exec mv {} "$allsourcebackuptempdir" \;
    fi
    # revert the previous source
    if [ -d "$archsourcebackupdir" ]; then
      mkdir -p "$archsourcedir"
      find "$archsourcebackupdir" -type f -maxdepth 1 -exec mv {} "$archsourcedir" \;
    elif [ -d "$allsourcebackupdir" ]; then
      mkdir -p "$allsourcedir"
      find "$allsourcebackupdir" -type f -maxdepth 1 -exec mv {} "$allsourcedir" \;
    fi
    # replace the current revision data with the previous revision data
    db_del_rev "$itemid"
    while read -r revinfo; do
      db_set_rev $revinfo
    done < "$backuprevfile"
    rm -f "$backuprevfile"
    # revert the previous package
    # (we already know that this exists, so no need for a test)
    mv "$backupdir" "$packagedir"
    # give the new backup its proper name
    if [ -d "$backuptempdir" ]; then
      mv "$backuptempdir" "$backupdir"
    fi
    # Finished!
    log_done
  fi

  # Log what happened, or what would have happened:
  # setup the messages
  if [ "$OPT_DRY_RUN" != 'y' ]; then
    revertlist=( "$packagedir"/*.t?z )
    backuplist=( "$backupdir"/*.t?z )
    action='have been'
  else
    revertlist=( "$backupdir"/*.t?z )
    backuplist=( "$packagedir"/*.t?z )
    action='would be'
  fi
  # print the messages
  gotfiles="n"
  for f in "${backuplist[@]}"; do
    [ ! -f "$f" ] && break
    [ "$gotfiles" = 'n' ] && { gotfiles='y'; log_normal "These packages $action backed up:"; }
    log_normal "$(printf '  %s\n' "$(basename "$f")")"
  done
  gotfiles="n"
  for f in "${revertlist[@]}"; do
    [ ! -f "$f" ] && break
    [ "$gotfiles" = 'n' ] && { gotfiles='y'; log_normal "These packages $action reverted:"; }
    log_normal "$(printf '  %s\n' "$(basename "$f")")"
  done
  if [ "$OPT_DRY_RUN" != 'y' ]; then
    changelog "$itemid" "Reverted" "" "$packagedir"/*.t?z
    log_itemfinish "$itemid" 'ok' "Reverted"
  else
    log_itemfinish "$itemid" 'ok' "Reverted [dry run]"
  fi

  return 0
}

#-------------------------------------------------------------------------------

function remove_command
# Move an item's source, package(s) and metadata to the backup.
# $1 = itemid
# Return status: always 0
{
  local itemid="${1:-$ITEMID}"
  local itemdir="${ITEMDIR[$itemid]}"
  local packagedir="$SR_PKGREPO"/"$itemdir"
  local allsourcedir="$SR_SRCREPO"/"$itemdir"
  local archsourcedir="$allsourcedir"/"$SR_ARCH"

  # Preliminary messages:
  if [ "$itemid" = "$ITEMID" ]; then
    log_itemstart "$itemid"
    if [ "${STATUS[$itemid]}" = 'removed' ] || [ -z "$itemdir" ] || [ ! -d "$SR_SBREPO"/"$itemdir"/ ]; then
      log_important "$itemid has been removed."
      log_normal ""
      return 0
    fi
    # Log a warning about any dependers, unless this is happening within another item
    dependers=$(db_get_dependers "$itemid")
    for depender in $dependers; do
      log_warning -s "$depender may need to be removed or rebuilt"
    done
  else
    removeopt=''
    [ "$OPT_DRY_RUN" = 'y' ] && removeopt=' [dry run]'
    # preview is the same as dry run
    [ "$OPT_PREVIEW" = 'y' ] && removeopt=" [preview]" && OPT_DRY_RUN='y'
    log_itemstart "$itemid" "Removing $itemid$removeopt"
  fi
  # Log a comment if the packages don't exist
  packagelist=( "$packagedir"/*.t?z )
  if [ ! -f "${packagelist[0]}" ]; then
    log_normal "There are no packages in $packagedir"
  fi
  # Log a warning about any packages that are installed
  for pkg in "${packagelist[@]}"; do
    is_installed "$pkg"
    istat=$?
    if [ "$istat" = 0 ] || [ "$istat" = 1 ]; then
      log_warning -s "$R_INSTALLED is installed, use removepkg to uninstall it"
    fi
  done

  # Backup and/or remove
  if [ -n "$SR_PKGBACKUP" ]; then

    # Move any packages to the backup
    backupdir="$SR_PKGBACKUP"/"$itemdir"
    if [ -d "$packagedir" ]; then
      if [ "$OPT_DRY_RUN" != 'y' ]; then
        [ -d "$backupdir" ] && rm -rf "$backupdir"
        # move the whole package directory to the backup directory
        mkdir -p "$(dirname "$backupdir")"
        mv "$packagedir" "$backupdir"
        # save revision data to the revision file (in the backup directory)
        revdata=( $(db_get_rev "$itemid") )
        backuprevfile="$backupdir"/revision
        echo "$itemid" "/" "${revdata[@]}" > "$backuprevfile"
        if [ "${revdata[0]}" != '/' ]; then
          for depid in ${revdata[0]//,/ }; do
            echo "$itemid $depid $(db_get_rev "$itemid" "$depid")" >> "$backuprevfile"
          done
        fi
        # log what's been done:
        for pkg in "$backupdir"/*.t?z; do
          [ -f "$pkg" ] && log_normal "Package $(basename "$pkg") has been backed up and removed"
        done
      else
        # do nothing, except log what would be done:
        for pkg in "$packagedir"/*.t?z; do
          [ -f "$pkg" ] && log_normal "Package $(basename "$pkg") would be backed up and removed"
        done
      fi
    fi

    # Move any source to the backup
    if [ -d "$archsourcedir" ]; then
      archsourcebackupdir="${allsourcebackupdir}_${SR_ARCH}"
      [ "$OPT_DRY_RUN" != 'y' ] && mkdir -p "$archsourcebackupdir"
      find "$archsourcedir" -type f -maxdepth 1 -print | while read -r srcpath; do
        srcfile="$(basename "$srcpath")"
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          mv "$srcpath" "$archsourcebackupdir"
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile has been backed up and removed"
        else
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile would be backed up and removed"
        fi
      done
    elif [ -d "$allsourcedir" ]; then
      allsourcebackupdir="$backupdir"/source
      [ "$OPT_DRY_RUN" != 'y' ] && mkdir -p "$allsourcebackupdir"
      find "$allsourcedir" -type f -maxdepth 1 -print | while read -r srcpath; do
        srcfile="$(basename "$srcpath")"
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          mv "$srcpath" "$allsourcebackupdir"
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile has been backed up and removed"
        else
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile would be backed up and removed"
        fi
      done
    fi

  else

    # Can't backup packages and/or source, so just remove them
    for pkg in "${packagelist[@]}"; do
      if [ -f "$pkg" ]; then
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          rm -f "$pkg" "${pkg%.t?z}".*
          log_normal "Package $pkg has been removed"
        else
          log_normal "Package $pkg would be removed"
        fi
      fi
    done
    if [ -d "$archsourcedir" ]; then
      find "$archsourcedir" -type f -maxdepth 1 -print | while read -r srcpath; do
        srcfile="$(basename "$srcpath")"
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          rm -f "$srcpath"
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile has been removed"
        else
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile would be removed"
        fi
      done
    elif [ -d "$allsourcedir" ]; then
      find "$allsourcedir" -type f -maxdepth 1 -print | while read -r srcpath; do
        srcfile="$(basename "$srcpath")"
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          rm -f "$srcpath"
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile has been removed"
        else
          [ "$srcfile" != '.version' ] && log_normal "Source file $srcfile would be removed"
        fi
      done
    fi

  fi

  if  [ "$OPT_DRY_RUN" != 'y' ]; then
    # Remove the package directory and any empty parent directories
    # (don't bother with the source directory)
    rm -rf "${SR_PKGREPO:?NotSetSR_PKGREPO}/${itemdir}"
    up="$(dirname "$itemdir")"
    [ "$up" != '.' ] && rmdir --parents --ignore-fail-on-non-empty "${SR_PKGREPO}/${up}"
    # Delete the revision and package name data
    db_del_rev "$itemid"
    db_del_itemid_pkgnam "$itemid"
  fi

  # Changelog, and exit with a smile
  if [ "$OPT_DRY_RUN" != 'y' ]; then
    changelog "$itemid" "Removed" "" "${packagelist[@]}"
    log_itemfinish "$itemid" 'ok' "Removed"
  else
    log_itemfinish "$itemid" 'ok' "Removed [dry run]"
  fi
  OKLIST+=( "$itemid" )

  return 0

}

#-------------------------------------------------------------------------------

function lint_command
# Test an item without building or installing it
# $1 = itemid
# Return status: always 0
{
  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  log_itemstart "$itemid"
  parse_info_and_hints "$itemid"
  if [ $? != 0 ]; then
    if [ "${STATUS[$itemid]}" = "unsupported" ]; then
      log_itemfinish "$itemid" "unsupported" "on ${SR_ARCH}"
    elif [ "${STATUS[$itemid]}" = "skipped" ]; then
      log_itemfinish "$itemid" "skipped" ""
    else
      log_itemfinish "$itemid" "${STATUS[$itemid]}" ''
    fi
    return 0
  fi

  tsbstat=0
  if [ "${OPT_LINT_SB:-y}" = 'y' ]; then
    test_slackbuild "$itemid"
    tsbstat=$?
  fi

  tdlstat=0
  if [ "${OPT_LINT_DL:-y}" = 'y' ]; then
    test_download "$itemid"
    tdlstat=$?
  fi

  tpkgstat=0
  if [ "${OPT_LINT_PKG:-y}" = 'y' ]; then
    pstat=''
    for pkgnam in $(db_get_itemid_pkgnams "$itemid"); do
      pkgpathlist=( "${SR_PKGREPO}"/"$itemdir"/"$pkgnam"-*-*-*.t?z )
      for pkgpath in "${pkgpathlist[@]}"; do
        if [ -f "$pkgpath" ]; then
          # Note, we can't test-install a package without its deps, so we don't use 'test_package -i'
          test_package "$itemid" "$pkgpath"
          pstat=$?
          [ "$pstat" -gt "$tpkgstat" ] && tpkgstat="$pstat"
        fi
      done
    done
    [ -z "$pstat" ] && log_important -a "No packages found."
  fi

  log_normal -a ""
  if [ "$tsbstat" = 0 ] && [ "$tdlstat" = 0 ] && [ "$tpkgstat" = 0 ]; then
    log_itemfinish "$itemid" "ok" "lint OK"
  elif [ "$tsbstat" -le 1 ] && [ "$tdlstat" -le 1 ] && [ "$tpkgstat" -le 1 ]; then
    log_itemfinish "$itemid" "warning" "lint completed with warnings"
  else
    log_itemfinish "$itemid" "failed" "lint"
  fi

  return 0
}

#-------------------------------------------------------------------------------

function info_command
# Print version, configuration and debugging information on standard output
# This is called without initialising the repo, so don't use log_xxxx
{

  # Show slackrepo version
  echo ""
  print_version
  echo ""

  # Show the system info
  echo "$(hostname)"
  osver="${SYS_OSVER}"
  [ "${SYS_CURRENT}" = 'y' ] && osver="current"
  echo "  OS: ${SYS_OSNAME}-${osver}"
  echo "  kernel: ${SYS_KERNEL}"
  echo "  arch: ${SYS_ARCH}"
  [ "$SYS_MULTILIB" = 'y' ] && echo "  multilib: yes"
  echo "  nproc: ${SYS_NPROC}"
  echo "  total MHz: ${SYS_MHz}"
  [ "$SYS_OVERLAYFS" = 'y' ] && echo "  overlayfs: yes"
  [ "$EUID" != 0 ] && echo "  username: $USER"
  echo ""

  # Show which config files exist
  echo "Configuration files"
  for configfile in ~/.slackreporc ~/.genreprc /etc/slackrepo/slackrepo_"${OPT_REPO}".conf; do
    if [ -f "$configfile" ]; then
      echo "  $configfile  [found]"
    else
      echo "  $configfile  [not found]"
    fi
  done
  echo ""

  # Show the options
  echo "Configuration options and variables"
  echo "  --repo=$OPT_REPO"
  if [ "$OPT_VERY_VERBOSE" = 'y' ]; then
    echo "  --very-verbose"
  elif [ "$OPT_VERBOSE" = 'y' ]; then
    echo "  --verbose"
  fi
  [      "$OPT_PREVIEW" = 'y' ] && echo "  --preview"
  [      "$OPT_DRY_RUN" = 'y' ] && echo "  --dry-run"
  [      "$OPT_INSTALL" = 'y' ] && echo "  --install"
  [        "$OPT_LINT" != 'n' ] && echo "  --lint=$OPT_LINT"
  [     "$OPT_KEEP_TMP" = 'y' ] && echo "  --keep-tmp"
  [      "$OPT_CHROOT" != 'n' ] && echo "  --chroot=$OPT_CHROOT"
  [    "$OPT_COLOR" != 'auto' ] && echo "  --color=$OPT_COLOR"
  [        "$OPT_NICE" != '5' ] && echo "  --nice=$OPT_NICE"
  [ "$OPT_REPRODUCIBLE" = 'y' ] && echo "  --reproducible"
  [   "$OPT_NOWARNING" != ''  ] && echo "  --nowarning=$OPT_NOWARNING"

  # Show the variables
  for name in $varnames; do
    srvar="SR_$name"
    case "$srvar" in
      *REPO | *DIR | SR_DATABASE )
        if [ -e "${!srvar}" ]; then
          echo "  $name=\"${!srvar}\""
        else
          echo "  $name=\"${!srvar}\"  [not found]"
        fi
        ;;
      SR_PKGBACKUP )
        if [ -n "$SR_PKGBACKUP" ]; then
          if [ -e "${!srvar}" ]; then
            echo "  $name=\"${!srvar}\""
          else
            echo "  $name=\"${!srvar}\"  [not found]"
          fi
        else
          echo "  $name=\"${!srvar}\""
        fi
        ;;
      * )
        echo "  $name=\"${!srvar}\""
        ;;
    esac
  done
  if [ "$SR_USE_GENREPOS" = 1 ]; then
    for name in $genrepnames; do
      srvar="SR_$name"
      if [ -n "${!srvar}" ]; then
        if [ "$srvar" = 'SR_REPOSROOT' ]; then
          if [ -e "${!srvar}" ]; then
            echo "  $name=\"${!srvar}\""
          else
            echo "  $name=\"${!srvar}\"  [not found]"
          fi
        else
          echo "  $name=\"${!srvar}\""
        fi
      fi
    done
    [ -z "$SR_RSS_UUID" ] && echo "  RSS_UUID=\"\"  [not valid]"
  else
    echo "  USE_GENREPOS=\"$SR_USE_GENREPOS\""
  fi
  echo ""

  # Show the repository info
  if [ -d "$SR_SBREPO" ]; then
    cd "$SR_SBREPO"
    if [ -d ".git" ]; then
      [ -n "$(git status -s .)" ] && dirty=' (DIRTY)'
      echo "git repo:   $SR_SBREPO"
      echo "  branch:   $(git rev-parse --abbrev-ref HEAD)"
      echo "  date:     $(date --date=@$(git log -n 1 --format=%ct))"
      echo "  revision: $(git rev-parse HEAD)$dirty"
      echo "  title:    $(git log -n 1 --format=%s)"
    elif [ -n "$(ls -A 2>/dev/null)" ]; then
      echo "SlackBuild repo: $SR_SBREPO is not a git repository."
    else
      echo "SlackBuild repo: $SR_SBREPO is uninitialised."
    fi
    echo ""
  fi

  # Show significant environment variables. This is not a comprehensive list (see
  # https://www.gnu.org/software/make/manual/html_node/Implicit-Variables.html)
  # and upstream builds don't always use them properly.
  for name in AR AS CC CFLAGS CXX CXXFLAGS CPP CPPFLAGS LD LDFLAGS DISTCC_HOSTS; do
    [ -n "${!name}" ] && echo "  $name=\"${!name}\""
  done
  echo ""

  return 0
}
