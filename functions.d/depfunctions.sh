#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# depfunctions.sh - dependency functions for slackrepo
#   list_direct_deps
#   build_with_deps
#   install_with_deps
#   uninstall_with_deps
#-------------------------------------------------------------------------------

function list_direct_deps
# Returns list of deps of a named item in global variable $DEPLIST
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  local dep deps deplist

  # If $DEPCACHE already has an entry for $itempath, just return that ;-)
  if [ "${DEPCACHE[$itempath]+yesitisset}" = 'yesitisset' ]; then
    DEPLIST="${DEPCACHE[$itempath]}"
    return 0
  fi

  deps="${INFOREQUIRES[$itempath]}"
  deplist=''
  for dep in $deps; do
    if [ $dep = '%README%' ]; then
      if [ "${HINT_readmedeps[$itempath]}" != '%NONE%' ]; then
        BLAME="$prgnam.readmedeps"
        parse_items -s ${HINT_readmedeps[$itempath]}
        unset BLAME
        deplist="$deplist $ITEMLIST"
      else
        log_warning "${itempath}: Unhandled %README% in $prgnam.info - please create $SR_HINTS/$itempath.readmedeps"
      fi
    else
      BLAME="$prgnam.info"
      parse_items -s $dep
      unset BLAME
      deplist="$deplist $ITEMLIST"
    fi
  done

  if [ "${HINT_optdeps[$itempath]}" != '%NONE%' ]; then
    BLAME="$prgnam.optdeps"
    parse_items -s ${HINT_optdeps[$itempath]}
    unset BLAME
    deplist="$deplist $ITEMLIST"
  fi

  # don't look at this, it's a horrible deduplicate and whitespace tidy,
  # plus an undocumented feature allowing commas as separators:
  DEPLIST="$(echo $deplist | sed 's/,/ /g' | tr -s '[:space:]' '\n' | sort -u | tr -s '[:space:]' ' ' | sed 's/ *$//')"
  # Remember it for later:
  DEPCACHE[$itempath]="$DEPLIST"
  return 0
}

#-------------------------------------------------------------------------------

function build_with_deps
# Recursively build all dependencies, and then build the named item
# $1 = itempath
# $2 = list of parents (for circular dep detection)
# Return status:
# 0 = build ok, or already up-to-date so not built, or dry run
# 1 = build failed, or sub-build failed => abort parent, or any other error
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  local parents="$2 $itempath"
  local mydeplist mydep
  local subresult revstatus op reason
  local allinstalled

  # Load up any hints
  parse_hints $itempath

  # Bail out if to be skipped, or unsupported/untested
  if [ "${HINT_skipme[$itempath]}" = 'y' ]; then
    SKIPPEDLIST="$SKIPPEDLIST $itempath"
    return 1
  elif ! check_arch_is_supported $itempath; then
    SKIPPEDLIST="$SKIPPEDLIST $itempath"
    return 1
  fi

  # Load up prgnam.info
  parse_info $itempath

  # First, get all my deps built
  list_direct_deps $itempath
  mydeplist="$DEPLIST"
  if [ -n "$mydeplist" ]; then
    log_normal "Dependencies of $itempath:"
    log_normal "$(echo $mydeplist | sed -e "s/ /\n  /g" -e 's/^ */  /')"
    for mydep in $mydeplist; do
      for p in $parents; do
        if [ "$mydep" = "$p" ]; then
          log_error "${itempath}: Circular dependency on $p found in $mydep"
          return 1
        fi
      done
      build_with_deps $mydep "$parents"
      subresult=$?
      if [ $subresult != 0 ]; then
        if [ "$itempath" = "$ITEMPATH" ]; then
          log_error -n "$ITEMPATH ABORTED"
          ABORTEDLIST="$ABORTEDLIST $ITEMPATH"
        fi
        return 1
      fi
    done
  fi

  # Next, work out whether I need to be built, updated or rebuilt
  get_rev_status $itempath
  revstatus=$?
  case $revstatus in
  0)  if [ "$itempath" = "$ITEMPATH" -a "$PROCMODE" = 'rebuild' ]; then
        OP='rebuild'; opmsg='rebuild'
      else
        if [ "$itempath" = "$ITEMPATH" ]; then
          log_important "$itempath is up-to-date."
        else
          log_normal "$itempath is up-to-date."
        fi
        return 0
      fi
      ;;
  1)  OP='build'
      opmsg="build version ${NEWVERSION:-${INFOVERSION[$itempath]}}"
      ;;
  2)  OP='update'
      shortrev="${GITREV[$itempath]:0:7}"
      [ "${GITDIRTY[$itempath]}" = 'y' ] && shortrev="$shortrev+dirty"
      opmsg="update for git $shortrev"
      ;;
  3)  OP='update'
      opmsg="update for version ${NEWVERSION:-${INFOVERSION[$itempath]}}"
      ;;
  4)  OP='rebuild'
      opmsg="rebuild for changed hints"
      ;;
  5)  OP='rebuild'
      opmsg="rebuild for updated deps"
      ;;
  6)  OP='rebuild'
      opmsg="rebuild for Slackware upgrade"
      ;;
  *)  log_error "${itempath}: Unrecognised revstatus=$revstatus"
      return 1
      ;;
  esac

  # Tweak the message for dryrun
  [ "$OPT_DRYRUN" = 'y' ] && opmsg="$opmsg --dry-run"

  # Now the real work starts :-)
  log_itemstart "Starting $itempath ($opmsg)"

  # Install all my deps
  if [ -n "$mydeplist" ]; then
    log_normal -a "Installing dependencies ..."
    allinstalled='y'
    for mydep in $mydeplist; do
      install_with_deps $mydep || allinstalled='n'
    done
    if [ "$allinstalled" = 'n' ]; then
      for mydep in $mydeplist; do
        uninstall_with_deps $mydep
      done
      return 1
    fi
  fi

  # Build me
  build_package $itempath
  myresult=$?

  # Even if build_package failed, uninstall all my deps
  if [ -n "$mydeplist" ]; then
    log_normal -a "Uninstalling dependencies ..."
    for mydep in $mydeplist; do
      uninstall_with_deps $mydep
    done
  fi

  # Now return if build_package failed
  [ $myresult != 0 ] && return 1

  # If build_package succeeded, do some housekeeping:
  create_metadata "$opmsg" $itempath $mydeplist
  # update the cached revision status
  REVCACHE[$itempath]=0

  return 0
}

#-------------------------------------------------------------------------------

function install_with_deps
# Recursive package install, bottom up for neatness :-)
# $1 = itempath
# Return status:
# 0 = all installs succeeded
# 1 = any install failed
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  local mydeplist mydep

  list_direct_deps $itempath
  mydeplist="$DEPLIST"
  errstat=0
  for mydep in $mydeplist; do
    install_with_deps $mydep || errstat=1 # but keep going
  done
  install_package $itempath || errstat=1
  return $errstat
}

#-------------------------------------------------------------------------------

function uninstall_with_deps
# Recursive package uninstall
# We'll be particularly O.C.D. by uninstalling from the top down :-)
# $1 = itempath
# Return status always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  local mydeplist mydep

  uninstall_package $itempath
  list_direct_deps $itempath
  mydeplist="$DEPLIST"
  for mydep in $mydeplist; do
    uninstall_with_deps $mydep
  done
  return
}
