#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for slackrepo
#   build_item
#   build_ok
#   build_failed
#   create_pkg_metadata
#   remove_item
#-------------------------------------------------------------------------------

function build_item
# Build the package(s) for an item
# $1 = itemid
# The built package goes into $SR_TMPOUT, but function build_ok then stores it elsewhere
# Return status:
# 0 = total success, world peace and happiness
# 1 = build failed
# 2 = download failed
# 3 = checksum failed
# 4 = [not used]
# 5 = skipped by hint, or unsupported on this arch
# 6 = SlackBuild returned 0 status, but nothing in $SR_TMPOUT
# 7 = excessively dramatic qa test fail
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local -a pkglist

  SR_TMPIN="$SR_TMP/sr_IN.$$"
  # initial wipe of $SR_TMPIN, even if $OPT_KEEPTMP is set
  rm -rf "$SR_TMPIN"
  cp -a "$SR_SBREPO/$itemdir" "$SR_TMPIN"

  if [ "$OPT_TEST" = 'y' ]; then
    test_slackbuild "$itemid" || return 7
  fi

  # Apply version hint
  NEWVERSION="${HINT_version[$itemid]}"
  if [ -n "$NEWVERSION" -a "${INFOVERSION[$itemid]}" != "$NEWVERSION" ]; then
    # Fiddle with $VERSION -- usually doomed to failure, but not always ;-)
    log_verbose "Note: $itemid: setting VERSION=$NEWVERSION (was ${INFOVERSION[$itemid]}) and ignoring md5sums"
    sed -i -e "s/^VERSION=.*/VERSION=$NEWVERSION/" "$SR_TMPIN/$itemfile"
    verpat="$(echo ${INFOVERSION[$itemid]} | sed 's/\./\\\./g')"
    INFODOWNLIST[$itemid]="$(echo "${INFODOWNLIST[$itemid]}" | sed "s/$verpat/$NEWVERSION/g")"
    HINT_md5ignore[$itemid]='y'
    INFOVERSION[$itemid]="$NEWVERSION"
  fi

  # Get the source (including check for unsupported/untested)
  verify_src "$itemid"
  case $? in
    0) # already got source, and it's good
       [ "$OPT_TEST" = 'y' ] && test_download "$itemid"
       ;;
    1|2|3|4)
       # already got source but it's bad, or not got source, or wrong version => get it
       download_src "$itemid" || { build_failed "$itemid"; return 2; }
       verify_src "$itemid" || { log_error -a "${itemid}: Downloaded source is bad"; build_failed "$itemid"; return 3; }
       ;;
    5) # unsupported/untested
       SKIPPEDLIST+=( "$itemid" )
       return 5
       ;;
  esac

  # Symlink the source (if any) into the temporary SlackBuild directory
  if [ -n "${INFODOWNLIST[$itemid]}" ]; then
    ln -sf -t "$SR_TMPIN/" "${SRCDIR[$itemid]}"/*
  fi

  # Get all dependencies installed
  install_deps "$itemid" || { uninstall_deps "$itemid"; return 1; }

  # Work out BUILD
  # Get the value from the SlackBuild
  unset BUILD
  buildassign=$(grep '^BUILD=' "$SR_TMPIN"/"$itemfile")
  if [ -z "$buildassign" ]; then
    buildassign="BUILD=1"
    log_warning -a "${itemid}: \"BUILD=\" not found in $itemfile; using 1"
  fi
  eval $buildassign
  if [ "${BUILDINFO:0:3}" = 'add' -o "${BUILDINFO:0:18}" = 'update for version' ]; then
    # We can just use the SlackBuild's BUILD
    SR_BUILD="$BUILD"
  else
    # Increment the existing package's BUILD, or use the SlackBuild's (whichever is greater).
    # If there are multiple packages from one SlackBuild, and they all have different BUILD numbers,
    # frankly, we are screwed :-(
    oldbuild=$(ls "$SR_PKGREPO"/"$itemdir"/*.t?z 2>/dev/null | head -n 1 | sed -e 's/^.*-//' -e 's/[^0-9]*$//' )
    nextbuild=$(( ${oldbuild:-0} + 1 ))
    if [ "$nextbuild" -gt "$BUILD" ]; then
      SR_BUILD="$nextbuild"
    else
      SR_BUILD="$BUILD"
    fi
  fi

  # Process other hints for the build:
  # uidgid ...
  do_hint_uidgid "$itemid"
  # ... makej1 (with MAKEFLAGS and NUMJOBS env vars) ...
  if [ "${HINT_makej1[$itemid]}" = 'y' ]; then
    tempmakeflags="MAKEFLAGS='-j1' $MAKEFLAGS"
    USE_NUMJOBS=" -j1 "
  else
    tempmakeflags="MAKEFLAGS='$SR_NUMJOBS' $MAKEFLAGS"
    USE_NUMJOBS=" $SR_NUMJOBS "
  fi
  # ... options ...
  options="${HINT_options[$itemid]}"
  SLACKBUILDCMD="sh ./$itemfile"
  [ -n "$tempmakeflags" -o -n "$options" ] && SLACKBUILDCMD="env $tempmakeflags $options $SLACKBUILDCMD"
  # ... and answers.
  [ -n "${HINT_answers[$itemid]}" ] && SLACKBUILDCMD="cat ${HINT_answers[$itemid]} | $SLACKBUILDCMD"

  # Build it
  SR_TMPOUT="$SR_TMP/sr_OUT.$$"
  # initial wipe of $SR_TMPOUT, even if $OPT_KEEPTMP is set
  rm -rf "$SR_TMPOUT"
  mkdir -p "$SR_TMPOUT"
  export \
    ARCH="$SR_ARCH" \
    BUILD="$SR_BUILD" \
    TAG="$SR_TAG" \
    TMP="$SR_TMP" \
    OUTPUT="$SR_TMPOUT" \
    PKGTYPE="$SR_PKGTYPE" \
    NUMJOBS="$USE_NUMJOBS"
  log_normal -a "Running $itemfile ..."
  log_verbose -a "$SLACKBUILDCMD"
  ( cd "$SR_TMPIN"; eval $SLACKBUILDCMD ) >> "$ITEMLOG" 2>&1
  stat=$?
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS
  if [ "$stat" != 0 ]; then
    log_error -a "${itemid}: $itemfile failed (status $stat)"
    build_failed "$itemid"
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=( $(ls "$SR_TMPOUT"/*.t?z 2>/dev/null) )
  if [ "${#pkglist[@]}" = 0 ]; then
    # let's get sneaky and snarf it/them from where makepkg said it/them was/were going ;-)
    logpkgs=$(grep "Slackware package .* created." "$ITEMLOG" | cut -f3 -d" ")
    if [ -n "$logpkgs" ]; then
      for pkgpath in $logpkgs; do
        if [ -f "$SR_TMPIN/README" -a -f "$SR_TMPIN"/$(basename "$itemfile" .SlackBuild).info ]; then
          # it's probably an SBo SlackBuild, so complain and don't retag
          log_warning -a "${itemid}: Package should have been in \$OUTPUT: $pkgpath"
          mv "$pkgpath" "$SR_TMPOUT"
        else
          pkgnam=$(basename "$pkgpath")
          currtag=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
          if [ "$currtag" != "$SR_TAG" ]; then
            # retag it
            pkgtype=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
            mv "$pkgpath" "$SR_TMPOUT"/$(echo "$pkgnam" | sed 's/'"$currtag"'\.'"$pkgtype"'$/'$SR_TAG'.'"$pkgtype"'/')
          else
            mv "$pkgpath" "$SR_TMPOUT"/
          fi
        fi
      done
      pkglist=( $(ls "$SR_TMPOUT"/*.t?z 2>/dev/null) )
    else
      log_error -a "${itemid}: No packages were created"
      build_failed "$itemid"
      return 6
    fi
  fi

  if [ "$OPT_TEST" = 'y' ]; then
    test_package "$itemid" "${pkglist[@]}" || { build_failed "$itemid"; return 7; }
  fi

  build_ok "$itemid"  # \o/
  return 0
}

#-------------------------------------------------------------------------------

function build_ok
# Log, cleanup and store the packages for a build that has succeeded
# $1 = itemid
# Also uses BUILDINFO set by rev_need_build
# Return status: always 0
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  [ "$OPT_KEEPTMP" != 'y' ] && rm -rf "$SR_TMPIN"

  if [ "$OPT_DRYRUN" = 'y' ]; then
    # put the packages into the special dryrun repo
    mkdir -p "$DRYREPO"/"$itemdir"
    rm -rf "$DRYREPO"/"$itemdir"/*
    mv "$SR_TMPOUT"/* "$DRYREPO"/"$itemdir"/
  else
    # put them into the real package repo
    mkdir -p "$SR_PKGREPO"/"$itemdir"
    rm -rf "$SR_PKGREPO"/"$itemdir"/*
    mv "$SR_TMPOUT"/* "$SR_PKGREPO"/"$itemdir"/
  fi
  # SR_TMPOUT is empty now, so remove it even if OPT_KEEPTMP is set
  rm -rf "$SR_TMPOUT"

  uninstall_deps "$itemid"

  create_pkg_metadata "$itemid"

  # This won't always kill everything, but it's good enough for saving space
  [ "$OPT_KEEPTMP" != 'y' ] && rm -rf "$SR_TMP"/"$itemprgnam"* "$SR_TMP"/package-"$itemprgnam"

  buildtype=$(echo $BUILDINFO | cut -f1 -d" ")
  msg="$buildtype OK"
  [ "$OPT_DRYRUN" = 'y' ] && msg="$buildtype --dry-run OK"
  log_success ":-) $itemid $msg (-:"
  OKLIST+=( "$itemid" )

  return 0
}

#-------------------------------------------------------------------------------

function build_failed
# Log and cleanup for a build that has failed
# $1 = itemid
# Return status: always 0
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  if [ "$OPT_KEEPTMP" != 'y' ]; then
    rm -rf "$SR_TMPIN" "$SR_TMPOUT"
    rm -rf "$SR_TMP"/"$itemprgnam"* "$SR_TMP"/package-"$itemprgnam"
  fi

  buildtype=$(echo $BUILDINFO | cut -f1 -d" ")
  msg="$buildtype FAILED"
  log_error -n ":-( $itemid $msg )-:"
  errorscan_itemlog | tee -a "$MAINLOG"
  log_error -n "See $ITEMLOG"
  FAILEDLIST+=( "$itemid" )

  uninstall_deps "$itemid"

  return 0
}

#-------------------------------------------------------------------------------

function create_pkg_metadata
# Create metadata files in package dir, and changelog entry
# $1    = itemid
# Return status:
# 9 = bizarre existential error, otherwise 0
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local -a pkglist

  MYREPO="$SR_PKGREPO"
  [ "$OPT_DRYRUN" = 'y' ] && MYREPO="$DRYREPO"

  #-----------------------------#
  # changelog entry: needlessly elaborate :-)
  #-----------------------------#
  if [ "$OPT_DRYRUN" != 'y' ]; then
    OPERATION="$(echo $BUILDINFO | sed -e 's/^add/Added/' -e 's/^update/Updated/' -e 's/^rebuild.*/Rebuilt/')"
    extrastuff=''
    case "$BUILDINFO" in
    add*)
        # append short description from slack-desc (if there's no slack-desc, this should be null)
        extrastuff="$(grep "^${itemprgnam}: " "$SR_SBREPO"/"$itemdir"/slack-desc 2>/dev/null| head -n 1 | sed -e 's/.*(/(/' -e 's/).*/)/')"
        ;;
    'update for git'*)
        # append the title of the latest commit message
        extrastuff="$(cd "$SR_SBREPO"/"$itemdir"; git log --pretty=format:%s -n 1 . | sed -e 's/.*: //')"
        ;;
    *)  :
        ;;
    esac
    # Filter previous entries for this item from the changelog
    # (it may contain info from a previous run that was interrupted)
    newchangelog="$CHANGELOG".new
    grep -v "^${itemid}: " "$CHANGELOG" > "$newchangelog"
    if [ -z "$extrastuff" ]; then
      echo "${itemid}: ${OPERATION}. NEWLINE" >> "$newchangelog"
    else
      echo "${itemid}: ${OPERATION}. LINEFEED $extrastuff NEWLINE" >> "$newchangelog"
    fi
    mv "$newchangelog" "$CHANGELOG"
  fi

  #-----------------------------#
  # .revision file
  #-----------------------------#
  print_current_revinfo "$itemid" > "$MYREPO"/"$itemdir"/.revision


  pkglist=( $(ls "$MYREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  for pkgpath in "${pkglist[@]}"; do

    pkgbasename=$(basename "$pkgpath")
    nosuffix=$(echo "$pkgpath" | sed 's/\.t.z$//')
    dotdep="$nosuffix".dep
    dottxt="$nosuffix".txt
    dotlst="$nosuffix".lst
    dotmeta="$nosuffix".meta
    # but the .md5 filename includes the suffix:
    dotmd5="$pkgpath".md5

    # Although gen_repos_files.sh can create most of the following files, it's
    # quicker to create them here (we don't have to extract the slack-desc from
    # the package, and if test_package has been run, we can reuse its listing
    # of the package contents)

    #-----------------------------#
    # .dep file (no deps => no file)
    #-----------------------------#
    if [ -z "${FULLDEPS[$itemid]}" ]; then
      rm -f "$dotdep"
    else
      printf "%s\n" ${FULLDEPS[$itemid]} > "$dotdep"
    fi

    #-----------------------------#
    # .txt file
    #-----------------------------#
    if [ -f "$SR_SBREPO"/"$itemdir"/slack-desc ]; then
      cat "$SR_SBREPO"/"$itemdir"/slack-desc | sed -n '/^#/d;/:/p' > "$dottxt"
    else
      echo "${itemprgnam}: ERROR: No slack-desc" > "$dottxt"
    fi

    #-----------------------------#
    # .md5 file
    #-----------------------------#
    ( cd "$MYREPO"/"$itemdir"/; md5sum "$pkgbasename" > "$dotmd5" )

    #-----------------------------#
    # .lst file
    #-----------------------------#
    cat << EOF > "$dotlst"
++========================================
||
||   Package:  ./$itemdir/$pkgbasename
||
++========================================
EOF
    TMP_PKGCONTENTS="$TMPDIR"/sr_pkgcontents_"$pkgbasename".$$.tmp
    if [ ! -f "$TMP_PKGCONTENTS" ]; then
      tar tvf "$pkgpath" > "$TMP_PKGCONTENTS"
    fi
    cat "$TMP_PKGCONTENTS" >> "$dotlst"
    echo "" >> "$dotlst"
    echo "" >> "$dotlst"

    #-----------------------------#
    # .meta file
    #-----------------------------#
    pkgsize=$(du -s "$pkgpath" | cut -f1)
    # this uncompressed size is approx, but hopefully good enough ;-)
    uncsize=$(awk '{t+=int($3/1024)+1} END {print t}' "$TMP_PKGCONTENTS")
    echo "PACKAGE NAME:  $pkgbase" > "$dotmeta"
    if [ -n "$DL_URL" ]; then
      echo "PACKAGE MIRROR:  $DL_URL" >> "$dotmeta"
    fi
    echo "PACKAGE LOCATION:  ./$itemdir" >> "$dotmeta"
    echo "PACKAGE SIZE (compressed):  ${pkgsize} K" >> "$dotmeta"
    echo "PACKAGE SIZE (uncompressed):  ${uncsize} K" >> "$dotmeta"
    if [ $FOR_SLAPTGET -eq 1 ]; then
      # Fish them out of the packaging directory. If they're not there, sod 'em.
      REQUIRED=$(cat "$TMP"/package-"$itemprgnam"/install/slack-required 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
      echo "PACKAGE REQUIRED:  $REQUIRED" >> "$dotmeta"
      CONFLICTS=$(cat "$TMP"/package-"$itemprgnam"/install/slack-conflicts 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
      echo "PACKAGE CONFLICTS:  $CONFLICTS" >> "$dotmeta"
      SUGGESTS=$(cat "$TMP"/package-"$itemprgnam"/install/slack-suggests 2>/dev/null | xargs -r)
      echo "PACKAGE SUGGESTS:  $SUGGESTS" >> "$dotmeta"
    fi
    echo "PACKAGE DESCRIPTION:" >> "$dotmeta"
    cat "$dottxt" >> "$dotmeta"
    echo "" >> "$dotmeta"

    [ "$OPT_KEEPTMP" != 'y' ] && rm -f "$TMP_PKGCONTENTS"

  done
  return 0
}

#-------------------------------------------------------------------------------

function remove_item
# Remove an item's package(s) from the package repository and the source repository
# $1 = itemid
# Return status:
# 0 = item removed
# 1 = item was skipped
{
  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  # Don't remove if this is an update and it's marked to be skipped
  if [ "$PROCMODE" = 'update' ]; then
    do_hint_skipme "$itemid" && return 1
  fi

  if [ "$OPT_DRYRUN" = 'y' ]; then
    log_important "$itemid would be removed (--dry-run)"
    #### log a list of packages
  else
    log_important "Removing $itemid"
    for repodir in "$SR_PKGREPO" "$SR_SRCREPO"; do
      ( cd "$repodir"/"$itemdir"
        find * -depth -print0 | xargs --null rm -f --
      )
      rmdir --parents --ignore-fail-on-non-empty "$repodir"/"$itemdir"
    done
    echo "$itemid: Removed. NEWLINE" >> "$CHANGELOG"
  fi
  return
}
