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

  #-----------------------------#
  # .revision file
  #-----------------------------#
  print_current_revinfo $itempath $* > $MYREPO/$itempath/.revision

  pkglist=$(ls $MYREPO/$itempath/*.t?z 2>/dev/null)
  for pkgpath in $pkglist; do

    pkgbase=$(basename $pkgpath)

    #-----------------------------#
    # changelog entry: needlessly elaborate :-)
    #-----------------------------#
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
      newchangelog=${TMP_CHANGELOG}.new
      grep -v "^${itempath}: " $TMP_CHANGELOG > $newchangelog
      if [ -z "$extrastuff" ]; then
        echo "${itempath}: ${OPERATION}. NEWLINE" >> $newchangelog
      else
        echo "${itempath}: ${OPERATION}. LINEFEED $extrastuff NEWLINE" >> $newchangelog
      fi
      mv $newchangelog $TMP_CHANGELOG
    fi

    # Although gen_repos_files.sh can create most of the following files, it's
    # quicker to create them here (we don't have to extract the slack-desc from
    # the package, and if OPT_TEST is set, we can reuse the tar list from test_package)

    METABASE=$MYREPO/$itempath/$(echo $pkgbase | sed 's/\.t.z$//')

    # .dep file (no deps => no file)
    ##### ought to list *all* deps here
    if [ $# != 0 ]; then
      > ${METABASE}.dep
      while [ $# != 0 ]; do
        echo "${1##*/}" \
          >> ${METABASE}.dep
        shift
      done
    fi

    #-----------------------------#
    # .txt file
    #-----------------------------#
    if [ -f $SR_SBREPO/$itempath/slack-desc ]; then
      cat $SR_SBREPO/$itempath/slack-desc | sed -n '/^#/d;/:/p' > ${METABASE}.txt
    else
      echo "${prgnam}: ERROR: No slack-desc" > ${METABASE}.txt
    fi

    #-----------------------------#
    # .md5 file
    #-----------------------------#
    ( cd $MYREPO/$itempath/; md5sum ${pkgbase} > ${pkgbase}.md5  )

    #-----------------------------#
    # .lst file
    #-----------------------------#
    cat << EOF > ${METABASE}.lst
++========================================
||
||   Package:  ./$itempath/$pkgbase
||
++========================================
EOF
    TMP_TARLIST=$TMPDIR/sr_tarlist_${pkgbase}.$$.tmp
    if [ ! -f "$TMP_TARLIST" ]; then
      tar tvf $pkgpath > $TMP_TARLIST
    fi
    cat ${TMP_TARLIST} >> ${METABASE}.lst
    echo "" >> ${METABASE}.lst
    echo "" >> ${METABASE}.lst

    #-----------------------------#
    # .meta file
    #-----------------------------#
    pkgsize=$(du -s $pkgpath | cut -f1)
    # this uncompressed size is approx, but hopefully good enough ;-)
    uncsize=$(awk '{t+=int($3/1024)+1} END {print t}' ${TMP_TARLIST})
    echo "PACKAGE NAME:  $pkgbase" > ${METABASE}.meta
    if [ -n "$DL_URL" ]; then
      echo "PACKAGE MIRROR:  $DL_URL" >> ${METABASE}.meta
    fi
    echo "PACKAGE LOCATION:  ./$itempath" >> ${METABASE}.meta
    echo "PACKAGE SIZE (compressed):  ${pkgsize} K" >> ${METABASE}.meta
    echo "PACKAGE SIZE (uncompressed):  ${uncsize} K" >> ${METABASE}.meta
    if [ $FOR_SLAPTGET -eq 1 ]; then
      # Fish them out of the packaging directory. If they're not there, sod 'em.
      REQUIRED=$(cat $TMP/package-$prgnam/install/slack-required 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
      echo "PACKAGE REQUIRED:  $REQUIRED" >> ${METABASE}.meta
      CONFLICTS=$(cat $TMP/package-$prgnam/install/slack-conflicts 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
      echo "PACKAGE CONFLICTS:  $CONFLICTS" >> ${METABASE}.meta
      SUGGESTS=$(cat $TMP/package-$prgnam/install/slack-suggests 2>/dev/null | xargs -r)
      echo "PACKAGE SUGGESTS:  $SUGGESTS" >> ${METABASE}.meta
    fi
    echo "PACKAGE DESCRIPTION:" >> ${METABASE}.meta
    cat ${METABASE}.txt >> ${METABASE}.meta
    echo "" >> ${METABASE}.meta

    [ "$OPT_KEEPTMP" != 'y' ] && rm -f $TMP_TARLIST

  done
  return 0
}

#-------------------------------------------------------------------------------

function print_current_revinfo
# Prints a revision info summary on standard output, format as follows:
#
# <prgnam> v:<version> git:<gitrevision> slack:<slackversion> [hints:<hintname1>:<md5sum1>:[<hintname2>:<md5sum2>:[...]]]
# [<depnam> v:<version> git:<gitrevision> slack:<slackversion> [hints:<hintname1>:<md5sum1>:[<hintname2>:<md5sum2>:[...]]]]
# [...]
#
# (for a non-git repo, git:<gitrevision> is replaced by secs:<since-epoch>)
#
# $1    = item name
# Return status always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  ver="v:${INFOVERSION[$itempath]}"

  if [ "$GOTGIT" = 'y' ]; then
    rev="git:${GITREV[$itempath]}"
    if [ "${GITDIRTY[$itempath]}" = 'y' ]; then
      rev="${rev}+dirty"
    fi
  else
    # Use newest file's seconds since epoch ;-)
    rev="secs:$(cd $SR_SBREPO/$itempath; ls -t | head -n 1 | xargs stat --format='%Y')"
  fi
  hintmd5sums="$(cd $SR_HINTS; md5sum $itempath.* 2>/dev/null | grep -v -e '.sample$' -e '.new$' | sed 's; .*/;:;' | tr -s '[:space:]' ':')"
  if [ -n "$hintmd5sums" ]; then
    echo "$prgnam $ver $rev slack:$SLACKVER hints:$hintmd5sums"
  else
    echo "$prgnam $ver $rev slack:$SLACKVER"
  fi

  # capture revision of each dep from its .revision file
  for dep in ${DEPCACHE[$itempath]}; do
    if [ "$OPT_DRYRUN" = 'y' -a -f $DRYREPO/$dep/.revision ]; then
      head -q -n 1 $DRYREPO/$dep/.revision
    else
      head -q -n 1 $SR_PKGREPO/$dep/.revision
    fi
  done

  return 0
}

#-------------------------------------------------------------------------------

function get_rev_status
# Works out a status value summarising whether the package needs to be built.
# $1 = itempath
# Return status:
# 0 = up to date
# 1 = package not found, or has no .revision file
# 2 = version has changed
# 3 = git revision changed, or git is dirty and files seem to have changed,
#     or nongit repo and files seem to have changed
# 4 = hints changed
# 5 = deps changed
# 6 = Slackware changed
# 9 = has been updated (special case of 0, for friendlier messages)
#     (set by build_with_deps, not here)
# and the same status code is stored in $REVCACHE[$itempath]
#   => DO NOT FORGET to set $REVCACHE[$itempath] before each return!
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  # If $REVCACHE already has an entry for $itempath, just return that ;-)
  if [ "${REVCACHE[$itempath]+yesitsset}" = 'yesitsset' ]; then
    return "${REVCACHE[$itempath]}"
  fi

  # Is there an existing package?
  if [ "$OPT_DRYRUN" = 'y' ]; then
    pkglist=$(ls $DRYREPO/$itempath/*.t?z 2>/dev/null)
    [ -z "$pkglist" ] && \
      pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  else
    pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  fi
  [ -z "$pkglist" ] && { REVCACHE[$itempath]=1; return 1; }

  REVFILE=$(dirname $(echo $pkglist | head -n 1))/.revision
  # Is the .revision file missing?
  [ ! -f "$REVFILE" ] && { REVCACHE[$itempath]=1; return 1; }

  # capture current rev into a temp file
  TMP_CURREV=$TMPDIR/sr_curr_rev.$$.tmp
  print_current_revinfo $itempath > $TMP_CURREV
  # and extract some key stats into variables
  currinfo=$(head -q -n 1 "$TMP_CURREV")
  previnfo=$(head -q -n 1 "$REVFILE")
  currver=$(echo $currinfo | cut -f2 -d" ")
  prevver=$(echo $previnfo | cut -f2 -d" ")
  currrev=$(echo $currinfo | cut -f3 -d" ")
  prevrev=$(echo $previnfo | cut -f3 -d" ")
  currslk=$(echo $currinfo | cut -f4 -d" ")
  prevslk=$(echo $previnfo | cut -f4 -d" ")
  currhnt=$(echo $currinfo | cut -f5 -d" ")
  prevhnt=$(echo $previnfo | cut -f5 -d" ")

  # Are we upversioning?
  if [ "$currver" != "$prevver" ]; then
    REVCACHE[$itempath]=2
  # If this isn't a git repo, have any of the files been modified since the package was built?
  elif [ "$GOTGIT" = 'n' -a -n "$(find $SR_SBREPO/$itempath -newer $revfile 2>/dev/null)" ]; then
    REVCACHE[$itempath]=3
  # If git is dirty, have any of the files been modified since the package was built?
  elif [ "${GITDIRTY[$itempath]}" = 'y' -a -n "$(find $SR_SBREPO/$itempath -newer $revfile 2>/dev/null)" ]; then
    REVCACHE[$itempath]=3
  # has the revision changed?
  elif [ "$currrev" != "$prevrev" ]; then
    REVCACHE[$itempath]=3
  # has a hint changed?
  elif [ "$currhnt" != "$prevhnt" ]; then
    REVCACHE[$itempath]=4
  # has Slackware changed?
  elif [ "$currslk" != "$prevslk" ]; then
    REVCACHE[$itempath]=6
  # have the deps changed?  Check them by comparing the entire files
  # (note, by now we know that the first line must be the same)
  elif ! cmp -s "$TMP_CURREV" "$REVFILE"; then
    REVCACHE[$itempath]=5
  # nothing has changed => it's up-to-date
  else
    REVCACHE[$itempath]=0
    #### but is it newer than the item that depends on it? if so, return 9
  fi

  [ "$OPT_KEEPTMP" != 'y' ] && rm -f $TMP_CURREV
  return ${REVCACHE[$itempath]}

}
