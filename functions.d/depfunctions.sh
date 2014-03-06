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
# $1 = itemname
# Return status: always 0
{
  local itemname="$1"
  local prg=$(basename $itemname)
  local dep deps deplist

  # If $DEPCACHE already has an entry for $itemname, just return that ;-)
  if [ "${DEPCACHE[$itemname]+yesitisset}" = 'yesitisset' ]; then
    DEPLIST="${DEPCACHE[$itemname]}"
    return 0
  fi

  set -e
  . $SR_GITREPO/$itemname/$prg.info
  set +e
  deps="$REQUIRES"

  deplist=''
  for dep in $deps; do
    if [ $dep = '%README%' ]; then
      if [ -f $SR_HINTS/$itemname.readmedeps ]; then
        log_verbose "Hint: Using \"$(cat $SR_HINTS/$itemname.readmedeps)\" for %README% in $prg.info"
        BLAME="$prg.readmedeps"
        parse_items $(cat $SR_HINTS/$itemname.readmedeps)
        unset BLAME
        deplist="$deplist $ITEMLIST"
      else
        log_warning "${itemname}: Unhandled %README% in $prg.info - please create $SR_HINTS/$itemname.readmedeps"
      fi
    else
      BLAME="$prg.info"
      parse_items $dep
      unset BLAME
      deplist="$deplist $ITEMLIST"
    fi
  done

  if [ -f $SR_HINTS/$itemname.optdeps ]; then
    log_verbose "Hint: Adding optional deps: \"$(cat $SR_HINTS/$itemname.optdeps)\""
    BLAME="$prg.optdeps"
    parse_items $(cat $SR_HINTS/$itemname.optdeps)
    unset BLAME
    deplist="$deplist $ITEMLIST"
  fi

  # don't look at this, it's a horrible deduplicate and whitespace tidy
  DEPLIST="$(echo $deplist | tr -s '[:space:]' '\n' | sort -u | tr -s '[:space:]' ' ' | sed 's/ *$//')"
  # Remember it for later:
  DEPCACHE[$itemname]="$DEPLIST"
  return 0
}

#-------------------------------------------------------------------------------

function build_with_deps
# Recursively build all dependencies, and then build the named item
# $1 = itemname
# $2 = list of parents (for circular dep detection)
# Return status:
# 0 = build ok, or already up-to-date so not built, or dry run
# 1 = build failed, or sub-build failed => abort parent, or any other error
{
  local me="$1"
  local prg=$(basename $me)
  local parents="$2 $me"
  local mydeplist mydep
  local subresult revstatus op reason
  local allinstalled

  # Bail out if to be skipped, or unsupported/untested
  if hint_skipme $me; then
    SKIPPEDLIST="$SKIPPEDLIST $me"
    return 1
  elif ! check_arch_is_supported $me; then
    SKIPPEDLIST="$SKIPPEDLIST $me"
    return 1
  fi

  # First, get all my deps built
  list_direct_deps $me
  mydeplist="$DEPLIST"
  if [ -n "$mydeplist" ]; then
    log_normal "Dependencies of $me:"
    log_normal "$(echo $mydeplist | sed -e "s/ /\n  /g" -e 's/^ */  /')"
    for mydep in $mydeplist; do
      for p in $parents; do
        if [ "$mydep" = "$p" ]; then
          log_error "${me}: Circular dependency on $p found in $mydep"
          return 1
        fi
      done
      build_with_deps $mydep "$parents"
      subresult=$?
      if [ $subresult != 0 ]; then
        if [ "$me" = "$ITEMNAME" ]; then
          log_error -n "$ITEMNAME ABORTED"
          ABORTEDLIST="$ABORTEDLIST $ITEMNAME"
        fi
        return 1
      fi
    done
  fi

  # Next, work out whether I need to be added, updated or rebuilt
  get_rev_status $me $mydeplist
  revstatus=$?
  case $revstatus in
  0)  if [ "$me" = "$ITEMNAME" -a \( "$PROCMODE" = 'rebuild' -o "$PROCMODE" = 'test' \) ]; then
        OP='rebuild'; opmsg='rebuild'
      else
        log_normal "$me is up-to-date." ; return 0
      fi
      ;;
  1)  OP='add';     opmsg="add" ;;
  2|3)
      shortrev=$(cd $SR_GITREPO/$me; git log -n 1 --format=format:%h .)
      [ -n "$(cd $SR_GITREPO/$itemname; git status -s .)" ] && shortrev="$shortrev+dirty"
      OP='update';  opmsg="update for git $shortrev" ;;
  4)  OP='rebuild'; opmsg="rebuild for changed hints" ;;
  5)  OP='rebuild'; opmsg="rebuild for updated deps" ;;
  6)  OP='rebuild'; opmsg="rebuild for Slackware upgrade" ;;
  *)  log_error "${me}: Unrecognised revstatus=$revstatus"; return 1 ;;
  esac

  # Stop here if update --dry-run
  if [ "$UPDATEDRYRUN" = 'y' ]; then
    opmsg="would be $(echo "$opmsg" | sed -e 's/^add /added /' -e 's/^update /updated /' -e 's/^rebuild /rebuilt /')"
    log_important "$me $opmsg"
    echo "$me $opmsg" >> $SR_UPDATEFILE
    return 0
  fi

  # Tweak the message for test mode
  [ "$PROCMODE" = 'test' ] && opmsg="test $opmsg"

  # Now the real work starts :-)
  log_prgstart "Starting $me ($opmsg)"

  # Install all my deps
  if [ -n "$mydeplist" ]; then
    local logprg="$prg"
    log_normal "Installing dependencies ..."
    allinstalled='y'
    for mydep in $mydeplist; do
      install_with_deps $mydep || allinstalled='n'
    done
    [ "$allinstalled" = 'n' ] && return 1  ##### should we uninstall?
    unset logprg
  fi

  # Build me
  build_package $me
  myresult=$?

  # Even if build_package failed, uninstall all my deps
  if [ -n "$mydeplist" ]; then
    local logprg="$prg"
    log_normal "Uninstalling dependencies ..."
    for mydep in $mydeplist; do
      uninstall_with_deps $mydep
    done
    unset logprg
  fi

  # Now return if build_package failed
  [ $myresult != 0 ] && return 1

  # If build_package succeeded, do some housekeeping:
  # create .dep and .rev files
  create_metadata $OP $me $mydeplist
  # update the cached revision status
  REVCACHE[$me]=0

  return 0
}

#-------------------------------------------------------------------------------

function install_with_deps
# Recursive package install, bottom up for neatness :-)
# $1 = itemname
# Return status:
# 0 = all installs succeeded
# 1 = any install failed
{
  local me="$1"
  local prg=$(basename $me)
  local mydeplist mydep

  list_direct_deps $me
  mydeplist="$DEPLIST"
  errstat=0
  for mydep in $mydeplist; do
    install_with_deps $mydep || errstat=1 # but keep going
  done
  install_package $me || errstat=1
  return $errstat
}

#-------------------------------------------------------------------------------

function uninstall_with_deps
# Recursive package uninstall
# We'll be particularly O.C.D. by uninstalling from the top down :-)
# $1 = itemname
# Return status always 0
{
  local me="$1"
  local prg=$(basename $me)
  local mydeplist mydep

  uninstall_package $me
  list_direct_deps $me
  mydeplist="$DEPLIST"
  for mydep in $mydeplist; do
    uninstall_with_deps $mydep
  done
  return
}
