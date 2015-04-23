#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for slackrepo
#   build_item_packages
#   build_ok
#   build_failed
#   build_skipped
#   chroot_setup
#   chroot_report
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
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local -a pkglist tempdownlist

  buildopt=''
  [ "$OPT_DRY_RUN" = 'y' ] && buildopt=' [dry run]'
  [ "$OPT_INSTALL" = 'y' ] && buildopt=' [install]'
  log_itemstart "$itemid" "Starting $itemid (${STATUSINFO[$itemid]})$buildopt"

  MYTMPIN="$MYTMPDIR/slackbuild_$itemprgnam"
  # initial wipe of $MYTMPIN, even if $OPT_KEEP_TMP is set
  rm -rf "$MYTMPIN"
  cp -a "$SR_SBREPO/$itemdir" "$MYTMPIN"

  if [ "$OPT_LINT" = 'y' ]; then
    test_slackbuild "$itemid"
    [ $? -gt 1 ] && return 7
  fi

  # Apply version hint
  NEWVERSION="${HINT_VERSION[$itemid]}"
  if [ -n "$NEWVERSION" -a "${INFOVERSION[$itemid]}" != "$NEWVERSION" ]; then
    # Fiddle with $VERSION -- usually doomed to failure, but not always ;-)
    log_info -a "Setting VERSION=$NEWVERSION (was ${INFOVERSION[$itemid]})"
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
    find "$SOURCESTASH" -type f -maxdepth 1 -exec rm -f {} \;
    find "$archsourcedir" -type f -maxdepth 1 -exec cp {} "$SOURCESTASH" \;
  elif [ -d "$allsourcedir" ]; then
    SOURCESTASH="$allsourcestash"
    mkdir -p "$SOURCESTASH"
    find "$SOURCESTASH" -type f -maxdepth 1 -exec rm -f {} \;
    find "$allsourcedir" -type f -maxdepth 1 -exec cp {} "$SOURCESTASH" \;
  fi
  # If there were no actual source files, remove the stash directory:
  [ -n "$SOURCESTASH" ] && rmdir --ignore-fail-on-non-empty "$SOURCESTASH"

  # Get the source (including check for unsupported/untested/nodownload)
  verify_src "$itemid" "log_important"
  case $? in
    0) # already got source, and it's good
       [ "$OPT_LINT" = 'y' -a -z "${HINT_NODOWNLOAD[$itemid]}" ] && test_download "$itemid"
       ;;
    1|2|3|4)
       # already got source but it's bad, or not got source, or wrong version => get it
       download_src "$itemid" || { build_failed "$itemid"; return 2; }
       verify_src "$itemid" "log_error" || { build_failed "$itemid"; return 3; }
       ;;
    5) # unsupported/untested
       STATUS[$itemid]='unsupported'
       STATUSINFO[$itemid]="${INFODOWNLIST[$itemid]} on $SR_ARCH"
       build_skipped "$itemid" "${STATUSINFO[$itemid]}" ''
       return 5
       ;;
    6) # nodownload hint (probably needs manual download due to licence agreement)
       STATUS[$itemid]='skipped'
       STATUSINFO[$itemid]="Please download the source\n  from: ${INFODOWNLIST[$itemid]}\n  to:   ${SRCDIR[$itemid]}"
       # We ought to prepare that directory ;-)
       mkdir -p "${SRCDIR[$itemid]}"
       build_skipped "$itemid" 'Source not available' "${STATUSINFO[$itemid]}"
       return 5
       ;;
  esac

  # Copy or link the source (if any) into the temporary SlackBuild directory
  # (need to copy if this is a chroot, it might be on an inaccessible mounted FS)
  if [ -n "${INFODOWNLIST[$itemid]}" ]; then
    if [ "$OPT_CHROOT" = 'y' ]; then
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
  if [ "${STATUSINFO[$itemid]:0:3}" = 'add' -o "${STATUSINFO[$itemid]:0:18}" = 'update for version' ]; then
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
      # backup(s) exist, just look at the first (as above)
      # if the version is the same, we need the higher build no.
      backupver=$(echo "${backuppkgs[0]}" | rev | cut -f3 -d- | rev )
      backupbuild=$(echo "${backuppkgs[0]}" | sed -e 's/^.*-//' -e 's/[^0-9]*$//' )
      [ "$backupver" = "${INFOVERSION[$itemid]}" ] && [ "$backupbuild" -gt "$oldbuild" ] && oldbuild="$backupbuild"
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

  SLACKBUILDOPTS="env"
  SLACKBUILDRUN="sh ./$itemfile"

  # Process options and hints for the build:

  # ... NUMJOBS (with MAKEFLAGS and NUMJOBS env vars) ...
  NUMJOBS="${HINT_NUMJOBS[$itemid]:-$SR_NUMJOBS}"
  SLACKBUILDOPTS="${SLACKBUILDOPTS} MAKEFLAGS='${HINT_NUMJOBS[$itemid]:-$SR_NUMJOBS}'"

  # ... OPTIONS ...
  [ -n "${HINT_OPTIONS[$itemid]}" ] && SLACKBUILDOPTS="${SLACKBUILDOPTS} ${HINT_OPTIONS[$itemid]}"

  # ... ANSWER ...
  [ -n "${HINT_ANSWER[$itemid]}" ] && SLACKBUILDOPTS="echo -e '${HINT_ANSWER[$itemid]}' | $SLACKBUILDOPTS"

  # ... PRAGMA ...
  hintnoremove='n'
  hintnofakeroot='n'
  restorevars=''
  for pragma in ${HINT_PRAGMA[$itemid]}; do
    case "$pragma" in
    'multilib_ldflags' )
      if [ "$SYS_MULTILIB" = 'y' ]; then
        # This includes the rare case when an i486 cross-compile on x86_64 needs -L/usr/lib
        log_info -a "Pragma: multilib_ldflags"
        libdirsuffix=''
        [ "$SR_ARCH" = 'x86_64' ] && libdirsuffix='64'
        sed -i -e "s;^\./configure ;LDFLAGS=\"-L/usr/lib$libdirsuffix\" &;" "$MYTMPIN/$itemfile"
      fi
      ;;
    'stubs-32' )
      if [ "$SYS_ARCH" = 'x86_64' -a "$SYS_MULTILIB" = 'n' -a ! -e /usr/include/gnu/stubs-32.h ]; then
        log_info -a "Pragma: stubs-32"
        ln -s /usr/include/gnu/stubs-64.h /usr/include/gnu/stubs-32.h
        if [ -z "${HINT_CLEANUP[$itemid]}" ]; then
          HINT_CLEANUP[$itemid]="rm /usr/include/gnu/stubs-32.h"
        else
          HINT_CLEANUP[$itemid]="${HINT_CLEANUP[$itemid]}; rm /usr/include/gnu/stubs-32.h"
        fi
      fi
      ;;
    'download_basename' )
      log_info -a "Pragma: download_basename"
      # We're going to guess that the timestamps in the source repo indicate the
      # order in which files were downloaded and therefore the order in INFODOWNLIST.
      # Most of the current bozo downloaders only download one file anyway :-)
      tempdownlist=( ${INFODOWNLIST[$itemid]} )
      count=0
      while read sourcefile; do
        source="${sourcefile##*/}"
        # skip subdirectories (and don't increment count)
        if [ -f "$SR_SRCREPO"/"$itemdir"/"$sourcefile" ]; then
          target="${tempdownlist[$count]##*/}"
          ( cd "$MYTMPIN"; [ -n "$target" ] && [ ! -e "$target" ] && ln -s "$source" "$target" )
          count=$(( count + 1 ))
        fi
      done < <(ls -rt "$SR_SRCREPO"/"$itemdir" 2>/dev/null)
      ;;
    'no_make_test' )
      log_info -a "Pragma: no_make_test"
      sed -i -e "s/make test/: # make test/" "$MYTMPIN"/"$itemfile"
      ;;
    'noexport_ARCH' )
      log_info -a "Pragma: noexport_ARCH"
      sed -i -e "s/^PRGNAM=.*/&; ARCH='$SR_ARCH'/" "$MYTMPIN"/"$itemfile"
      unset ARCH
      ;;
    'noexport_BUILD' | 'noexport_TAG' )
      log_info -a "Pragma: ${pragma}"
      var="${pragma/noexport_/}"
      sed -i -e "s/^${var}=.*/${var}='${!var}'/" "$MYTMPIN"/"$itemfile"
      unset "${var}"
      ;;
    'unset'* )
      varname="${pragma/unset_/}"
      assignment="$(env | grep "^${varname}=")"
      if [ -n "$assignment" ]; then
        log_info -a "Pragma: ${pragma}"
        restorevars="${restorevars}export $(echo "${assignment}" | sed -e 's/^/\"/' -e 's/$/\"/'); "
        eval "unset ${varname}"
      fi
      ;;
    'noremove' )
      log_info -a "Pragma: noremove"
      hintnoremove='y'
      ;;
    'nofakeroot' )
      log_info -a "Pragma: nofakeroot"
      hintnofakeroot='y'
      ;;
    'abstar' )
      log_info -a "Pragma: abstar"
      sed -i -e "s/^tar .*/& --absolute-names/" "$MYTMPIN"/"$itemfile"
      ;;
    * )
      log_warning -a "${itemid}: Hint PRAGMA=\"$pragma\" not recognised"
      ;;
    esac
  done

  # ... fakeroot ...
  if [ -n "$SUDO" ] && [ -x /usr/bin/fakeroot ]; then
    if [ "$hintnofakeroot" = 'y' ]; then
      SLACKBUILDRUN="${SUDO}${SLACKBUILDRUN}"
    else
      SLACKBUILDRUN="fakeroot ${SLACKBUILDRUN}"
    fi
  fi

  # ... nice ...
  [ "${OPT_NICE:-0}" != '0' ] && SLACKBUILDRUN="nice -n $OPT_NICE $SLACKBUILDRUN"

  # ... and finally, VERBOSE/--color
  [ "$OPT_VERBOSE" = 'y' ] && [ "$DOCOLOUR" = 'y' ] && SLACKBUILDRUN="/usr/libexec/slackrepo/unbuffer $SLACKBUILDRUN"

  # Finished assembling the command line.
  SLACKBUILDCMD="${SLACKBUILDOPTS} ${SLACKBUILDRUN}"

  # Setup the chroot
  # (to be destroyed below, or by build_failed if necessary)
  chroot_setup

  # Get all dependencies installed
  install_deps "$itemid"
  if [ $? != 0 ]; then
    build_failed "$itemid"
    [ -n "$restorevars" ] && eval "$restorevars"
    return 1
  fi

  # Remove any existing packages for the item to be built
  # (some builds fail if already installed)
  # (... this might not be entirely appropriate for gcc or glibc ...)
  if [ "$hintnoremove" != 'y' ]; then
    uninstall_packages "$itemid"
  fi

  # Process GROUPADD and USERADD hints, preferably inside the chroot :-)
  if [ -n "${HINT_GROUPADD[$itemid]}" ] || [ -n "${HINT_USERADD[$itemid]}" ]; then
    log_info -a "Adding groups and users:"
    if [ -n "${HINT_GROUPADD[$itemid]}" ]; then
      log_info -a "  ${HINT_GROUPADD[$itemid]}"
      eval $(echo "${HINT_GROUPADD[$itemid]}" | sed "s#groupadd #${CHROOTCMD}${SUDO}groupadd #g")
    fi
    if [ -n "${HINT_USERADD[$itemid]}" ]; then
      log_info -a "  ${HINT_USERADD[$itemid]}"
      eval $(echo "${HINT_USERADD[$itemid]}" | sed "s#useradd #${CHROOTCMD}${SUDO}useradd #g")
    fi
  fi

  # Remember the build start time and estimate the build finish time
  estbuildsecs=''
  read prevsecs prevmhz guessflag < <(db_get_buildsecs "$itemid")
  if [ -n "$prevsecs" ] && [ -n "$prevmhz" ]; then
    estbuildsecs=$(echo "scale=3; ${prevsecs}*${prevmhz}/${SYS_MHz}+1" | bc | sed 's/\..*//')
  fi
  buildstarttime="$(date '+%s')"
  eta=""
  if [ -n "$estbuildsecs" ]; then
    eta="ETA $(date --date=@"$(( buildstarttime + estbuildsecs + 30 ))" '+%H:%M'):??"
    [ "$guessflag" = '~' ] && [ "$estbuildsecs" -gt "1200" ] && eta="${eta:0:8}?:??"
    [ "$guessflag" = '~' ] && eta="eta ~${eta:4:8}"
  fi

  # Build it
  touch "$MYTMPDIR"/start
  log_normal -a "Running $itemfile ..." "$eta"
  log_info -a "$SLACKBUILDCMD"
  if [ "$OPT_VERBOSE" = 'y' ]; then
    log_verbose '\n---->8-------->8-------->8-------->8-------->8-------->8-------->8-------->8----\n'
    set -o pipefail
    if [ "$SYS_MULTILIB" = "y" ] && [ "$ARCH" = 'i486' -o "$ARCH" = 'i686' ]; then
      ${CHROOTCMD}sh -c ". /etc/profile.d/32dev.sh; cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    else
      ${CHROOTCMD}sh -c "cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    fi
    set +o pipefail
    log_verbose '\n----8<--------8<--------8<--------8<--------8<--------8<--------8<--------8<----\n'
  else
    if [ "$SYS_MULTILIB" = "y" ] && [ "$ARCH" = 'i486' -o "$ARCH" = 'i686' ]; then
      ${CHROOTCMD}sh -c ". /etc/profile.d/32dev.sh; cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" >> "$ITEMLOG" 2>&1
      buildstat=$?
    else
      ${CHROOTCMD}sh -c "cd \"${MYTMPIN}\"; ${SLACKBUILDCMD}" >> "$ITEMLOG" 2>&1
      buildstat=$?
    fi
  fi

  buildfinishtime="$(date '+%s')"
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS
  [ -n "$restorevars" ] && eval "$restorevars"

  # If there's a config.log in the obvious place, save it
  configlog="${CHROOTDIR}${SR_TMP}/${itemprgnam}-${INFOVERSION[$itemid]}/config.log"
  if [ -f "$configlog" ]; then
    cp "$configlog" "$ITEMLOGDIR"
  fi

  if [ "$buildstat" != 0 ]; then
    log_error -a "${itemid}: $itemfile failed (status $buildstat)" "$(date +%T)"
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
            mv "${CHROOTDIR}$pkgpath" "$MYTMPOUT"/"${pkgnam/$currtag.$pkgtype/${SR_TAG}.$pkgtype}"
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

  # update build time information
  # add 1 to round it up so it's never zero
  actualsecs=$(( buildfinishtime - buildstarttime + 1 ))
  db_set_buildsecs "$itemid" "$actualsecs"

  # update pkgnam to itemid table (do this before any attempt to install)
  #### [ "$OPT_DRY_RUN" != 'y' ] && db_del_itemid_pkgnam "$itemid" ####
  #### need something in the db if we just did a dry run of a new item
  #### (but what about an old item where the package names changed?)
  db_del_itemid_pkgnam "$itemid"
  for pkgpath in "${pkglist[@]}"; do
    pkgbasename=$(basename "$pkgpath")
    log_important -a "Built ok:  $pkgbasename" "$(date +%T)"
    #### if [ "$OPT_DRY_RUN" != 'y' ]; then ####
      pkgnam=$(echo "$pkgbasename" | rev | cut -f4- -d- | rev)
      db_set_pkgnam_itemid "$pkgnam" "$itemid"
    #### fi ####
  done

  [ "$OPT_CHROOT" = 'y' ] && chroot_report

  if [ "$OPT_LINT" = 'y' ]; then
    test_package "$itemid" "${pkglist[@]}"
    [ $? -gt 1 ] && { build_failed "$itemid"; return 7; }
  fi

  [ "$OPT_CHROOT" = 'y' ] && chroot_destroy
  rm -f "$MYTMPDIR"/start 2>/dev/null

  if [ "${HINT_INSTALL[$itemid]}" = 'y' ] || [ "$OPT_INSTALL" = 'y' -a "${HINT_INSTALL[$itemid]}" != 'n' ]; then
    install_packages "${pkglist[@]}" || { build_failed "$itemid"; return 8; }
    #### set the new pkgbase in KEEPINSTALLED[$pkgnam] ????
  else
    uninstall_deps "$itemid"
  fi

  [ "$OPT_KEEP_TMP" != 'y' ] && rm -rf "${SR_TMP:?NotSetSR_TMP}"/"$itemprgnam"* "${SR_TMP:?NotSetSR_TMP}"/package-"$itemprgnam"

  build_ok "$itemid"  # \o/
  return 0
}

#-------------------------------------------------------------------------------

function build_ok
# Store packages, write metadata, cleanup and log for a build that has succeeded
# $1 = itemid
# Return status: always 0
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

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
      rm -rf "${backupdir:?NotSetBackupdir}".prev
      # if there's a stashed source, save it to the backup repo
      if [ -d "$SOURCESTASH" ]; then
        rm -rf "${backupdir:?NotSetBackupdir}"/"$(basename "${SOURCESTASH/prev_/}")"
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
        log_info -a "Backed up: $(basename "$backpack")"
      done
    else
      rm -rf "${SR_PKGREPO:?NotSetSR_PKGREPO}"/"$itemdir"/*
    fi
    # put the new packages into the real package repo
    mkdir -p "$SR_PKGREPO"/"$itemdir"
    mv "$MYTMPOUT"/* "$SR_PKGREPO"/"$itemdir"/
  fi
  rmdir "$MYTMPOUT"

  # ---- Write the metadata ----
  write_pkg_metadata "$itemid"  # sets $CHANGEMSG

  # ---- Logging ----
  buildopt=''
  [ "$OPT_DRY_RUN" = 'y' ] && buildopt=' [dry run]'
  [ "$OPT_INSTALL" = 'y' ] && buildopt=' [install]'
  STATUS[$itemid]="ok"
  STATUSINFO[$itemid]="$CHANGEMSG$buildopt"
  log_itemfinish "${itemid}" 'ok' "${STATUSINFO[$itemid]}"

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

  STATUS[$itemid]="failed"
  STATUSINFO[$itemid]="See $ITEMLOG"
  log_info -t "$(errorscan_itemlog)"
  log_error -n "${STATUSINFO[$itemid]}"

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

  log_itemfinish "$itemid" 'failed'

  return 0
}

#-------------------------------------------------------------------------------

function build_skipped
# Log and cleanup for a build that has been skipped or is unsupported
# $1 = itemid
# $2 = message (optional -- supplied to log_itemfinish as $3)
# $3 = extra message for next line (optional -- supplied to log_itemfinish as $4)
# Return status: always 0
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"

  log_itemfinish "$itemid" "${STATUS[$itemid]}" "$2" "$3"

  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    rm -rf "$MYTMPIN" "$MYTMPOUT"
    rm -rf "${SR_TMP:?NotSetSR_TMP}"/"$itemprgnam"* "${SR_TMP:?NotSetSR_TMP}"/package-"$itemprgnam"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function chroot_setup
# Setup a temporary chroot environment at $MYTMPDIR/chroot using overlayfs
# Also sets the global variables $CHROOTCMD and $CHROOTDIR
# Return status:
# 0 = it worked
# 1 = OPT_CHROOT is not set, or could not mount the overlay
{
  CHROOTCMD=''
  [ "$OPT_CHROOT" != 'y' ] && return 1
  mkdir -p "$MYTMPDIR"/{changes,workdir,chroot}
  CHROOTDIR="${MYTMPDIR}/chroot/"   # note the trailing slash
  ${SUDO}mount -t overlay overlay -olowerdir=/,upperdir="$MYTMPDIR"/changes,workdir="$MYTMPDIR"/workdir "$CHROOTDIR" || return 1
  ${SUDO}mount -t proc    proc    "$CHROOTDIR"/proc
  ${SUDO}mount -t tmpfs   shm     "$CHROOTDIR"/dev/shm
  #### do we actually need any of these?
  # ${SUDO}mount -t devpts  devpts  -ogid=5,mode=620 "$CHROOTDIR"/dev/pts
  # ${SUDO}mount -t sysfs   sysfs   "$CHROOTDIR"/sys
  if [ -n "$SUDO" ] && [ ! -d "${CHROOTDIR}/${HOME}" ]; then
    # create $HOME as a (mostly) empty directory
    ${SUDO}mkdir -p "${CHROOTDIR}/${HOME}"
    ${SUDO}chown "${EUID}" "${CHROOTDIR}/${HOME}"
    [ -f ~/.Xauthority ] && cp -a ~/.Xauthority "${CHROOTDIR}/${HOME}"
  fi
  CHROOTCMD="chroot ${CHROOTDIR} "  # note the trailing space
  [ -n "$SUDO" ] && CHROOTCMD="${SUDO} chroot --userspec=${USER} ${CHROOTDIR} "
  return 0
}

#-------------------------------------------------------------------------------

function chroot_report
# Warn about modified files and directories in the chroot
# Return status: always 0
{
  [ -z "$CHROOTDIR" ] && return 0

  if [ -f "$MYTMPDIR"/start ]; then
    crap=$(cd "$MYTMPDIR"/changes; find . -path './tmp' -prune -o  -path ".$HOME/.*/*" -prune -o -newer ../start -print 2>/dev/null)
    if [ -n "$crap" ]; then
      excludes="^/dev/ttyp|^$HOME/.distcc|^$HOME/.cache/g-ir-scanner|^$HOME\$"
      significant="$(echo "$crap" | sed -e "s#^\./#/#" | grep -v -E "$excludes" | sort)"
      if [ -n "$significant" ]; then
        log_warning -a "$itemid: Files/directories were modified during the build"
        log_info -t -a "${significant}"
      fi
    fi
  fi

  return 0
}

#-------------------------------------------------------------------------------

function chroot_destroy
# Unmount the chroot, copy any wanted files, and then destroy it
# Return status: always 0
{
  [ -z "$CHROOTDIR" ] && return 0
  log_normal -a "Unmounting chroot ... "
  ${SUDO}umount "$CHROOTDIR"/dev/shm || return 0
  ${SUDO}umount "$CHROOTDIR"/proc || return 0
  ${SUDO}umount -l "$CHROOTDIR" || return 0
  if [ "$OPT_KEEP_TMP" = 'y' ] && [ -d "$MYTMPDIR"/changes/"$SR_TMP" ]; then
    rsync -rlptgo "$MYTMPDIR"/changes/"$SR_TMP"/ "$SR_TMP"/
  fi
  log_done
  ${SUDO}rm -rf "${MYTMPDIR:?NotSetMYTMPDIR}"/changes/{"$SR_TMP","${MYTMPDIR:?NotSetMYTMPDIR}"}
  ${SUDO}rm -rf "${MYTMPDIR:?NotSetMYTMPDIR}"/changes
  unset CHROOTCMD CHROOTDIR
  return 0
}
