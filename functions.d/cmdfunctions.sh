#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# cmdfunctions.sh - command functions for slackrepo
#   revert_item
#   remove_item
#-------------------------------------------------------------------------------

function revert_item
# Revert an item's package(s) from the backup repository
# $1 = itemid
# Return status:
# 0 = ok
# 1 = backups not configured
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  if [ -z "$SR_PKGBACKUP" ]; then
    log_error ":-( No backup repository configured -- please set PKGBACKUP in your config file )-:"
    return 1
  elif [ ! -d "$SR_PKGBACKUP"/"$itemid" ]; then
    log_error ":-( There is no backup copy of $itemid in $SR_PKGBACKUP )-:"
    return 1
  fi

  # save any existing packages to the backup repo with a temporary name
  if [ -d "$SR_PKGREPO"/"$itemdir" ]; then
    if [ "$OPT_DRY_RUN" != 'y' ]; then
      mv "$SR_PKGREPO"/"$itemdir" "$SR_PKGBACKUP"/"$itemdir".temp
      log_normal "These packages have been backed up:"
      log_normal "$(printf '  %s\n' "$(cd "$SR_PKGBACKUP"/"$itemdir".temp; ls *.t?z)")"
    else
      log_normal "These packages would be backed up:"
      log_normal "$(printf '  %s\n' "$(cd "$SR_PKGREPO"/"$itemdir"; ls *.t?z)")"
    fi
  fi
  # move the backup to the package repo
  if [ -d "$SR_PKGBACKUP"/"$itemdir" ]; then
    if [ "$OPT_DRY_RUN" != 'y' ]; then
      mv "$SR_PKGBACKUP"/"$itemdir" "$SR_PKGREPO"/"$itemdir"
      log_normal "These packages have been reverted:"
      log_normal "$(printf '  %s\n' "$(cd "$SR_PKGREPO"/"$itemdir"; ls *.t?z)")"
    else
      log_normal "These packages would be reverted:"
      log_normal "$(printf '  %s\n' "$(cd "$SR_PKGBACKUP"/"$itemdir"; ls *.t?z)")"
    fi
  fi
  # give the new backup its proper name
  if [ -d "$SR_PKGBACKUP"/"$itemdir".temp ]; then
    mv "$SR_PKGBACKUP"/"$itemdir".temp "$SR_PKGBACKUP"/"$itemdir"
  fi

  BUILDINFO='revert'
  create_pkg_metadata "$itemid"

  if [ "$OPT_DRY_RUN" != 'y' ]; then
    log_success ":-) $itemid: Reverted (-:"
  else
    log_success ":-) $itemid would be reverted [dry run] (-:"
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
      for pkg in "${pkglist[@]}"; do
        pkgbase=$(basename "$pkg")
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          log_normal "Removing package $pkgbase"
          rm -f "$(echo "$pkg" | sed 's/\.t.z$//')".*
          echo "$pkgbase:  Removed. NEWLINE" >> "$CHANGELOG"
        else
          log_normal "Would remove package $pkgbase"
        fi
        is_installed "$pkg"
        istat=$?
        if [ "$istat" = 0 -o "$istat" = 1 -o "$istat" = 3 ]; then
          log_warning "Package $R_INSTALLED is installed, use removepkg to uninstall it"
        fi
      done
    fi
    if [ "$OPT_DRY_RUN" != 'y' ]; then
      db_del_buildsecs "$itemid"
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
