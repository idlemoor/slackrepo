#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# cmdfunctions.sh - command functions for slackrepo
#   restore_item
#   remove_item
#-------------------------------------------------------------------------------

function restore_item
# Restore an item's package(s) from the backup repository
# $1 = itemid
# Return status:
# 0 = ok
# 1 = backups not configured
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  if [ -z "$SR_PKGBACKUP" ]; then
    log_error ":-/ No backups! Please set PKGBACKUP in your config file /-:"
    return 1
  fi

  log_warning ":-/ $itemid would be restored [not yet implemented] /-:"
  return 0
}

#-------------------------------------------------------------------------------

function remove_item
# Remove an item's package(s) from the package repository and the source repository
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  if [ -d "$SR_PKGREPO"/"$itemdir" ]; then
    [ "$OPT_DRY_RUN" != 'y' ] && rm -f "$SR_PKGREPO"/"$itemdir"/.revision
    pkglist=( $(ls "$SR_PKGREPO"/"$itemdir"/*.t?z 2>/dev/null) )
    if [ "${#pkglist[@]}" = 0 ] ; then
      log_normal "There is nothing in $SR_PKGREPO/$itemdir"
    else
      for pkg in "${pkglist[@]}"; do
        pkgbase=$(basename "$pkg")
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          log_normal "Removing package $pkgbase"
          rm "$pkg"
          db_del_buildsecs "$itemid"
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
    echo "$itemid: Removed. NEWLINE" >> "$CHANGELOG"
    log_success ":-) $itemid: Removed (-:"
  else
    log_success ":-) $itemid would be removed [dry run] (-:"
  fi
  OKLIST+=( "$itemid" )

  return 0
}
