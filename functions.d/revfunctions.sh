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
# $1    = operation (build, update, rebuild) and extra message
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
  [ "$OPT_DRYRUN" = 'y' ] && MYREPO="$DRYREPO"

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
    if [ "$OPT_DRYRUN" != 'y' ]; then
      OPERATION="$(echo $opmsg | sed -e 's/^build/Added/' -e 's/^update/Updated/' -e 's/^rebuild.*/Rebuilt/')"
      extrastuff=''
      case "$opmsg" in
      build*)
          extrastuff="$(grep "^$prgnam: " $SR_SBREPO/$itempath/slack-desc | head -n 1 | sed -e 's/.*(/(/' -e 's/).*/)/')"
          ;;
      'update for git'*)
          extrastuff="$(cd $SR_SBREPO/$itempath; git log --pretty=format:%s -n 1 . | sed -e 's/.*: //')"
          ;;
      *)  :
          ;;
      esac
      # Filter previous entries for this item from the changelog
      # (it may contain info from a previous run that was interrupted)
      newchangelog=${CHANGELOG}.new
      grep -v "^${itempath}: " $CHANGELOG > $newchangelog
      if [ -z "$extrastuff" ]; then
        echo "$itempath: ${OPERATION}. NEWLINE" >> $newchangelog
      else
        echo "$itempath: ${OPERATION}. LINEFEED $extrastuff NEWLINE" >> $newchangelog
      fi
      mv $newchangelog $CHANGELOG
    fi

    # Although gen_repos_files.sh can create the following files, it's quicker to
    # create the .txt file here (we don't have to extract the slack-desc from the package)
    # .txt file
    cat $SR_SBREPO/$itempath/slack-desc | sed -n '/^#/d;/:/p' > $MYREPO/$itempath/${pkgbase}.txt
    # .md5 file
    ( cd $MYREPO/$itempath/; md5sum $pkg > ${pkg##*/}.md5 )
    # .meta and .lst files are a bit more complex

  done
  return 0
}

#-------------------------------------------------------------------------------

function print_current_revinfo
# Prints a revision info summary on standard output, format as follows:
#
# <prgnam> git:<gitrevision> slack:<slackversion> [hints:<hintname1>:<md5sum1>:[<hintname2>:<md5sum2>:[...]]]
# [<depnam> git:<gitrevision> slack:<slackversion> [hints:<hintname1>:<md5sum1>:[<hintname2>:<md5sum2>:[...]]]]
# [...]
#
# (for a non-git repo, git:<gitrevision> is replaced by secs:<since-epoch>)
#
# $1    = item name
# Return status always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ "$GOTGIT" = 'y' ]; then
    rev="git:${GITREV[$itempath]}"
    if [ "${GITDIRTY[$itempath]}" = 'y' ]; then
      rev="${rev}+dirty"
    fi
  else
    # Use newest file's seconds since epoch ;-)
    rev="secs:$(cd $SR_SBREPO/$itempath; ls -t | head -n 1 | xargs stat --format='%Y')"
  fi
  md5sums="$(cd $SR_HINTS; md5sum $itempath.* 2>/dev/null | grep -v -e '.sample$' -e '.new$' | sed 's; .*/;:;' | tr -s '[:space:]' ':')"
  if [ -n "$md5sums" ]; then
    echo "$prgnam $rev slack:$SLACKVER hints:$md5sums"
  else
    echo "$prgnam $rev slack:$SLACKVER"
  fi

  # capture revision of each dep from its .rev file
  for dep in ${DEPCACHE[$itempath]}; do
    if [ "$OPT_DRYRUN" = 'y' -a -f $DRYREPO/$dep/*.rev ]; then
      head -q -n 1 $DRYREPO/$dep/*.rev
    else
      head -q -n 1 $SR_PKGREPO/$dep/*.rev
    fi
  done

  return 0
}

#-------------------------------------------------------------------------------

function get_rev_status
# Compares print_current_revinfo with old revision info (from .rev file)
# and returns a status value summarising the difference.
# $1    = item name
# Return status:
# 0 = up to date
# 1 = package not found, or has no .rev metadata file
# 2 = git revision changed, or git is dirty and files seem to have changed,
#     or nongit repo and files seem to have changed
# 3 = version has changed (special case of 2, for friendlier messages)
# 4 = hints changed
# 5 = deps changed
# 6 = Slackware changed
# and the same status code is stored in $REVCACHE[$itempath]
# => DO NOT FORGET to set $REVCACHE[$itempath] before each return!
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  # If $REVCACHE already has an entry for $itempath, just return that ;-)
  if [ "${REVCACHE[$itempath]+yesitsset}" = 'yesitsset' ]; then
    return "${REVCACHE[$itempath]}"
  fi

  # Is there an old package?
  if [ "$OPT_DRYRUN" = 'y' ]; then
    pkglist=$(ls $DRYREPO/$itempath/*.t?z 2>/dev/null)
    [ -z "$pkglist" ] && \
      pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  else
    pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  fi
  [ -z "$pkglist" ] && { REVCACHE[$itempath]=1; return 1; }

  # is there a version hint that differs from the old package's version?
  do_hint_version $itempath #######
  [ -n "$NEWVERSION" ] && { REVCACHE[$itempath]=3; return 3; }

  # if this isn't a git repo, or if git is dirty,
  # have any of the files been modified since the package was built?
  if [ "$GOTGIT" = 'n' -o "${GITDIRTY[$itempath]}" = 'y' ]; then
    [ "${GITDIRTY[$itempath]}" = 'y' ] && log_warning "${itempath}: git is dirty"
    # is anything in the git dir newer than the corresponding package dir?
    if [ -n "$(find $SR_SBREPO/$itempath -newer $SR_PKGREPO/$itempath 2>/dev/null)" ]; then
      REVCACHE[$itempath]=2
      return 2
    fi
  fi

  # capture current rev into a temp file
  currfile=$TMPDIR/sr_curr_rev.$$.tmp
  print_current_revinfo $itempath > $currfile
  # and extract some key stats into variables
  currrev=$(head -q -n 1 "$currfile" | sed -r -e 's/^.* (git)|(secs)://' -e 's/ .*//')
  currhints=$(head -q -n 1 "$currfile" | sed -e 's/^.* hints://' -e 's/ .*//')
  currslack=$(head -q -n 1 "$currfile" | sed -e 's/^.* slack://' -e 's/ .*//')

  # compare the current rev to each old package's rev file
  for pkgfile in $pkglist; do
    # is the rev file missing?
    prevfile=$(echo $pkgfile | sed 's/\.t.z$/.rev/')
    [ ! -f "$prevfile" ] && { REVCACHE[$itempath]=1; return 1; }
    # has the revision changed?
    prevrev=$(head -q -n 1 "$prevfile" | sed -r -e 's/^.* (git)|(secs)://' -e 's/ .*//')
    if [ "$currrev" != "$prevrev" ]; then
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
  rm -f $currfile

  REVCACHE[$itempath]=0
  return 0
}
