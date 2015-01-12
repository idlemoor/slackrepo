#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# cmdfunctions.sh - command functions for slackrepo
#   revert_item
#   remove_item
#-------------------------------------------------------------------------------
# For build, rebuild and update commands, see build_with_deps in depfunctions.sh
# (and see also build_item in buildfunctions.sh)
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

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  packagedir="$SR_PKGREPO"/"$itemdir"
  backupdir="$SR_PKGBACKUP"/"$itemdir"
  backuptempdir="$backupdir".temp
  # We can't get these from parse_info_and_hints because the item's .info may have been removed:
  allsourcedir="$SR_SRCREPO"/"$itemdir"
  archsourcedir="$allsourcedir"/"$SR_ARCH"
  allsourcebackupdir="$backupdir"/source
  archsourcebackupdir="${allsourcebackupdir}_${SR_ARCH}"
  allsourcebackuptempdir="$backuptempdir"/source
  archsourcebackuptempdir="${allsourcebackuptempdir}_${SR_ARCH}"

  # Check that there is something to revert.
  failmsg=":-( $itemid: revert failed )-:"
  [ "$OPT_DRY_RUN" = 'y' ] && failmsg=":-( $itemid: revert failed [dry run] )-:"
  if [ -z "$SR_PKGBACKUP" ]; then
    log_error "No backup repository configured -- please set PKGBACKUP in your config file"
    log_error "$failmsg"
    return 1
  elif [ ! -d "$backupdir" ]; then
    log_error "There is no backup in $backupdir to be reverted"
    log_error "$failmsg"
    return 1
  else
    for f in "$backupdir"/*.t?z; do
      [ -f "$f" ] && break
      log_error "There are no backup packages in $SR_PKGBACKUP/$itemdir to be reverted"
      log_error "$failmsg"
      return 1
    done
  fi

  # Get the backup package's dependencies and warn if any direct deps are newer than the restored package
  for revfile in "$backupdir"/*.rev "$backupdir"/.revision ; do
    [ ! -f "$revfile" ] && continue
    pkgid=$(basename "$revfile" '.rev')
    myprgnam=''
    while read revfileline; do
      eval "$revfileline"
      # grab first line's details -- it's the rev info for this package
      if [ "$myprgnam" = '' ]; then
        myprgnam="$prgnam"; mybuildrev="$buildrev"; mybuildtime="$built";
      else
        if [ "$buildrev" != "$mybuildrev" ] && [ "$built" -gt "$mybuildtime" ]; then
          log_warning "${pkgid}: dependency $prgnam may need to be reverted"
        fi
      fi
    done < "$revfile"
  done
  # Log an unconditional warning about dependers
  log_warning "Any packages that depend on ${itemid} may need to be rebuilt or reverted"

  if [ "$OPT_DRY_RUN" != 'y' ]; then
    # Perform the reversion.

    # move the current package to a temporary backup directory
    if [ -d "$packagedir" ]; then
      mv "$packagedir" "$backuptempdir"
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

    # revert the previous package
    # (we already know that this exists, so no need for a test)
    mv "$backupdir" "$packagedir"
    # give the new backup its proper name
    if [ -d "$backuptempdir" ]; then
      mv "$backuptempdir" "$backupdir"
    fi

  fi

  # Log what happened:
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
# Move an item's package(s) and metadata from the package repository to the
# backup, and remove its stuff from the source repository.
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  if [ -d "$SR_PKGREPO"/"$itemdir" ]; then
    pkglist=( $(ls "$SR_PKGREPO"/"$itemdir"/*.t?z 2>/dev/null) )
    if [ "${#pkglist[@]}" = 0 ] ; then
      log_normal "There are no packages in $SR_PKGREPO/$itemdir"
    else
      #### need to backup
      for pkg in "${pkglist[@]}"; do
        pkgbase=$(basename "$pkg")
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          log_normal "Removing package $pkgbase"
          rm -f "${pkg%.t?z}".*
        else
          log_normal "Would remove package $pkgbase"
        fi
        is_installed "$pkg"
        istat=$?
        if [ "$istat" = 0 -o "$istat" = 1 -o "$istat" = 3 ]; then
          log_warning "Package $R_INSTALLED is installed, use removepkg to uninstall it"
        fi
      done
      changelog "$itemid" "Removed" "" "${pkglist[@]}"
    fi

    if [ "$OPT_DRY_RUN" != 'y' ]; then
      log_normal "Removing directory $SR_PKGREPO/$itemdir"
      rm -rf "$SR_PKGREPO"/"$itemdir"
      up="$(dirname "$itemdir")"
      [ "$up" != '.' ] && rmdir --parents --ignore-fail-on-non-empty "$SR_PKGREPO"/"$up"
    else
      log_normal "Would remove directory $SR_PKGREPO/$itemdir"
    fi
  fi

  if [ -d "$SR_SRCREPO"/"$itemdir" ]; then
    [ "$OPT_DRY_RUN" != 'y' ] && rm -f "$SR_SRCREPO"/"$itemdir"/.version
    srclist=( $(ls "$SR_SRCREPO"/"$itemdir"/* 2>/dev/null) )
    for src in "${srclist[@]}"; do
      if [ "$OPT_DRY_RUN" != 'y' ]; then
        log_normal "Removing source $(basename "$src")"
        rm "$src"
      else
        log_normal "Would remove source $(basename "$src")"
      fi
    done
    if [ "$OPT_DRY_RUN" != 'y' ]; then
      log_normal "Removing directory $SR_SRCREPO/$itemdir"
      rm -rf "$SR_SRCREPO"/"$itemdir"
      up="$(dirname "$itemdir")"
      [ "$up" != '.' ] && rmdir --parents --ignore-fail-on-non-empty "$SR_SRCREPO"/"$up"
    else
      log_normal "Would remove directory $SR_SRCREPO/$itemdir"
    fi
  fi

  if [ "$OPT_DRY_RUN" != 'y' ]; then
    log_success ":-) $itemid: Removed (-:"
  else
    log_success ":-) $itemid would be removed [dry run] (-:"
  fi
  OKLIST+=( "$itemid" )

  return 0
}
