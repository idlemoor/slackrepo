#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# revfunctions.sh - revision control functions for slackrepo
#   create_metadata
#   print_current_revinfo
#   get_rev_status
#-------------------------------------------------------------------------------

function create_metadata
# Create .rev and .dep files in package dir, and changelog entry
# $1    = operation (add, update, rebuild)
# $2    = itemname
# $3... = list of dependencies
# Return status:
# 
# 
{
  local op="$1"
  local itemname="$2"
  local prg=$(basename $itemname)
  shift 2

  MYREPO="$SR_PKGREPO"
  [ "$PROCMODE" = 'test' ] && MYREPO="$SR_TESTREPO"

  pkglist=$(ls $MYREPO/$itemname/$prg-*.t?z 2>/dev/null)
  for pkg in $pkglist; do
    pkgbase=$(basename $pkg | sed 's/\.t.z$//')

    print_current_revinfo $itemname $* > $MYREPO/$itemname/${pkgbase}.rev

    if [ $# != 0 ]; then
      > $MYREPO/$itemname/${pkgbase}.dep
      while [ $# != 0 ]; do
        echo "${1##*/}" \
          >> $MYREPO/$itemname/${pkgbase}.dep
        shift
      done
    fi

    if [ "$PROCMODE" != 'test' ]; then
      case "$op" in
        add )     OPERATION='Added' ;;
        update )  OPERATION='Updated' ;;
        rebuild ) OPERATION='Rebuilt' ;;
        * )       log_error "$(basename $0): Unrecognised operation '$op'" ; return 9 ;;
      esac
      # Filter previous entries for this item from the changelog
      # (it may contain info from a previous run that was interrupted)
      grep -v "^${itemname}: " $SR_CHANGELOG > $TMP/sr_changelog.new
      echo "$itemname: $OPERATION version $VERSION. NEWLINE" >> $TMP/sr_changelog.new
      mv $TMP/sr_changelog.new $SR_CHANGELOG
    fi

  done
  return 0
}

#-------------------------------------------------------------------------------

function print_current_revinfo
  # $1    = item name
  # $2... = list of dependencies
{
  local itemname="$1"
  local prg=$(basename $itemname)
  shift

  gitrev="$(cd $SR_GITREPO/$itemname; git log -n 1 --format=format:%H .)"
  if [ -n "$(cd $SR_GITREPO/$itemname; git status -s .)" ]; then
    gitrev="${gitrev}+dirty"
  fi
  md5sums="$(cd $SR_HINTS; md5sum $itemname.* 2>/dev/null | grep -v -e '.sample$' -e '.new$' | sed 's; .*/;:;' | tr -s '[:space:]' ':')"
  if [ -n "$md5sums" ]; then
    echo "$prg git:$gitrev slack:$SLACKVER hints:$md5sums"
  else
    echo "$prg git:$gitrev slack:$SLACKVER"
  fi

  # capture revision of each dep from its .rev file
  while [ $# != 0 ]; do
    if [ "$PROCMODE" = 'test' -a -f $SR_TESTREPO/$1/*.rev ]; then
      head -q -n 1 $SR_TESTREPO/$1/*.rev
    else
      head -q -n 1 $SR_PKGREPO/$1/*.rev
    fi
    shift
  done

  return 0
}

#-------------------------------------------------------------------------------

function get_rev_status
# $1    = item name
# $2... = list of dependencies
# Return status:
# 0 = up to date
# 1 = package not found (or no .rev metadata file)
# 2 = git revision changed
# 3 = git is dirty, files seem to have changed
# 4 = hints changed
# 5 = deps changed
# 6 = Slackware changed
# and the same status code is stored in $REVCACHE[$itemname]
# DO NOT FORGET to set $REVCACHE[$itemname] before each return!
{
  local itemname="$1"
  local prg=$(basename $itemname)
  shift

  # If $REVCACHE already has an entry for $itemname, just return that ;-)
  if [ "${REVCACHE[$itemname]+yesitsset}" = 'yesitsset' ]; then
    return "${REVCACHE[$itemname]}"
  fi

  # owt or nowt?
  if [ "$PROCMODE" = 'test' ]; then
    pkglist=$(ls $SR_TESTREPO/$itemname/*.t?z 2>/dev/null)
    [ -z "$pkglist" ] && \
      pkglist=$(ls $SR_PKGREPO/$itemname/*.t?z 2>/dev/null)
  else
    pkglist=$(ls $SR_PKGREPO/$itemname/*.t?z 2>/dev/null)
  fi
  [ -z "$pkglist" ] && { REVCACHE[$itemname]=1; return 1; }

  gitdirt="$(cd $SR_GITREPO/$itemname; git status -s .)"
  if [ -n "$gitdirt" ]; then
    log_warning "${itemname}: git is dirty"
    # is anything in the git dir newer than the corresponding package dir?
    if [ -n "$(find $SR_GITREPO/$itemname -newer $SR_PKGREPO/$itemname 2>/dev/null)" ]; then
      REVCACHE[$itemname]=3
      return 3
    fi
  fi

  # capture current rev into a temp file
  currfile=$SR_TMP/slackrepo_rev
  print_current_revinfo $itemname $* > $currfile
  # and extract some key stats into variables
  currgit=$(head -q -n 1 "$currfile" | sed -e 's/^.* git://' -e 's/ .*//')
  currhints=$(head -q -n 1 "$currfile" | sed -e 's/^.* hints://' -e 's/ .*//')
  currslack=$(head -q -n 1 "$currfile" | sed -e 's/^.* slack://' -e 's/ .*//')

  # compare the current rev to each old package's rev file
  for pkgfile in $pkglist; do
    prevfile=$(echo $pkgfile | sed 's/\.t.z$/.rev/')
    [ -f "$prevfile" ] || { REVCACHE[$itemname]=1; return 1; }
    prevgit=$(head -q -n 1 "$prevfile" | sed -e 's/^.* git://' -e 's/ .*//')
    [ "$currgit" = "$prevgit" ] || { REVCACHE[$itemname]=2; return 2; }
    prevhints=$(head -q -n 1 "$prevfile" | sed -e 's/^.* hints://' -e 's/ .*//')
    [ "$currhints" = "$prevhints" ] || { REVCACHE[$itemname]=4; return 4; }
    prevslack=$(head -q -n 1 "$prevfile" | sed -e 's/^.* slack://' -e 's/ .*//')
    [ "$currslack" = "$prevslack" ] || { REVCACHE[$itemname]=6; return 6; }
    # Check the deps by comparing the entire files
    # (by now we know that the first line must be the same)
    cmp -s "$currfile" "$prevfile" || { REVCACHE[$itemname]=5; return 5; }
  done

  REVCACHE[$itemname]=0
  return 0
}
