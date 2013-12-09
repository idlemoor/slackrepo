#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# depfunctions.sh - dependency functions for sboggit:
#   list_direct_deps (not yet used)
#   build_with_deps (not yet used)
#   install_with_deps (not yet used)
#   uninstall_with_deps (not yet used)
#   dependublaster2000
#-------------------------------------------------------------------------------

function list_direct_deps
{
  local prg="$1"
  local deplist dep
  . $SB_REPO/*/$prg/$prg.info
  deplist="$REQUIRES"
  if [ -f $SB_HINTS/$me.moredeps ]; then
    moredeps="$(cat $SB_HINTS/$me.moredeps)"
    deplist="$deplist $moredeps"
  fi
  for dep in $deplist; do
    if [ $dep = '%README%' ]; then
      if [ -f $SB_HINTS/$me.readmedeps ]; then
        cat $SB_HINTS/$me.readmedeps
      else
        ####### complain (unhandled %README%)
        :
      fi
    else
      echo $rdep
    fi
  done
}

#-------------------------------------------------------------------------------

function build_with_deps
{
  local me="$1"
  local mydeplist="$(list_direct_deps $me)"
  for mydep in $mydeplist; do
    build_with_deps $mydep
  done
  for mydep in $mydeplist; do
    install_with_deps $mydep
  done
  build_package $me
  for mydep in $mydeplist; do
    uninstall_with_deps $mydep
  done
}

#-------------------------------------------------------------------------------

function install_with_deps
{
  local me="$1"
  :
}

#-------------------------------------------------------------------------------

function uninstall_with_deps
{
  local me="$1"
  :
}

#-------------------------------------------------------------------------------

function dependublaster2000
{
  local me="$1"
  local prevdep mydeps moredeps dep readmedep
  for prevdep in $DEPLIST; do
    if [ "$prevdep" = "$me" ]; then
      # if I'm already on the list, then my deps must also be on the list
      # so nothing to do :-)
      return 0
    fi
  done
  if [ ! -d $SB_REPO/*/$me ]; then
    echo_yellow "WARNING: Dependency $me not found in $SB_REPO"
    return 0  # carry on regardless ;-)
  fi
  if [ -f $SB_HINTS/$me.tar.gz ]; then
    echo "Hint: applying tarball for $me"
    ( cd $SB_REPO/*/$me/..; rm -rf $me/; tar xf $SB_HINTS/$me.tar.gz )
  fi
  . $SB_REPO/*/$me/$me.info
  # ok, ready to go!  First, add my deps:
  mydeps="$REQUIRES"
  if [ -f $SB_HINTS/$me.moredeps ]; then
    moredeps="$(cat $SB_HINTS/$me.moredeps)"
    echo "Hint: adding more deps: $moredeps"
    mydeps="$mydeps $moredeps"
  fi
  for dep in $mydeps; do
    if [ $dep = '%README%' ]; then
      if [ -f $SB_HINTS/$me.readmedeps ]; then
        echo "Hint: substituting '$(cat $SB_HINTS/$me.readmedeps)' for %README%"
        for readmedep in $(cat $SB_HINTS/$me.readmedeps); do 
          dependublaster2000 $readmedep
        done
      else
        echo_yellow "WARNING: %README% in $me.info but $SB_HINTS/$me.readmedeps not found"
      fi
    else
      dependublaster2000 $dep
    fi
  done
  # then add me:
  DEPLIST="$DEPLIST $me"
  return 0
}
