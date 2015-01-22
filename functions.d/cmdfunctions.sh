#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# cmdfunctions.sh - command functions for slackrepo
#   build_item   (see also build_item_packages in buildfunctions.sh)
#   rebuild_item
#   update_item
#   revert_item
#   remove_item
#-------------------------------------------------------------------------------

function build_item
# Recursively build all dependencies, and then build the named item
# $1 = itemid
# Return status:
# 0 = build ok, or already up-to-date so not built, or dry run
# 1 = build failed, or sub-build failed => abort parent, or any other error
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2
  [ -z "$1" ] && return 1

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  local mydeplist mydep

  calculate_deps "$itemid" || return 1

  mydeplist=( ${DIRECTDEPS[$itemid]} )
  if [ "${#mydeplist[@]}" != 0 ]; then
    log_verbose "Dependencies of $itemid:"
    log_verbose "$(printf '  %s\n' "${mydeplist[@]}")"
    for mydep in "${mydeplist[@]}"; do
      build_item $mydep || return 1
    done
  fi

  needs_build "$itemid" || return 0

  buildopt=''
  [ "$OPT_DRY_RUN" = 'y' ] && buildopt=' [dry run]'
  [ "$OPT_INSTALL" = 'y' ] && buildopt=' [install]'
  log_itemstart "Starting $itemid ($BUILDINFO)$buildopt"

  build_item_packages "$itemid"
  myresult=$?

  # Now we can return
  if [ $myresult = 0 ]; then
    return 0
  else
    if [ "$itemid" != "$ITEMID" ]; then
      log_error -n ":-( $ITEMID ABORTED )-:"
      ABORTEDLIST+=( "$ITEMID" )
    fi
    return 1
  fi

}

#-------------------------------------------------------------------------------

function rebuild_item
# Implements the 'rebuild' command (by calling build_item)
# $1 = itemid
# Return status:
# 0 = ok, anything else = whatever was returned by build_item
{
  build_item "${1:-$ITEMID}"
  return $?
}

#-------------------------------------------------------------------------------

function update_item
# Implements the 'update' command:
# build or rebuild an item that exists, or remove packages for an item that doesn't exist
# $1 = itemid
# Return status:
# 0 = ok, anything else = whatever was returned by build_item or remove_item
{
  if [ -d "$SR_SBREPO"/"$itemdir"/ ]; then
    build_item "${1:-$ITEMID}"
    return $?
  else
    remove_item "${1:-$ITEMID}"
    return $?
  fi
}

#-------------------------------------------------------------------------------

function revert_item
# Revert an item's package(s) and source from the backup repository
# (and send the current packages and source into the backup repository)
# $1 = itemid
# Return status:
# 0 = ok
# 1 = backups not configured
# Problems: (1) messes up build number, (2) messes up deps & dependers
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

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

  # Check that there is something to revert.
  failmsg=":-( $itemid revert failed )-:"
  [ "$OPT_DRY_RUN" = 'y' ] && failmsg=":-( $itemid: revert failed [dry run] )-:"
  if [ -z "$SR_PKGBACKUP" ]; then
    log_error "No backup repository configured -- please set PKGBACKUP in your config file"
    log_error "$failmsg"
    return 1
  elif [ ! -d "$backupdir" ]; then
    log_error "$itemid has no backup packages to be reverted"
    log_error "$failmsg"
    return 1
  else
    for f in "$backupdir"/*.t?z; do
      [ -f "$f" ] && break
      log_error "$itemid has no backup packages to be reverted"
      log_error "$failmsg"
      return 1
    done
  fi

  # Log a warning about any dependencies
  if [ -f "$backuprevfile" ]; then
    while read b_itemid b_depid b_deplist b_version b_built b_rev b_os b_hintcksum ; do
      if [ "${b_depid}" = '/' ]; then
        mybuildtime="${b_built}"
      else
        deprevdata=( $(db_get_rev "${b_depid}") )
        if [ "${deprevdata[2]}" -gt "$mybuildtime" ]; then
          log_warning "${b_depid} may need to be reverted"
        fi
      fi
    done < "$backuprevfile"
  else
    log_error "There is no revision file in $backupdir"
    log_error "$failmsg"
    return 1
  fi
  # Log a warning about any dependers
  dependers=$(db_get_dependers "$itemid")
  for depender in $dependers; do
    log_warning "$depender may need to be rebuilt or reverted"
  done
  # Log a warning about any packages that are installed
  packagelist=( "$packagedir"/*.t?z )
  if [ -f "${packagelist[0]}" ]; then
    for pkg in "${packagelist[@]}"; do
      is_installed "$pkg"
      istat=$?
      if [ "$istat" = 0 -o "$istat" = 1 ]; then
        log_warning "$R_INSTALLED is installed, use removepkg to uninstall it"
      fi
    done
  fi

  if [ "$OPT_DRY_RUN" != 'y' ]; then
    # Actually perform the reversion!
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
    while read revinfo; do
      db_set_rev $revinfo
    done < "$backuprevfile"
    rm "$backuprevfile"
    # revert the previous package
    # (we already know that this exists, so no need for a test)
    mv "$backupdir" "$packagedir"
    # give the new backup its proper name
    if [ -d "$backuptempdir" ]; then
      mv "$backuptempdir" "$backupdir"
    fi
    # Finished!
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
    log_success ":-) $itemid: Reverted (-:"
  else
    log_success ":-) $itemid: Reverted [dry run] (-:"
  fi

  OKLIST+=( "$itemid" )
  return 0
}

#-------------------------------------------------------------------------------

function remove_item
# Move an item's source, package(s) and metadata to the backup.
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="${1:-$ITEMID}"
  local itemdir="${ITEMDIR[$itemid]}"
  local packagedir="$SR_PKGREPO"/"$itemdir"
  local allsourcedir="$SR_SRCREPO"/"$itemdir"
  local archsourcedir="$allsourcedir"/"$SR_ARCH"

  # Preliminary warnings and comments:
  # Log a warning if there will be no backup
  if [ -z "$SR_PKGBACKUP" ]; then
    log_warning "No backup repository configured -- please set PKGBACKUP in your config file"
  fi
  # Log a warning about any dependers
  dependers=$(db_get_dependers "$itemid")
  for depender in $dependers; do
    log_warning "$depender may need to be removed or rebuilt"
  done
  # Log a comment if the packages don't exist
  packagelist=( "$packagedir"/*.t?z )
  if [ ! -f "${packagelist[0]}" ]; then
    log_normal "There are no packages in $packagedir"
  fi
  # Log a warning about any packages that are installed
  for pkg in "${packagelist[@]}"; do
    is_installed "$pkg"
    istat=$?
    if [ "$istat" = 0 -o "$istat" = 1 ]; then
      log_warning "$R_INSTALLED is installed, use removepkg to uninstall it"
    fi
  done

  # Backup and/or remove
  if [ -n "$SR_PKGBACKUP" ]; then

    # Move any packages to the backup
    backupdir="$SR_PKGBACKUP"/"$itemdir"
    if [ -d "$packagedir" ]; then
      if [ "$OPT_DRY_RUN" != 'y' ]; then
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
      find "$archsourcedir" -type f -maxdepth 1 -print | while read srcpath; do
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
      find "$allsourcedir" -type f -maxdepth 1 -print | while read srcpath; do
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
      find "$archsourcedir" -type f -maxdepth 1 -print | while read srcpath; do
        srcfile="$(basename "$srcpath")"
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          rm "$srcpath"
          log_normal "Source file $srcfile has been removed"
        else
          log_normal "Source file $srcfile would be removed"
        fi
      done
    elif [ -d "$allsourcedir" ]; then
      find "$allsourcedir" -type f -maxdepth 1 -print | while read srcpath; do
        srcfile="$(basename "$srcpath")"
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          rm "$srcpath"
          log_normal "Source file $srcfile has been removed"
        else
          log_normal "Source file $srcfile would be removed"
        fi
      done
    fi

  fi

  # Remove the package directory and any empty parent directories
  # (don't bother with the source directory)
  if  [ "$OPT_DRY_RUN" != 'y' ]; then
    rm -rf "$SR_PKGREPO"/"$itemdir"
    up="$(dirname "$itemdir")"
    [ "$up" != '.' ] && rmdir --parents --ignore-fail-on-non-empty "$SR_PKGREPO"/"$up"
  fi

  # Delete the revision data
  db_del_rev "$itemid"

  # Changelog, and exit with a smile
  if [ "$OPT_DRY_RUN" != 'y' ]; then
    changelog "$itemid" "Removed" "" "${pkglist[@]}"
    log_success ":-) $itemid: Removed (-:"
  else
    log_success ":-) $itemid: Removed [dry run] (-:"
  fi
  OKLIST+=( "$itemid" )

  return 0

}
