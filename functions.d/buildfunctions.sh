#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for slackrepo
#   build_item
#   build_ok
#   build_failed
#   create_pkg_metadata
#   do_groupadd_useradd
#   remove_item
#-------------------------------------------------------------------------------

function build_item
# Build the package(s) for an item
# $1 = itemid
# The built package goes into $MYTMPOUT, but function build_ok then stores it elsewhere
# Return status:
# 0 = total success, world peace and happiness
# 1 = build failed
# 2 = download failed
# 3 = checksum failed
# 4 = [not used]
# 5 = skipped (skip hint, or download=no, or unsupported on this arch)
# 6 = SlackBuild returned 0 status, but nothing in $MYTMPOUT
# 7 = excessively dramatic qa test fail
# 8 = package install fail
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local -a pkglist

  MYTMPIN="$MYTMPDIR/slackbuild_$itemprgnam"
  # initial wipe of $MYTMPIN, even if $OPT_KEEP_TMP is set
  rm -rf "$MYTMPIN"
  cp -a "$SR_SBREPO/$itemdir" "$MYTMPIN"

  if [ "$OPT_TEST" = 'y' ]; then
    test_slackbuild "$itemid" || return 7
  fi

  # Apply version hint
  NEWVERSION="${HINT_VERSION[$itemid]}"
  if [ -n "$NEWVERSION" -a "${INFOVERSION[$itemid]}" != "$NEWVERSION" ]; then
    # Fiddle with $VERSION -- usually doomed to failure, but not always ;-)
    log_verbose -a "Note: $itemid: setting VERSION=$NEWVERSION (was ${INFOVERSION[$itemid]})"
    sed -i -e "s/^VERSION=.*/VERSION=$NEWVERSION/" "$MYTMPIN/$itemfile"
    verpat="$(echo ${INFOVERSION[$itemid]} | sed 's/\./\\\./g')"
    INFODOWNLIST[$itemid]="$(echo "${INFODOWNLIST[$itemid]}" | sed "s/$verpat/$NEWVERSION/g")"
    INFOVERSION[$itemid]="$NEWVERSION"
  fi

  # Get the source (including check for unsupported/untested/nodownload)
  verify_src "$itemid"
  case $? in
    0) # already got source, and it's good
       [ "$OPT_TEST" = 'y' -a -z "${HINT_NODOWNLOAD[$itemid]}" ] && test_download "$itemid"
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
    6) # nodownload hint (probably needs manual download due to licence agreement)
       log_warning -n -a ":-/ SKIPPED $itemid - please download the source /-:"
       log_normal "  from: ${INFODOWNLIST[$itemid]}"
       log_normal "  to:   ${SRCDIR[$itemid]}"
       # We ought to prepare that directory ;-)
       mkdir -p "${SRCDIR[$itemid]}"
       SKIPPEDLIST+=( "$itemid" )
       return 5
       ;;
  esac

  # Symlink the source (if any) into the temporary SlackBuild directory
  if [ -n "${INFODOWNLIST[$itemid]}" ]; then
    ln -sf -t "$MYTMPIN/" "${SRCDIR[$itemid]}"/*
  fi

  # Get all dependencies installed
  install_deps "$itemid" || { uninstall_deps "$itemid"; return 1; }

  # Work out BUILD
  # Get the value from the SlackBuild
  unset BUILD
  buildassign=$(grep '^BUILD=' "$MYTMPIN"/"$itemfile")
  if [ -z "$buildassign" ]; then
    buildassign="BUILD=1"
    log_warning -a "${itemid}: no \"BUILD=\" in $itemfile; using 1"
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

  # Setup MYTMPOUT
  MYTMPOUT="$MYTMPDIR/packages_$itemprgnam"
  # initial wipe of $MYTMPOUT, even if $OPT_KEEP_TMP is set
  rm -rf "$MYTMPOUT"
  mkdir -p "$MYTMPOUT"

  export \
    ARCH="$SR_ARCH" \
    BUILD="$SR_BUILD" \
    TAG="$SR_TAG" \
    TMP="$SR_TMP" \
    OUTPUT="$MYTMPOUT" \
    PKGTYPE="$SR_PKGTYPE" \
    NUMJOBS="$SR_NUMJOBS"

  # Process other hints for the build:

  # GROUPADD and USERADD ...
  do_groupadd_useradd "$itemid"

  # ... NUMJOBS (with MAKEFLAGS and NUMJOBS env vars) ...
  NUMJOBS=" ${HINT_NUMJOBS[$itemid]:-$SR_NUMJOBS} "
  tempmakeflags="MAKEFLAGS='${HINT_NUMJOBS[$itemid]:-$SR_NUMJOBS}'"

  # ... OPTIONS ...
  options="${HINT_OPTIONS[$itemid]}"
  SLACKBUILDCMD="sh ./$itemfile"
  [ -n "$tempmakeflags" -o -n "$options" ] && SLACKBUILDCMD="env $tempmakeflags $options $SLACKBUILDCMD"

  # ... ANSWER ...
  [ -n "${HINT_ANSWER[$itemid]}" ] && SLACKBUILDCMD="echo -e '${HINT_ANSWER[$itemid]}' | $SLACKBUILDCMD"

  # ... and SPECIAL.
  noremove='n'
  for special in ${HINT_SPECIAL[$itemid]}; do
    case "$special" in
    'multilib_ldflags' )
      if [ "$SYS_MULTILIB" = 'y' ]; then
        # This includes the rare case when an i486 cross-compile on x86_64 needs -L/usr/lib
        log_verbose "Special action: multilib_ldflags"
        libdirsuffix=''
        [ "$SR_ARCH" = 'x86_64' ] && libdirsuffix='64'
        sed -i -e "s;^\./configure ;LDFLAGS=\"-L/usr/lib$libdirsuffix\" &;" "$MYTMPIN/$itemfile"
      fi
      ;;
    'stubs-32' )
      if [ "$SYS_ARCH" = 'x86_64' -a "$SYS_MULTILIB" = 'n' -a ! -e /usr/include/gnu/stubs-32.h ]; then
        log_verbose "Special action: stubs-32"
        ln -s /usr/include/gnu/stubs-64.h /usr/include/gnu/stubs-32.h
        if [ -z "${HINT_CLEANUP[$itemid]}" ]; then
          HINT_CLEANUP[$itemid]="rm /usr/include/gnu/stubs-32.h"
        else
          HINT_CLEANUP[$itemid]="${HINT_CLEANUP[$itemid]}; rm /usr/include/gnu/stubs-32.h"
        fi
      fi
      ;;
    'download_basename' )
      log_verbose "Special action: download_basename"
      # We're going to guess that the timestamps in the source repo indicate the
      # order in which files were downloaded and therefore the order in INFODOWNLIST.
      # most of the current bozo downloaders only download one file anyway :-)
      tempdownlist=( ${INFODOWNLIST[$itemid]} )
      count=0
      for sourcefile in $(ls -rt "$SR_SRCREPO"/"$itemdir" 2>/dev/null); do
        target=$(basename "${tempdownlist[$count]}")
        ( cd "$MYTMPIN"; [ ! -e "$target" ] && ln -s $(basename "$sourcefile") "$target" )
        count=$(( $count + 1 ))
      done
      ;;
    'noexport_ARCH' )
      log_verbose "Special action: noexport_ARCH"
      sed -i -e "s/^PRGNAM=.*/&; ARCH='$SR_ARCH'/" "$MYTMPIN"/"$itemfile"
      unset ARCH
      ;;
    'noexport_BUILD' )
      log_verbose "Special action: noexport_BUILD"
      sed -i -e "s/^BUILD=.*/BUILD='$BUILD'/" "$MYTMPIN"/"$itemfile"
      unset BUILD
      ;;
    'noremove' )
      log_verbose "Special action: noremove"
      noremove='y'
      ;;
    * )
      log_warning "Hint SPECIAL=\"$special\" not recognised"
      ;;
    esac
  done

  # Remove any existing packages (some builds fail if already installed)
  # (... this might not be entirely appropriate for gcc or glibc ...)
  if [ "$noremove" != 'y' ]; then
    uninstall_packages -f "$itemid"
  fi

  # Build it
  buildstarttime="$(date '+%s')"
  prevbuildsecs="$(db_get_buildsecs "$itemid")"
  eta=""
  [ ${prevbuildsecs:-0} -gt 120 ] && eta=" ETA $(date --date=@"$(( $buildstarttime + $prevbuildsecs ))" '+%T')"
  log_normal -a "Running $itemfile ...$eta"
  log_verbose -a "$SLACKBUILDCMD"
  if [ "$OPT_VERY_VERBOSE" = 'y' ]; then
    echo ''
    echo '---->8-------->8-------->8-------->8-------->8-------->8-------->8-------->8---'
    echo ''
    set -o pipefail
    if [ "$SYS_MULTILIB" = "y" -a "$ARCH" = 'i486' ]; then
      ( cd "$MYTMPIN"; . /etc/profile.d/32dev.sh; eval $SLACKBUILDCMD ) 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    else
      ( cd "$MYTMPIN"; eval $SLACKBUILDCMD ) 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    fi
    set +o pipefail
    echo '----8<--------8<--------8<--------8<--------8<--------8<--------8<--------8<---'
    echo ''
  else
    if [ "$SYS_MULTILIB" = "y" -a "$ARCH" = 'i486' ]; then
      ( cd "$MYTMPIN"; . /etc/profile.d/32dev.sh; eval $SLACKBUILDCMD ) >> "$ITEMLOG" 2>&1
      buildstat=$?
    else
      ( cd "$MYTMPIN"; eval $SLACKBUILDCMD ) >> "$ITEMLOG" 2>&1
      buildstat=$?
    fi
  fi
  buildfinishtime="$(date '+%s')"
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS

  if [ "$buildstat" != 0 ]; then
    log_error -a "${itemid}: $itemfile failed (status $buildstat)"
    build_failed "$itemid"
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=( $(ls "$MYTMPOUT"/*.t?z 2>/dev/null) )
  if [ "${#pkglist[@]}" = 0 ]; then
    # let's get sneaky and snarf it/them from where makepkg said it/them was/were going ;-)
    logpkgs=$(grep "Slackware package .* created." "$ITEMLOG" | cut -f3 -d" ")
    if [ -n "$logpkgs" ]; then
      for pkgpath in $logpkgs; do
        if [ -f "$MYTMPIN/README" -a -f "$MYTMPIN"/$(basename "$itemfile" .SlackBuild).info ]; then
          # it's probably an SBo SlackBuild, so complain and don't retag
          log_warning -a "${itemid}: Package should have been in \$OUTPUT: $pkgpath"
          mv "$pkgpath" "$MYTMPOUT"
        else
          pkgnam=$(basename "$pkgpath")
          currtag=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
          if [ "$currtag" != "$SR_TAG" ]; then
            # retag it
            pkgtype=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
            mv "$pkgpath" "$MYTMPOUT"/$(echo "$pkgnam" | sed 's/'"$currtag"'\.'"$pkgtype"'$/'$SR_TAG'.'"$pkgtype"'/')
          else
            mv "$pkgpath" "$MYTMPOUT"/
          fi
        fi
      done
      pkglist=( $(ls "$MYTMPOUT"/*.t?z 2>/dev/null) )
    else
      log_error -a "${itemid}: No packages were created"
      build_failed "$itemid"
      return 6
    fi
  fi

  db_set_buildsecs "$itemid" $(( $buildfinishtime - $buildstarttime ))

  if [ "$OPT_TEST" = 'y' ]; then
    test_package "$itemid" "${pkglist[@]}" || { build_failed "$itemid"; return 7; }
  elif [ "${HINT_INSTALL[$itemid]}" = 'y' ] || [ "$OPT_INSTALL" = 'y' -a "${HINT_INSTALL[$itemid]}" != 'n' ]; then
    install_packages "$itemid" || { build_failed "$itemid"; return 8; }
  fi

  build_ok "$itemid"  # \o/
  return 0
}

#-------------------------------------------------------------------------------

function build_ok
# Log, cleanup and store the packages for a build that has succeeded
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  [ "$OPT_KEEP_TMP" != 'y' ] && rm -rf "$MYTMPIN"

  if [ "$OPT_DRY_RUN" = 'y' ]; then
    # put the packages into the special dryrun repo
    mkdir -p "$DRYREPO"/"$itemdir"
    rm -rf "$DRYREPO"/"$itemdir"/*
    mv "$MYTMPOUT"/* "$DRYREPO"/"$itemdir"/
  else
    # put them into the real package repo
    mkdir -p "$SR_PKGREPO"/"$itemdir"
    rm -rf "$SR_PKGREPO"/"$itemdir"/*
    mv "$MYTMPOUT"/* "$SR_PKGREPO"/"$itemdir"/
  fi
  # MYTMPOUT is empty now, so remove it even if OPT_KEEP_TMP is set
  rm -rf "$MYTMPOUT"

  if [ "${HINT_INSTALL[$itemid]}" = 'n' ] || [ "$OPT_INSTALL" != 'y' -a "${HINT_INSTALL[$itemid]}" != 'y' ]; then
    uninstall_deps "$itemid"
  fi

  create_pkg_metadata "$itemid"  # sets $CHANGEMSG

  # This won't always kill everything, but it's good enough for saving space
  [ "$OPT_KEEP_TMP" != 'y' ] && rm -rf "$SR_TMP"/"$itemprgnam"* "$SR_TMP"/package-"$itemprgnam"

  buildopt=''
  [ "$OPT_DRY_RUN" = 'y' ] && buildopt=' [dry run]'
  [ "$OPT_INSTALL" = 'y' ] && buildopt=' [install]'
  log_success ":-) ${itemid}: $CHANGEMSG$buildopt (-:"
  OKLIST+=( "$itemid" )

  return 0
}

#-------------------------------------------------------------------------------

function build_failed
# Log and cleanup for a build that has failed
# $1 = itemid
# Also uses BUILDINFO set by needs_build()
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    rm -rf "$MYTMPIN" "$MYTMPOUT"
    rm -rf "$SR_TMP"/"$itemprgnam"* "$SR_TMP"/package-"$itemprgnam"
  fi

  buildtype=$(echo $BUILDINFO | cut -f1 -d" ")
  msg="$buildtype FAILED"
  log_error -n ":-( $itemid $msg )-:"
  if [ "$OPT_QUIET" != 'y' ]; then
    errorscan_itemlog | tee -a "$MAINLOG"
  else
    errorscan_itemlog >> "$MAINLOG"
  fi
  log_error -n "See $ITEMLOG"
  FAILEDLIST+=( "$itemid" )

  if [ "${HINT_INSTALL[$itemid]}" = 'n' ] || [ "$OPT_INSTALL" != 'y' -a "${HINT_INSTALL[$itemid]}" != 'y' ]; then
    uninstall_deps "$itemid"
  fi

  return 0
}

#-------------------------------------------------------------------------------

function create_pkg_metadata
# Create metadata files in package dir, and changelog entry
# $1 = itemid
# Return status:
# 9 = bizarre existential error, otherwise 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local -a pkglist

  MYREPO="$SR_PKGREPO"
  [ "$OPT_DRY_RUN" = 'y' ] && MYREPO="$DRYREPO"

  #-----------------------------#
  # changelog entry: needlessly elaborate :-)
  #-----------------------------#

  OPERATION="$(echo $BUILDINFO | sed -e 's/^add/Added/' -e 's/^update/Updated/' -e 's/^rebuild.*/Rebuilt/')"
  extrastuff=''
  case "$BUILDINFO" in
  add*)
      # add short description from slack-desc (if there's no slack-desc, this should be null)
      extrastuff="($(grep "^${itemprgnam}: " "$SR_SBREPO"/"$itemdir"/slack-desc 2>/dev/null| head -n 1 | sed -e 's/.*(//' -e 's/).*//'))"
      ;;
  'update for git'*)
      # add title of the latest commit message
      extrastuff="($(cd "$SR_SBREPO"/"$itemdir"; git log --pretty=format:%s -n 1 . | sed -e 's/.*: //' -e 's/\.$//'))"
      ;;
  *)  :
      ;;
  esac
  # Set $changelogentry for the ChangeLog, and $CHANGEMSG for build_ok()
  if [ -z "$extrastuff" ]; then
    changelogentry="${itemid}: ${OPERATION}. NEWLINE"
    CHANGEMSG="${OPERATION}"
  else
    changelogentry="${itemid}: ${OPERATION}. LINEFEED $extrastuff NEWLINE"
    CHANGEMSG="${OPERATION} ${extrastuff}"
  fi
  if [ "$OPT_DRY_RUN" != 'y' ]; then
    echo "$changelogentry" >> "$CHANGELOG"
  fi

  #-----------------------------#
  # .revision file
  #-----------------------------#
  print_current_revinfo "$itemid" > "$MYREPO"/"$itemdir"/.revision


  pkglist=( $(ls "$MYREPO"/"$itemdir"/*.t?z 2>/dev/null) )
  for pkgpath in "${pkglist[@]}"; do

    pkgbasename=$(basename "$pkgpath")
    pkgnam=$(echo "$pkgbasename" | rev | cut -f4- -d- | rev)
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
    rm -f "$dotdep"
    if [ -n "${FULLDEPS[$itemid]}" ]; then
      for dep in ${FULLDEPS[$itemid]}; do
        printf "%s\n" $(basename $dep) >> "$dotdep"
      done
    fi

    #-----------------------------#
    # slack-required
    #-----------------------------#
    if [ "$SR_FOR_SLAPTGET" -eq 1 ]; then
      if [ -n "${DIRECTDEPS[$itemid]}" ]; then
        if [ -d "$TMP"/package-"$pkgnam"/install -a ! -f "$TMP"/package-"$pkgnam"/install/slack-required ]; then
          for dep in ${DIRECTDEPS[$itemid]}; do
            printf "%s\n" $(basename $dep) >> "$TMP"/package-"$pkgnam"/install/slack-required
          done
          ( cd "$TMP"/package-"$itemprgnam"; tar-1.13 r "$pkgpath" install/slack-required )
        fi
      fi
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
    TMP_PKGCONTENTS="$MYTMPDIR"/pkgcontents_"$pkgbasename"
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
    if [ -n "$SR_DL_URL" ]; then
      echo "PACKAGE MIRROR:  $SR_DL_URL" >> "$dotmeta"
    fi
    echo "PACKAGE LOCATION:  ./$itemdir" >> "$dotmeta"
    echo "PACKAGE SIZE (compressed):  ${pkgsize} K" >> "$dotmeta"
    echo "PACKAGE SIZE (uncompressed):  ${uncsize} K" >> "$dotmeta"
    if [ "$SR_FOR_SLAPTGET" -eq 1 ]; then
      # Fish them out of the packaging directory.
      REQUIRED=$(cat "$TMP"/package-"$pkgnam"/install/slack-required 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
      echo "PACKAGE REQUIRED:  $REQUIRED" >> "$dotmeta"
      CONFLICTS=$(cat "$TMP"/package-"$pkgnam"/install/slack-conflicts 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
      echo "PACKAGE CONFLICTS:  $CONFLICTS" >> "$dotmeta"
      SUGGESTS=$(cat "$TMP"/package-"$pkgnam"/install/slack-suggests 2>/dev/null | xargs -r)
      echo "PACKAGE SUGGESTS:  $SUGGESTS" >> "$dotmeta"
    fi
    echo "PACKAGE DESCRIPTION:" >> "$dotmeta"
    cat "$dottxt" >> "$dotmeta"
    echo "" >> "$dotmeta"

    [ "$OPT_KEEP_TMP" != 'y' ] && rm -f "$TMP_PKGCONTENTS"

  done
  return 0
}

#-------------------------------------------------------------------------------

function do_groupadd_useradd
# If there is a GROUPADD or USERADD hint for this item, set up the group and username.
# GROUPADD hint format: GROUPADD="<gnum>:<gname> ..."
# USERADD hint format:  USERADD="<unum>:<uname>:[-g<ugroup>:][-d<udir>:][-s<ushell>:][-uargs:...] ..."
#   but if the USERADD hint is messed up, we can take a wild guess or two, see below ;-)
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"

  if [ -n "${HINT_GROUPADD[$itemid]}" ]; then
    for groupstring in ${HINT_GROUPADD[$itemid]}; do
      gnum=''; gname="$itemprgnam"
      for gfield in $(echo $groupstring | tr ':' ' '); do
        case "$gfield" in
          [0-9]* ) gnum="$gfield" ;;
          * ) gname="$gfield" ;;
        esac
      done
      [ -z "$gnum" ] && { log_warning "${itemid}: GROUPADD hint has no GID number" ; break ; }
      if ! getent group "$gname" | grep -q "^${gname}:" 2>/dev/null ; then
        gaddcmd="groupadd -g $gnum $gname"
        log_verbose -a "Adding group: $gaddcmd"
        eval $gaddcmd
      else
        log_verbose -a "Group $gname already exists."
      fi
    done
  fi

  if [ -n "${HINT_USERADD[$itemid]}" ]; then
    for userstring in ${HINT_USERADD[$itemid]}; do
      unum=''; uname="$itemprgnam"; ugroup=""
      udir='/dev/null'; ushell='/bin/false'; uargs=''
      for ufield in $(echo $userstring | tr ':' ' '); do
        case "$ufield" in
          -g* ) ugroup="${ufield:2}" ;;
          -d* ) udir="${ufield:2}" ;;
          -s* ) ushell="${ufield:2}" ;;
          -*  ) uargs="$uargs ${ufield:0:2} ${ufield:2}" ;;
          /*  ) if [ -x "$ufield" ]; then ushell="$ufield"; else udir="$ufield"; fi ;;
          [0-9]* ) unum="$ufield" ;;
          *   ) uname="$ufield" ;;
        esac
      done
      [ -z "$unum" ] && { log_warning "${itemid}: USERADD hint has no UID number" ; break ; }
      if ! getent passwd "$uname" | grep -q "^${uname}:" 2>/dev/null ; then
        [ -z "$ugroup" ] && ugroup="$uname"
        if ! getent group "${ugroup}" | grep -q "^${ugroup}:" 2>/dev/null ; then
          gaddcmd="groupadd -g $unum $ugroup"
          log_verbose -a "Adding group: $gaddcmd"
          eval $gaddcmd
        fi
        uaddcmd="useradd  -u $unum -g $ugroup -c $itemprgnam -d $udir -s $ushell $uargs $uname"
        log_verbose -a "Adding user:  $uaddcmd"
        eval $uaddcmd
      else
        log_verbose -a "User $uname already exists."
      fi
    done
  fi

  return 0
}

#-------------------------------------------------------------------------------

function remove_item
# Remove an item's package(s) from the package repository and the source repository
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  if [ -d "$SR_PKGREPO"/"$itemdir" ]; then
    [ "$OPT_DRY_RUN" != 'y' ] && rm -f "$SR_PKGREPO"/"$itemdir"/.revision
    pkglist=( $(ls "$SR_PKGREPO"/"$itemdir"/*.t?z 2>/dev/null) )
    if [ "${#pkglist[@]}" = 0 ] ; then
      log_normal "There is nothing in $SR_PKGREPO/$itemdir"
    else
      for pkg in "${pkglist[@]}"; do
        pkgbase=$(basename "$pkg")
        if [ "$OPT_DRY_RUN" != 'y' ]; then
          log_normal "Removing package $pkgbase"
          rm "$pkg"
        else
          log_normal "Would remove package $pkgbase"
        fi
        is_installed "$pkg"
        istat=$?
        if [ "$istat" = 0 -o "$istat" = 1 -o "$istat" = 3 ]; then
          log_warning "Package $R_INSTALLED is installed, use removepkg to uninstall it"
        fi
      done
    fi
    if [ "$OPT_DRY_RUN" != 'y' ]; then
      log_normal "Removing directory $SR_PKGREPO/$itemdir"
      rm -rf "$SR_PKGREPO"/"$itemdir"
      up="$(dirname "$itemdir")"
      [ "$up" != '.' ] && rmdir --parents --ignore-fail-on-non-empty "$SR_PKGREPO"/"$up"
    else
      log_normal "Would remove directory $SR_PKGREPO/$itemdir"
    fi
  fi

  if [ -d "$SR_SRCREPO"/"$itemdir" ]; then
    [ "$OPT_DRY_RUN" != 'y' ] && rm -f "$SR_SRCREPO"/"$itemdir"/.version
    srclist=( $(ls "$SR_SRCREPO"/"$itemdir"/* 2>/dev/null) )
    for src in "${srclist[@]}"; do
      if [ "$OPT_DRY_RUN" != 'y' ]; then
        log_normal "Removing source $(basename "$src")"
        rm "$src"
      else
        log_normal "Would remove source $(basename "$src")"
      fi
    done
    if [ "$OPT_DRY_RUN" != 'y' ]; then
      log_normal "Removing directory $SR_SRCREPO/$itemdir"
      rm -rf "$SR_SRCREPO"/"$itemdir"
      up="$(dirname "$itemdir")"
      [ "$up" != '.' ] && rmdir --parents --ignore-fail-on-non-empty "$SR_SRCREPO"/"$up"
    else
      log_normal "Would remove directory $SR_SRCREPO/$itemdir"
    fi
  fi

  if [ "$OPT_DRY_RUN" != 'y' ]; then
    echo "$itemid: Removed. NEWLINE" >> "$CHANGELOG"
    log_success ":-) $itemid: Removed (-:"
  else
    log_success ":-) $itemid would be removed [dry run] (-:"
  fi
  OKLIST+=( "$itemid" )

  return 0
}
