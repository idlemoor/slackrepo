#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# cmdfunctions.sh - command functions for slackrepo
#   revert_item
#   remove_item
#-------------------------------------------------------------------------------
# For build, rebuild and update commands, see build_with_deps in depfunctions.sh
# (and see also buildfunctions.sh)
#-------------------------------------------------------------------------------

function revert_item
# Revert an item's package(s) from the backup repository
# (and send the current packages into the backup repository)
# $1 = itemid
# Return status:
# 0 = ok
# 1 = backups not configured
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  failmsg=":-( $itemid: revert failed )-:"
  [ "$OPT_DRY_RUN" = 'y' ] && failmsg=":-( $itemid: revert failed [dry run] )-:"

  if [ -z "$SR_PKGBACKUP" ]; then
    log_error "No backup repository configured -- please set PKGBACKUP in your config file"
    log_error "$failmsg"
    return 1
  elif [ ! -d "$SR_PKGBACKUP"/"$itemdir" ]; then
    log_error "There is no backup in $SR_PKGBACKUP/$itemdir to be reverted"
    log_error "$failmsg"
    return 1
  else
    for f in "$SR_PKGBACKUP"/"$itemdir"/*.t?z; do
      [ -f "$f" ] && break
      log_error "There are no backup packages in $SR_PKGBACKUP/$itemdir to be reverted"
      log_error "$failmsg"
      return 1
    done
  fi

  if [ "$OPT_DRY_RUN" = 'y' ]; then

    gotfiles="n"
    for f in "$SR_PKGBACKUP"/"$itemdir"/*.t?z; do
      [ ! -f "$f" ] && break
      [ "$gotfiles" = 'n' ] && { gotfiles='y'; log_normal "These packages would be reverted:"; }
      log_normal "$(printf '  %s\n' "$(basename "$f")")"
    done
    gotfiles="n"
    for f in "$SR_PKGREPO"/"$itemdir"/*.t?z; do
      [ ! -f "$f" ] && break
      [ "$gotfiles" = 'n' ] && { gotfiles='y'; log_normal "These packages would be backed up:"; }
      log_normal "$(printf '  %s\n' "$(basename "$f")")"
    done
    log_success ":-) $itemid: Reverted [dry run] (-:"

  else

    # swap the package repo and backup repo
    if [ -d "$SR_PKGREPO"/"$itemdir" ]; then
      mv "$SR_PKGREPO"/"$itemdir" "$SR_PKGBACKUP"/"$itemdir".temp
    fi
    # we've already established this exists:
    mv "$SR_PKGBACKUP"/"$itemdir" "$SR_PKGREPO"/"$itemdir"
    # give the new backup its proper name
    if [ -d "$SR_PKGBACKUP"/"$itemdir".temp ]; then
      mv "$SR_PKGBACKUP"/"$itemdir".temp "$SR_PKGBACKUP"/"$itemdir"
    fi

    # log what's happened
    gotfiles="n"
    for f in "$SR_PKGREPO"/"$itemdir"/*.t?z; do
      [ ! -f "$f" ] && break
      [ "$gotfiles" = 'n' ] && { gotfiles='y'; log_normal "These packages have been reverted:"; }
      log_normal "$(printf '  %s\n' "$(basename "$f")")"
    done
    gotfiles="n"
    for f in "$SR_PKGBACKUP"/"$itemdir"/*.t?z; do
      [ ! -f "$f" ] && break
      [ "$gotfiles" = 'n' ] && { gotfiles='y'; log_normal "These packages have been backed up:"; }
      log_normal "$(printf '  %s\n' "$(basename "$f")")"
    done
    changelog "$itemid" "Reverted" "" "$SR_PKGREPO"/"$itemdir"/*.t?z
    log_success ":-) $itemid: Reverted (-:"

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
