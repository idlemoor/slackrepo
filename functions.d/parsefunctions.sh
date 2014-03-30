#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# parsefunctions.sh - parse functions for slackrepo
#   parse_items
#   parse_package_name
#-------------------------------------------------------------------------------

function parse_items
# Parse item names
# $1 = -s => look up in SlackBuild repo, or -p => look up in Package repo
# $* = the item names to be parsed :-)
#    - can be <prgnam>, or <directory>/.../<prgnam>
#    - any number of directories are supported
#    - if <prgnam> is unambiguous, directories can be omitted
# Also uses $BLAME which the caller can set for extra info in errors and warnings
# Returns canonical [<directory>/]<prgnam> name (or names) in $ITEMLIST
# and populates associative arrays with values from the .info file:
# INFOVERSION INFODOWNLIST INFOMD5LIST INFOREQUIRES
# Return status:
# 0 = all ok
# 1 = any item not found
# 9 = existential crisis
{
  ITEMLIST=''
  errstat=0
  local blamemsg=''
  [ -n "$BLAME" ] && blamemsg="${BLAME}: "

  if [ "$1" = '-s' ]; then
    SEARCHFILE='.SlackBuild'
    TOPLEVEL="$SR_SBREPO"
  elif [ "$1" = '-p' ]; then
    SEARCHFILE='-*.t?z'
    TOPLEVEL="$SR_PKGREPO"
  else
    log_error "parse_items: invalid argument '$1'"
    return 9
  fi

  while [ $# != 0 ]; do

    local item="${1##/}"
    a=$(echo "$item/" | cut -f1 -d/)
    b=$(echo "$item/" | cut -f2 -d/)
    shift

    # We can have zero, one, or two names in $a and $b.
    if [ -z "$a" -a -n "$b" ]; then
      # this can't happen due to '${1##/}' above, but if it *does* happen,
      # put the only name we've got in $a and make $b empty:
      a="$b"; b=''
    fi

    if [ -z "$a" -a -z "$b" ]; then
      # zero names supplied
      log_warning "$(basename $0): ${blamemsg}Empty item specified"
      errstat=1
      continue
    fi

    if [ -z "$b" ]; then
      # one name supplied
      if [ -f $TOPLEVEL/$a/$a$SEARCHFILE ]; then
        # one-level repo, exact match :-)
        ITEMLIST="$ITEMLIST $a"
      else
        # is it a prog in a two-level repo?
        progcount=$(ls $TOPLEVEL/*/$a/$a$SEARCHFILE 2>/dev/null | wc -l)
        if [ $progcount = 1 ]; then
          # two-level repo, one matching prog :-)
          ITEMLIST="$ITEMLIST $(cd $TOPLEVEL/*/$a/..; basename $(pwd))/$a"
        elif [ $progcount != 0 ]; then
          log_warning "${blamemsg}Multiple matches for $a in $TOPLEVEL, please specify the category"
          errstat=1
          continue
        else
          # is it a category in a two-level repo?
          if [ -d "$TOPLEVEL/$a" ]; then
            # push the whole category onto $*
            cd $TOPLEVEL
            ITEMLIST="$ITEMLIST $(ls -d $a/*)"
            cd - >/dev/null
          else
            log_warning "${blamemsg}${a} not found in $TOPLEVEL"
            errstat=1
            continue
          fi
        fi
      fi
    else
      # two names supplied, so it should be a prog in a two-level repo:
      if [ -f $TOPLEVEL/$a/$b/$b$SEARCHFILE ]; then
        # two-level repo, exact match :-)
        ITEMLIST="$ITEMLIST $a/$b"
      else
        # let's try to be user-friendly:
        if [ -d "$TOPLEVEL/$a/$b" ]; then
          log_warning "${blamemsg}$TOPLEVEL/$a/$b/$b$SEARCHFILE not found"
        elif [ -d "$TOPLEVEL/$a" ]; then
          log_warning "${blamemsg}${b} not found in $TOPLEVEL/$a"
        else
          log_warning "${blamemsg}${a}/${b} not found in $TOPLEVEL"
        fi
        errstat=1
        continue
      fi
    fi

  done

  return $errstat

}

#-------------------------------------------------------------------------------

function parse_package_name
# Split a package name into its component fields
# $1 = the package's pathname (or just the filename - we don't care)
# Returns global variables PN_{PRGNAM,VERSION,ARCH,BUILD,TAG,PKGTYPE}
# Return status: always 0
{
  local pkgnam=$(basename $1)
  PN_PRGNAM=$(echo $pkgnam | rev | cut -f4- -d- | rev)
  PN_VERSION=$(echo $pkgnam | rev | cut -f3 -d- | rev)
  PN_ARCH=$(echo $pkgnam | rev | cut -f2 -d- | rev)
  PN_BUILD=$(echo $pkgnam | rev | cut -f1 -d- | rev | sed 's/[^0-9]*$//')
  PN_TAG=$(echo $pkgnam | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
  PN_PKGTYPE=$(echo $pkgnam | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
  return
}
