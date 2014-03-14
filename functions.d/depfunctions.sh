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
      if [ -f $SR_HINTS/$itempath.readmedeps ]; then
        log_verbose "Hint: Using \"$(cat $SR_HINTS/$itempath.readmedeps)\" for %README% in $prgnam.info"
        BLAME="$prgnam.readmedeps"
        parse_items $(cat $SR_HINTS/$itempath.readmedeps)
        unset BLAME
        deplist="$deplist $ITEMLIST"
      else
        log_warning "${itempath}: Unhandled %README% in $prgnam.info - please create $SR_HINTS/$itempath.readmedeps"
      fi
    else
      BLAME="$prgnam.info"
      parse_items $dep
      unset BLAME
      deplist="$deplist $ITEMLIST"
    fi
  done

  if [ -f $SR_HINTS/$itempath.optdeps ]; then
    log_verbose "Hint: Adding optional deps: \"$(cat $SR_HINTS/$itempath.optdeps)\""
    BLAME="$prgnam.optdeps"
    parse_items $(cat $SR_HINTS/$itempath.optdeps)
    unset BLAME
    deplist="$deplist $ITEMLIST"
  fi

  # don't look at this, it's a horrible deduplicate and whitespace tidy
  DEPLIST="$(echo $deplist | tr -s '[:space:]' '\n' | sort -u | tr -s '[:space:]' ' ' | sed 's/ *$//')"
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
  local me="$1"
  local prgnam=${me##*/}
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

  # Surprisingly this is the ideal place to load up .info and cache it
  if [ "${INFOVERSION[$me]+yesitisset}" != 'yesitisset' ]; then
    unset VERSION DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH}
    . $SR_GITREPO/$me/$prgnam.info
    INFOVERSION[$me]="$VERSION"
    if [ -n "$(eval echo \$DOWNLOAD_$SR_ARCH)" ]; then
      SRCDIR[$me]=$SR_SRCREPO/$me/$SR_ARCH
      INFODOWNLIST[$me]="$(eval echo \$DOWNLOAD_$SR_ARCH)"
      INFOMD5LIST[$me]="$(eval echo \$MD5SUM_$SR_ARCH)"
    else
      SRCDIR[$me]=$SR_SRCREPO/$me
      INFODOWNLIST[$me]="$DOWNLOAD"
      INFOMD5LIST[$me]="$MD5SUM"
    fi
    INFOREQUIRES[$me]="$REQUIRES"
    GITREV[$me]="$(cd $SR_GITREPO/$me; git log -n 1 --format=format:%H .)"
    GITDIRTY[$me]="n"
    if [ -n "$(cd $SR_GITREPO/$me; git status -s .)" ]; then
      GITDIRTY[$me]="y"
    fi
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
        if [ "$me" = "$ITEMPATH" ]; then
          log_error -n "$ITEMPATH ABORTED"
          ABORTEDLIST="$ABORTEDLIST $ITEMPATH"
        fi
        return 1
      fi
    done
  fi

  # Next, work out whether I need to be added, updated or rebuilt
  get_rev_status $me $mydeplist
  revstatus=$?
  case $revstatus in
  0)  if [ "$me" = "$ITEMPATH" -a "$PROCMODE" = 'rebuild' ]; then
        OP='rebuild'; opmsg='rebuild'
      else
        if [ "$me" = "$ITEMPATH" ]; then
          log_important "$me is up-to-date."
        else
          log_normal "$me is up-to-date."
        fi
        return 0
      fi
      ;;
  1)  OP='add'
      opmsg="add version ${NEWVERSION:-${INFOVERSION[$me]}}"
      ;;
  2)  OP='update'
      shortrev="${GITREV[$me]:0:7}"
      [ "${GITDIRTY[$me]}" = 'y' ] && shortrev="$shortrev+dirty"
      opmsg="update for git $shortrev"
      ;;
  3)  OP='update'
      opmsg="update for version ${NEWVERSION:-${INFOVERSION[$me]}}"
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
  *)  log_error "${me}: Unrecognised revstatus=$revstatus"
      return 1
      ;;
  esac

  # Stop here if update --dry-run
  if [ "$PROCMODE" = 'update' -a "$OPT_DRYRUN" = 'y' ]; then
    opmsg="would be $(echo "$opmsg" | sed -e 's/^add /added /' -e 's/^update /updated /' -e 's/^rebuild /rebuilt /')"
    log_important "$me $opmsg"
    echo "$me $opmsg" >> $SR_UPDATEFILE
    return 0
  fi

  # Tweak the message for dryrun
  [ "$OPT_DRYRUN" = 'y' ] && opmsg="$opmsg --dry-run"

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
  create_metadata "$opmsg" $me $mydeplist
  # update the cached revision status
  REVCACHE[$me]=0

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
  local me="$1"
  local prgnam=${me##*/}
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
# $1 = itempath
# Return status always 0
{
  local me="$1"
  local prgnam=${me##*/}
  local mydeplist mydep

  uninstall_package $me
  list_direct_deps $me
  mydeplist="$DEPLIST"
  for mydep in $mydeplist; do
    uninstall_with_deps $mydep
  done
  return
}
