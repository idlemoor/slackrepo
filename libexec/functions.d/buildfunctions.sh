#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for slackrepo
#   build_item_packages
#   build_ok
#   build_failed
#   build_skipped
#   do_groupadd_useradd
#   chroot_setup
#   chroot_destroy
#-------------------------------------------------------------------------------

function build_item_packages
# Build the package(s) for a single item
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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local -a pkglist tempdownlist

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
    # Let's assume shell globbing chars won't appear in any sane VERSION ;-)
    INFODOWNLIST[$itemid]="${INFODOWNLIST[$itemid]//${INFOVERSION[$itemid]}/$NEWVERSION}"
    INFOVERSION[$itemid]="$NEWVERSION"
  fi

  # Save the existing source to a temporary stash.
  allsourcedir="$SR_SRCREPO"/"$itemdir"
  archsourcedir="$allsourcedir"/"$SR_ARCH"
  allsourcestash="$MYTMPDIR"/prev_source
  archsourcestash="${allsourcestash}_${SR_ARCH}"
  SOURCESTASH=""
  if [ -d "$archsourcedir" ]; then
    SOURCESTASH="$archsourcestash"
    mkdir -p "$SOURCESTASH"
    find "$SOURCESTASH" -type f -maxdepth 1 -exec rm {} \;
    find "$archsourcedir" -type f -maxdepth 1 -exec cp {} "$SOURCESTASH" \;
  elif [ -d "$allsourcedir" ]; then
    SOURCESTASH="$allsourcestash"
    mkdir -p "$SOURCESTASH"
    find "$SOURCESTASH" -type f -maxdepth 1 -exec rm {} \;
    find "$allsourcedir" -type f -maxdepth 1 -exec cp {} "$SOURCESTASH" \;
  fi
  # If there were no actual source files, remove the stash directory:
  [ -n "$SOURCESTASH" ] && rmdir --ignore-fail-on-non-empty "$SOURCESTASH"

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
       build_skipped "$itemid"
       return 5
       ;;
    6) # nodownload hint (probably needs manual download due to licence agreement)
       log_warning -n -a ":-/ SKIPPED $itemid - please download the source /-:"
       log_normal "  from: ${INFODOWNLIST[$itemid]}"
       log_normal "  to:   ${SRCDIR[$itemid]}"
       # We ought to prepare that directory ;-)
       mkdir -p "${SRCDIR[$itemid]}"
       build_skipped "$itemid"
       return 5
       ;;
  esac

  # Copy or link the source (if any) into the temporary SlackBuild directory
  # (need to copy if this is a chroot, it might be on an inaccessible mounted FS)
  if [ -n "${INFODOWNLIST[$itemid]}" ]; then
    if [ "$SYS_OVERLAYFS" = 'y' ]; then
      cp -a "${SRCDIR[$itemid]}"/* "$MYTMPIN/"
    else
      # "Copy / is dandy / but linky / is quicky" [after Ogden Nash]
      ln -sf -t "$MYTMPIN/" "${SRCDIR[$itemid]}"/*
    fi
  fi

  # Work out BUILD
  # Get the value from the SlackBuild
  unset BUILD
  buildassign=$(grep '^BUILD=' "$MYTMPIN"/"$itemfile")
  if [ -z "$buildassign" ]; then
    buildassign="BUILD=1"
    log_warning -a "${itemid}: no \"BUILD=\" in $itemfile; using 1"
  fi
  eval $buildassign
  #### This still isn't right when the backup is a different version :-(
  if [ "${BUILDINFO[$itemid]:0:3}" = 'add' -o "${BUILDINFO[$itemid]:0:18}" = 'update for version' ]; then
    # We can just use the SlackBuild's BUILD
    SR_BUILD="$BUILD"
  else
    # Increment the existing packages' BUILD, or use the SlackBuild's (whichever is greater).
    oldpkgs=( "$SR_PKGREPO"/"$itemdir"/*.t?z )
    if [ "${oldpkgs[0]}" = "$SR_PKGREPO"/"$itemdir"/'*.t?z' ]; then
      # no existing packages
      oldbuild=0
    else
      # If there are multiple packages from one SlackBuild, and they all have
      # different BUILD numbers, frankly we are screwed, so just use the first:
      oldbuild=$(echo "${oldpkgs[0]}" | sed -e 's/^.*-//' -e 's/[^0-9]*$//' )
    fi
    backuppkgs=( "$SR_PKGBACKUP"/"$itemdir"/*.t?z )
    if [ "${backuppkgs[0]}" != "$SR_PKGBACKUP"/"$itemdir"/'*.t?z' ]; then
      # backup(s) exist, just use the first (as above)
      backupbuild=$(echo "${backuppkgs[0]}" | sed -e 's/^.*-//' -e 's/[^0-9]*$//' )
      [ "$backupbuild" -gt "$oldbuild" ] && oldbuild="$backupbuild"
    fi
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

  SLACKBUILDCMD="sh ./$itemfile"
  [ "$OPT_VERY_VERBOSE" = 'y' ] && [ "$DOCOLOUR"  = 'y' ] && SLACKBUILDCMD="/usr/libexec/slackrepo/unbuffer $SLACKBUILDCMD"
  [ -n "$SUDO" ] && [ -x /usr/bin/fakeroot ] && SLACKBUILDCMD="fakeroot $SLACKBUILDCMD"

  # Process other hints for the build:

  # NUMJOBS (with MAKEFLAGS and NUMJOBS env vars) ...
  NUMJOBS="${HINT_NUMJOBS[$itemid]:-$SR_NUMJOBS}"
  tempmakeflags="MAKEFLAGS='${HINT_NUMJOBS[$itemid]:-$SR_NUMJOBS}'"

  # ... OPTIONS ...
  options="${HINT_OPTIONS[$itemid]}"
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
      # Most of the current bozo downloaders only download one file anyway :-)
      tempdownlist=( ${INFODOWNLIST[$itemid]} )
      count=0
      while read sourcefile; do
        target=$(basename "${tempdownlist[$count]}")
        ( cd "$MYTMPIN"; [ ! -e "$target" ] && ln -s "$(basename "$sourcefile")" "$target" )
        count=$(( count + 1 ))
      done < <(ls -rt "$SR_SRCREPO"/"$itemdir" 2>/dev/null)
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
    'unset'* )
      eval "${special//_/ }"
      ;;
    'noremove' )
      log_verbose "Special action: noremove"
      noremove='y'
      ;;
    * )
      log_warning "${itemid}: Hint SPECIAL=\"$special\" not recognised"
      ;;
    esac
  done

  # Setup the chroot
  # (to be destroyed below, or by build_failed if necessary)
  chroot_setup

  # Process GROUPADD and USERADD hints, preferably inside the chroot :-)
  do_groupadd_useradd "$itemid"

  # Get all dependencies installed
  install_deps "$itemid" || { build_failed "$itemid"; return 1; }

  # Remove any existing packages (some builds fail if already installed)
  # (... this might not be entirely appropriate for gcc or glibc ...)
  if [ "$noremove" != 'y' ]; then
    uninstall_packages "$itemid"
  fi

  # Remember the build start time and estimate the build finish time
  estbuildsecs=''
  read prevsecs prevbogomips guessflag < <(db_get_buildsecs "$itemid")
  if [ -n "$prevsecs" ] && [ -n "$prevbogomips" ]; then
    if [ "$guessflag" = '=' ] || [ "$prevsecs" -lt 120 ] || [ "${BOGOCOUNT:-0}" -lt 5 ]; then
      estbuildsecs=$(echo "scale=3; ${prevsecs}*${prevbogomips}/${SYS_BOGOMIPS}+1" | bc | sed 's/\..*//')
    elif [ "$guessflag" = '~' ]; then
      BOGOSLOPE=$(echo "scale=3; (($BOGOCOUNT*$BOGOSUMXY)-($BOGOSUMX*$BOGOSUMY))/(($BOGOCOUNT*$BOGOSUMX2)-($BOGOSUMX*$BOGOSUMX))" | bc)
      BOGOCONST=$(echo "scale=3; ($BOGOSUMY - ($BOGOSLOPE*$BOGOSUMX))/$BOGOCOUNT*60.0" | bc)
      estbuildsecs=$(echo "scale=3; $BOGOSLOPE*(${prevsecs}*${prevbogomips}/${SYS_BOGOMIPS})+$BOGOCONST+1" | bc | sed 's/\..*//')
    fi
  fi
  buildstarttime="$(date '+%s')"
  eta=""
  [ -n "$estbuildsecs" ] && eta="ETA ${guessflag/=/}$(date --date=@"$(( buildstarttime + estbuildsecs + 30 ))" '+%H:%M')"

  # Build it
  touch "$MYTMPDIR"/start
  runmsg=$(format_left_right "Running $itemfile ..." "$eta")
  log_normal -a "$runmsg"
  log_verbose -a "$SLACKBUILDCMD"
  if [ "$OPT_VERY_VERBOSE" = 'y' ]; then
    echo ''
    echo '---->8-------->8-------->8-------->8-------->8-------->8-------->8-------->8---'
    echo ''
    set -o pipefail
    if [ "$SYS_MULTILIB" = "y" ] && [ "$ARCH" = 'i486' -o "$ARCH" = 'i686' ]; then
      ${CHROOTCMD}sh -c ". /etc/profile.d/32dev.sh; cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    else
      ${CHROOTCMD}sh -c "cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    fi
    set +o pipefail
    echo '----8<--------8<--------8<--------8<--------8<--------8<--------8<--------8<---'
    echo ''
  else
    if [ "$SYS_MULTILIB" = "y" -a "$ARCH" = 'i486' ]; then
      ${CHROOTCMD}sh -c ". /etc/profile.d/32dev.sh; cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" >> "$ITEMLOG" 2>&1
      buildstat=$?
    else
      ${CHROOTCMD}sh -c "cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" >> "$ITEMLOG" 2>&1
      buildstat=$?
    fi
  fi
  buildfinishtime="$(date '+%s')"
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS

  # If there's a config.log in the obvious place, save it
  configlog="${CHROOTDIR}$SR_TMP"/"$itemprgnam"-"${INFOVERSION[$itemid]}"/config.log
  if [ -f "$configlog" ]; then
    cp "$configlog" "$ITEMLOGDIR"
  fi

  if [ "$buildstat" != 0 ]; then
    log_error -a "${itemid}: $itemfile failed (status $buildstat)"
    build_failed "$itemid"
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=( "${CHROOTDIR}${MYTMPOUT}"/*.t?z )
  if [ "${pkglist[0]}" = "${CHROOTDIR}${MYTMPOUT}"/'*.t?z' ]; then
    # no packages: let's get sneaky and snarf it/them from where makepkg said it/them was/were going ;-)
    logpkgs=( $(grep "Slackware package .* created." "$ITEMLOG" | cut -f3 -d" ") )
    if [ "${#logpkgs[@]}" = 0 ]; then
      log_error -a "${itemid}: No packages were created"
      build_failed "$itemid"
      return 6
    else
      for pkgpath in "${logpkgs[@]}"; do
        if [ -f "$MYTMPIN/README" -a -f "$MYTMPIN"/"$(basename "$itemfile" .SlackBuild)".info ]; then
          # it's probably an SBo SlackBuild, so complain and don't retag
          if [ -f "${CHROOTDIR}$pkgpath" ]; then
            log_warning -a "${itemid}: Package should have been in \$OUTPUT: $pkgpath"
            mv "${CHROOTDIR}$pkgpath" "$MYTMPOUT"
          else
            log_error -a "${itemid}: Package not found: $pkgpath"
            build_failed "$itemid"
            return 6
          fi
        else
          pkgnam=$(basename "$pkgpath")
          currtag=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
          if [ "$currtag" != "$SR_TAG" ]; then
            # retag it. If it's not found, sod it...
            pkgtype=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
            mv "${CHROOTDIR}$pkgpath" "$MYTMPOUT"/"${pkgnam/%$currtag.$pkgtype/${SR_TAG}.$pkgtype}"
          else
            mv "${CHROOTDIR}$pkgpath" "$MYTMPOUT"/
          fi
        fi
      done
      pkglist=( "$MYTMPOUT"/*.t?z )
    fi
  else
    if [ -n "${CHROOTDIR}" ]; then
      mv "${CHROOTDIR}${MYTMPOUT}"/*.t?z "${MYTMPOUT}"
    fi
  fi

  if [ "$OPT_TEST" = 'y' ]; then
    # this will happen inside the chw00t :D
    test_package "$itemid" "${pkglist[@]}" || { build_failed "$itemid"; return 7; }
  fi

  chroot_destroy

  # update pkgnam to itemid table
  if [ "$OPT_DRY_RUN" != 'y' ]; then
    db_del_pkgnam_itemid "$itemid"
    for pkgpath in "${pkglist[@]}"; do
      pkgbasename=$(basename "$pkgpath")
      log_important "Built ok:  $pkgbasename"
      pkgnam=$(echo "$pkgbasename" | rev | cut -f4- -d- | rev)
      db_set_pkgnam_itemid "$pkgnam" "$itemid"
    done
  fi

  # update build time information
  # add 1 to round it up so it's never zero
  actualsecs=$(( buildfinishtime - buildstarttime + 1 ))
  db_set_buildsecs "$itemid" "$actualsecs"
  if [ -n "$estbuildsecs" ]; then
    secsdiff=$(( actualsecs - estbuildsecs ))
    if [ "$guessflag" = '~' ] && [ "${estbuildsecs:-0}" -gt 120 ] && [ "${secsdiff//-/}" -gt 30 ] && [ "${BOGOCOUNT:-0}" -lt 200 ]; then
      # yes, this is crazy :P ... 200 data points should be enough. We use minutes to prevent the numbers getting enormous.
      BOGOCOUNT=$(( BOGOCOUNT + 1 ))
      BOGOSUMX=$(echo "scale=3; $BOGOSUMX+$estbuildsecs/60.0" | bc)
      BOGOSUMY=$(echo "scale=3; $BOGOSUMY+$actualsecs/60.0"   | bc)
      BOGOSUMX2=$(echo "scale=3; $BOGOSUMX2 + ($estbuildsecs/60.0)*($estbuildsecs/60.0)" | bc)
      BOGOSUMXY=$(echo "scale=3; $BOGOSUMXY + ($estbuildsecs/60.0)*($actualsecs/60.0)"   | bc)
      db_set_misc bogostuff "BOGOCOUNT=$BOGOCOUNT; BOGOSUMX=$BOGOSUMX; BOGOSUMY=$BOGOSUMY; BOGOSUMX2=$BOGOSUMX2; BOGOSUMXY=$BOGOSUMXY;"
    fi
  fi

  if [ "${HINT_INSTALL[$itemid]}" = 'y' ] || [ "$OPT_INSTALL" = 'y' -a "${HINT_INSTALL[$itemid]}" != 'n' ]; then
    install_packages "$itemid" || { build_failed "$itemid"; return 8; }
  fi
  #### set the new pkgbase in KEEPINSTALLED[$pkgid]

  build_ok "$itemid"  # \o/
  return 0
}

#-------------------------------------------------------------------------------

function build_ok
# Store packages, write metadata, cleanup and log for a build that has succeeded
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  STATUS[$itemid]="ok"
  OKLIST+=( "$itemid" )

  [ "$OPT_KEEP_TMP" != 'y' ] && rm -rf "$MYTMPIN"

  # ---- Store the packages ----
  if [ "$OPT_DRY_RUN" = 'y' ]; then
    # put the packages into the special dryrun repo
    mkdir -p "$DRYREPO"/"$itemdir"
    rm -rf "${DRYREPO:?NotSetDRYREPO}"/"$itemdir"/*
    mv "$MYTMPOUT"/* "$DRYREPO"/"$itemdir"/
  else
    # save any existing packages and metadata to the backup repo
    if [ -d "$SR_PKGREPO"/"$itemdir" -a -n "$SR_PKGBACKUP" ]; then
      backupdir="$SR_PKGBACKUP"/"$itemdir"
      if [ -d "$backupdir" ]; then
        mv "$backupdir" "$backupdir".prev
      else
        mkdir -p "$(dirname "$backupdir")"
      fi
      mv "$SR_PKGREPO"/"$itemdir" "$backupdir"
      rm -rf "$backupdir".prev
      # if there's a stashed source, save it to the backup repo
      if [ -d "$SOURCESTASH" ]; then
        mv "$SOURCESTASH" "$backupdir"/"$(basename "${SOURCESTASH/prev_/}")"
      fi
      # save old revision data to a file in the backup repo
      revisionfile="$backupdir"/revision
      dbrevdata=( $(db_get_rev "$itemid") )
      echo "$itemid" '/' "${dbrevdata[@]}" > "$revisionfile"
      deplist="${dbrevdata[0]//,/ }"
      if [ "$deplist" != '/' ]; then
        for depid in ${deplist}; do
          echo "$itemid $depid $(db_get_rev "$depid")" >> "$revisionfile"
        done
      fi
      # log what happened
      for backpack in "$backupdir"/*.t?z; do
        [ -e "$backpack" ] || break
        log_verbose "Backed up: $(basename "$backpack")"
      done
    fi
    # put the new packages into the real package repo
    mkdir -p "$SR_PKGREPO"/"$itemdir"
    mv "$MYTMPOUT"/* "$SR_PKGREPO"/"$itemdir"/
  fi
  rmdir "$MYTMPOUT"

  # ---- Write the metadata ----
  write_pkg_metadata "$itemid"  # sets $CHANGEMSG

  # ---- Cleanup ----
  # We can skip this if we were using the chroot :-)
  if [ "$SYS_OVERLAYFS" != 'y' ]; then
    # uninstall the deps
    if [ "$OPT_DRY_RUN" = 'y' ] || [ "${HINT_INSTALL[$itemid]}" != 'y' ] || [ "$OPT_INSTALL" != 'y' ]; then
      uninstall_deps "$itemid"
    fi
    #### IMPORTANT #### some cleanup hints (depmod, possibly others) are needed even if we're chroot ####
    # smite the temporary storage (this won't always kill everything, but it's good enough for saving space)
    [ "$OPT_KEEP_TMP" != 'y' ] && rm -rf "${SR_TMP:?NotSetSR_TMP}"/"$itemprgnam"* "${SR_TMP:?NotSetSR_TMP}"/package-"$itemprgnam"
  fi

  # ---- Logging ----
  buildopt=''
  [ "$OPT_DRY_RUN" = 'y' ] && buildopt=' [dry run]'
  [ "$OPT_INSTALL" = 'y' ] && buildopt=' [install]'
  log_success ":-) ${itemid}: $CHANGEMSG$buildopt (-:"

  return 0
}

#-------------------------------------------------------------------------------

function build_failed
# Log and cleanup for a build that has failed
# $1 = itemid
# Also uses BUILDINFO[$itemid] set by needs_build()
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  STATUS[$itemid]="failed"
  FAILEDLIST+=( "$itemid" )

  if [ "$OPT_QUIET" != 'y' ]; then
    errorscan_itemlog | tee -a "$MAINLOG"
  else
    errorscan_itemlog >> "$MAINLOG"
  fi
  log_error -n "See $ITEMLOG"

  if [ -n "${CHROOTDIR}" ]; then
    chroot_destroy
  elif [ "${HINT_INSTALL[$itemid]}" = 'n' ] || [ "$OPT_INSTALL" != 'y' -a "${HINT_INSTALL[$itemid]}" != 'y' ]; then
    uninstall_deps "$itemid"
    #### reinstate packages that we uninstalled prior to building
  fi

  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    rm -rf "$MYTMPIN" "$MYTMPOUT"
    rm -rf "${SR_TMP:?NotSetSR_TMP}"/"$itemprgnam"* "${SR_TMP:?NotSetSR_TMP}"/package-"$itemprgnam"
  fi

  log_error -n ":-( $itemid FAILED )-:"

  return 0
}

#-------------------------------------------------------------------------------

function build_skipped
# Log and cleanup for a build that has been skipped
# $1 = itemid
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"

  STATUS[$itemid]="skipped"
  SKIPPEDLIST+=( "$itemid" )

  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    rm -rf "$MYTMPIN" "$MYTMPOUT"
    rm -rf "${SR_TMP:?NotSetSR_TMP}"/"$itemprgnam"* "${SR_TMP:?NotSetSR_TMP}"/package-"$itemprgnam"
  fi
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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"

  if [ -n "${HINT_GROUPADD[$itemid]}" ]; then
    for groupstring in ${HINT_GROUPADD[$itemid]}; do
      gnum=''; gname="$itemprgnam"
      for gfield in $(echo "$groupstring" | tr ':' ' '); do
        case "$gfield" in
          [0-9]* ) gnum="$gfield" ;;
          * ) gname="$gfield" ;;
        esac
      done
      [ -z "$gnum" ] && { log_warning "${itemid}: GROUPADD hint has no GID number" ; break ; }
      if ! getent group "$gname" | grep -q "^${gname}:" 2>/dev/null ; then
        gaddcmd="groupadd -g $gnum $gname"
        log_verbose -a "Adding group: $gaddcmd"
        eval "$gaddcmd"
      else
        log_verbose -a "Group $gname already exists."
      fi
    done
  fi

  if [ -n "${HINT_USERADD[$itemid]}" ]; then
    for userstring in ${HINT_USERADD[$itemid]}; do
      unum=''; uname="$itemprgnam"; ugroup=""
      udir='/dev/null'; ushell='/bin/false'; uargs=''
      for ufield in $(echo "$userstring" | tr ':' ' '); do
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
          eval "${CHROOTCMD}${SUDO}$gaddcmd"
        fi
        uaddcmd="useradd  -u $unum -g $ugroup -c $itemprgnam -d $udir -s $ushell $uargs $uname"
        log_verbose -a "Adding user:  $uaddcmd"
        eval "${CHROOTCMD}${SUDO}$uaddcmd"
      else
        log_verbose -a "User $uname already exists."
      fi
    done
  fi

  return 0
}

#-------------------------------------------------------------------------------

function chroot_setup
# Setup a temporary chroot environment at $MYTMPDIR/chroot using overlayfs
# Also sets the global variables $CHROOTCMD and $CHROOTDIR
# Return status:
# 0 = it worked
# 1 = SYS_OVERLAYFS is not set, or could not mount the overlay
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2
  CHROOTCMD=''
  [ "$SYS_OVERLAYFS" != 'y' ] && return 1
  ${SUDO}mkdir -p "$MYTMPDIR"/{changes,workdir,chroot}
  ${SUDO}mount -t overlay overlay -olowerdir=/,upperdir="$MYTMPDIR"/changes,workdir="$MYTMPDIR"/workdir "$MYTMPDIR"/chroot || return 1
  #### do we actually need any of these?
  # ${SUDO}mount -t devpts  devpts  -ogid=5,mode=620 "$MYTMPDIR"/chroot/dev/pts
  # ${SUDO}mount -t tmpfs   shm     "$MYTMPDIR"/chroot/dev/shm
  # ${SUDO}mount -t proc    proc    "$MYTMPDIR"/chroot/proc
  # ${SUDO}mount -t sysfs   sysfs   "$MYTMPDIR"/chroot/sys
  CHROOTDIR="${MYTMPDIR}/chroot/"   # note the trailing slash
  CHROOTCMD="chroot ${CHROOTDIR} "  # note the trailing space
  return 0
}

#-------------------------------------------------------------------------------

function chroot_destroy
# Copy wanted files out of the temporary chroot, and warn about everything else
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2
  [ -z "$CHROOTDIR" ] && return 0
  log_normal "Unmounting chroot ... "
  umount "$CHROOTDIR" || return 0
  if [ "$OPT_KEEP_TMP" = 'y' ]; then
    rsync -rlptgo "$MYTMPDIR"/changes/"$SR_TMP"/ "$SR_TMP"/
  fi
  log_done
  rm -rf "$MYTMPDIR"/changes/tmp
  if [ -f "$MYTMPDIR"/start ]; then
    crap=$(find "$MYTMPDIR"/changes -newer "$MYTMPDIR"/start -print | sed -e "s#"$MYTMPDIR"/changes##" | sort)
    if [ -n "$crap" ]; then
      log_warning "$itemid: Files/directories were modified during the build"
      printf "  %s\n" ${crap}
    fi
  fi
  rm -rf "$MYTMPDIR"/changes
  unset CHROOTCMD CHROOTDIR
  return 0
}
