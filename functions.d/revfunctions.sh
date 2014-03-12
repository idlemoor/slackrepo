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
# Create metadata files in package dir, and changelog entry
# $1    = operation (add, update, rebuild) and extra message
# $2    = itempath
# $3... = list of dependencies
# Return status:
# 9 = bizarre existential error, otherwise 0
{
  local opmsg="$1"
  local itempath="$2"
  local prgnam=${itempath##*/}
  shift 2

  MYREPO="$SR_PKGREPO"
  [ "$PROCMODE" = 'test' ] && MYREPO="$SR_TESTREPO"

  pkglist=$(ls $MYREPO/$itempath/$prgnam-*.t?z 2>/dev/null)
  for pkg in $pkglist; do
    pkgbase=$(basename $pkg | sed 's/\.t.z$//')

    # .rev file
    print_current_revinfo $itempath $* > $MYREPO/$itempath/${pkgbase}.rev

    # .dep file (no deps => no file)
    if [ $# != 0 ]; then
      > $MYREPO/$itempath/${pkgbase}.dep
      while [ $# != 0 ]; do
        echo "${1##*/}" \
          >> $MYREPO/$itempath/${pkgbase}.dep
        shift
      done
    fi

    # changelog entry: needlessly elaborate :-)
    if [ "$PROCMODE" != 'test' ]; then
      OPERATION="$(echo $opmsg | sed -e 's/^add/Added/' -e 's/^update/Updated/' -e 's/^rebuild.*/Rebuilt/')"
      extrastuff=''
      case "$opmsg" in
      add*)
          extrastuff="LINEFEED $(grep "^$prgnam: " $SR_GITREPO/$itempath/slack-desc | head -n 1 | sed -e 's/.*(/(/' -e 's/).*/)/')"
          ;;
      'update for git'*)
          extrastuff="LINEFEED $(cd $SR_GITREPO/$itempath; git log --pretty=format:%s . | sed -e 's/.*: //')"
          ;;
      *)  :
          ;;
      esac
      # Filter previous entries for this item from the changelog
      # (it may contain info from a previous run that was interrupted)
      grep -v "^${itempath}: " $SR_CHANGELOG > $TMP/sr_changelog.new
      echo "$itempath: ${OPERATION}. $extrastuff NEWLINE" >> $TMP/sr_changelog.new
      mv $TMP/sr_changelog.new $SR_CHANGELOG
    fi

    # Although gen_repos_files.sh can create the following files, it's quicker to
    # create the .txt file here (we don't have to extract the slack-desc from the package)
    # .txt file
    cat $SR_GITREPO/$itempath/slack-desc | sed -n '/^#/d;/:/p' > $MYREPO/$itempath/${pkgbase}.txt
    # .md5 file
    ( cd $MYREPO/$itempath/; md5sum $pkg > ${pkg##*/}.md5 )
    # .meta and .lst files are a bit more complex

  done
  return 0
}

#-------------------------------------------------------------------------------

function print_current_revinfo
# Prints a revision info summary on standard output
##### (document the format here)
# $1    = item name
# $2... = list of dependencies
##### do we need that list, or can we get it from DEPCACHE?
# Return status always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  shift

  gitrev="${GITREV[$itempath]}"
  if [ "${GITDIRTY[$itempath]}" = 'y' ]; then
    gitrev="${gitrev}+dirty"
  fi
  md5sums="$(cd $SR_HINTS; md5sum $itempath.* 2>/dev/null | grep -v -e '.sample$' -e '.new$' | sed 's; .*/;:;' | tr -s '[:space:]' ':')"
  if [ -n "$md5sums" ]; then
    echo "$prgnam git:$gitrev slack:$SLACKVER hints:$md5sums"
  else
    echo "$prgnam git:$gitrev slack:$SLACKVER"
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
# Compares print_current_revinfo with old revision info (from .rev file) and
# returns a status value summarising the difference.
# $1    = item name
# $2... = list of dependencies
##### do we need that list, or can we get it from DEPCACHE?
# Return status:
# 0 = up to date
# 1 = package not found, or has no .rev metadata file
# 2 = git revision changed, or git is dirty and files seem to have changed
# 3 = upstream version has changed (special case of 2, for friendlier messages)
# 4 = hints changed
# 5 = deps changed
# 6 = Slackware changed
# and the same status code is stored in $REVCACHE[$itempath]
# => DO NOT FORGET to set $REVCACHE[$itempath] before each return!
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  shift

  # If $REVCACHE already has an entry for $itempath, just return that ;-)
  if [ "${REVCACHE[$itempath]+yesitsset}" = 'yesitsset' ]; then
    return "${REVCACHE[$itempath]}"
  fi

  # Is there an old package?
  if [ "$PROCMODE" = 'test' ]; then
    pkglist=$(ls $SR_TESTREPO/$itempath/*.t?z 2>/dev/null)
    [ -z "$pkglist" ] && \
      pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  else
    pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  fi
  [ -z "$pkglist" ] && { REVCACHE[$itempath]=1; return 1; }

  # is there a version hint that differs from the old package's version?
  hint_version $itempath
  [ -n "$NEWVERSION" ] && { REVCACHE[$itempath]=3; return 3; }

  # if git is dirty, have any of the files been modified since the package was built?
  if [ "${GITDIRTY[$itempath]}" = 'y' ]; then
    log_warning "${itempath}: git is dirty"
    # is anything in the git dir newer than the corresponding package dir?
    if [ -n "$(find $SR_GITREPO/$itempath -newer $SR_PKGREPO/$itempath 2>/dev/null)" ]; then
      REVCACHE[$itempath]=2
      return 2
    fi
  fi

  # capture current rev into a temp file
  currfile=$SR_TMP/slackrepo_rev
  print_current_revinfo $itempath $* > $currfile
  # and extract some key stats into variables
  currgit=$(head -q -n 1 "$currfile" | sed -e 's/^.* git://' -e 's/ .*//')
  currhints=$(head -q -n 1 "$currfile" | sed -e 's/^.* hints://' -e 's/ .*//')
  currslack=$(head -q -n 1 "$currfile" | sed -e 's/^.* slack://' -e 's/ .*//')

  # compare the current rev to each old package's rev file
  for pkgfile in $pkglist; do
    # is the rev file missing?
    prevfile=$(echo $pkgfile | sed 's/\.t.z$/.rev/')
    [ ! -f "$prevfile" ] && { REVCACHE[$itempath]=1; return 1; }
    # has the git revision changed?
    prevgit=$(head -q -n 1 "$prevfile" | sed -e 's/^.* git://' -e 's/ .*//')
    if [ "$currgit" != "$prevgit" ]; then
      prevver=$(echo $pkgfile | rev | cut -f3 -d- | rev)
      if [ "${INFOVERSION[$itempath]}" != "$prevver" ]; then
        REVCACHE[$itempath]=3; return 3
      else
        REVCACHE[$itempath]=2; return 2
      fi
    fi
    # has a hint changed?
    prevhints=$(head -q -n 1 "$prevfile" | sed -e 's/^.* hints://' -e 's/ .*//')
    [ "$currhints" != "$prevhints" ] && { REVCACHE[$itempath]=4; return 4; }
    # has Slackware changed?
    prevslack=$(head -q -n 1 "$prevfile" | sed -e 's/^.* slack://' -e 's/ .*//')
    [ "$currslack" != "$prevslack" ] && { REVCACHE[$itempath]=6; return 6; }
    # Have the deps changed?  Check them by comparing the entire files
    # (note, by now we know that the first line must be the same)
    cmp -s "$currfile" "$prevfile" || { REVCACHE[$itempath]=5; return 5; }
  done

  REVCACHE[$itempath]=0
  return 0
}
