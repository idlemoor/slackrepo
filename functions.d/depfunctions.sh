#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# depfunctions.sh - dependency functions for slackrepo
#   calculate_deps
#   build_with_deps
#   install_deps
#   uninstall_deps
#-------------------------------------------------------------------------------

declare -A DIRECTDEPS FULLDEPS

function calculate_deps
# Stores a space-separated list of deps of an item in ${DIRECTDEPS[$itemname]}
# and ${FULLDEPS[$itemname]}
# $1 = itemid
# Return status:
# 0 = ok
# 1 = any error
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"

  # If FULLDEPS already has an entry for $itemid, do nothing
  # (note that *null* means "we have already calculated that the item has no deps",
  # whereas *unset* means "we have not yet calculated the deps of this item").
  if [ "${FULLDEPS[$itemid]+yesitisset}" = 'yesitisset' ]; then
    return 0
  fi

  parse_info_and_hints "$itemid" || return 1

  local dep
  local -a deplist

  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  for dep in ${INFOREQUIRES[$itemid]}; do
    if [ $dep = '%README%' ]; then
      log_warning "${itemid}: Unhandled %README% in $itemprgnam.info"
    else
      find_slackbuild "$dep"
      fstat=$?
      if [ $fstat = 0 ]; then
        deplist+=( "${R_SLACKBUILD}" )
      elif [ $fstat = 1 ]; then
        log_warning "${itemid}: Dependency $dep does not exist"
      elif [ $fstat = 2 ]; then
        log_warning "${itemid}: Dependency $dep matches more than one SlackBuild"
      fi
    fi
  done

  deplist=( $(printf '%s\n' "${deplist[@]}" | sort -u) )
  DIRECTDEPS["$itemid"]="${deplist[@]}"

  # If there are no direct deps, then there are no recursive deps ;-)
  if [ -z "${DIRECTDEPS[$itemid]}" ]; then
    FULLDEPS["$itemid"]=''
    return 0
  fi

  local -a myfulldeps

  for dep in "${deplist[@]}"; do
    calculate_deps "$dep" || return 1
    for newdep in ${FULLDEPS[$dep]} "$dep"; do
      gotnewdep='n'
      for olddep in "${myfulldeps[@]}"; do
        if [ "$newdep" = "$olddep" ]; then
          gotnewdep='y'
          break
        elif [ "$newdep" = "$itemid" ]; then
          log_error "${itemid}: Circular dependency via $dep"
          return 1
        fi
      done
      if [ "$gotnewdep" = 'n' ]; then
        myfulldeps+=( "$newdep" )
      fi
    done
  done
  FULLDEPS["$itemid"]="${myfulldeps[@]}"

  return 0
}

#-------------------------------------------------------------------------------

function build_with_deps
# Recursively build all dependencies, and then build the named item
# $1 = itemid
# Return status:
# 0 = build ok, or already up-to-date so not built, or dry run
# 1 = build failed, or sub-build failed => abort parent, or any other error
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  local mydeplist mydep
  local revstatus op reason
  local allinstalled

  calculate_deps "$itemid" || return 1

  mydeplist=( ${DIRECTDEPS["$itemid"]} )
  if [ "${#mydeplist[@]}" != 0 ]; then
    log_normal "Dependencies of $itemid:"
    log_normal "$(printf '  %s\n' "${mydeplist[@]}")"
    for mydep in "${mydeplist[@]}"; do
      build_with_deps $mydep || return 1
    done
  fi

  needs_build "$itemid" || return 0

  log_itemstart "Starting $itemid ($BUILDINFO)"

  build_item "$itemid"
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

function install_deps
# Install dependencies of $itemid (but NOT $itemid itself)
# $1 = itemid
# Return status:
# 0 = all installs succeeded
# 1 = any install failed
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local mydep

  if [ -n "${FULLDEPS[$itemid]}" ]; then
    log_normal -a "Uninstalling dependencies ..."
    for mydep in ${FULLDEPS[$itemid]}; do
      uninstall_packages "$mydep"
    done
  fi
  return 0
}
