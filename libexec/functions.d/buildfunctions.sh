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
# The built package goes into $TMP_OUTPUT, but function build_ok then stores it elsewhere
# Return status:
# 0 = total success, world peace and happiness
# 1 = build failed
# 2 = download failed
# 3 = checksum failed
# 4 = [not used]
# 5 = skipped (skip hint, or download=no, or unsupported on this arch)
# 6 = SlackBuild returned 0 status, but nothing in $TMP_OUTPUT
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

  MY_SLACKBUILD="$MYTMP/slackbuild_$itemprgnam"
  # initial wipe of $MY_SLACKBUILD, even if $OPT_KEEP_TMP is set
  rm -rf "$MY_SLACKBUILD"
  cp -a "$SR_SBREPO/$itemdir" "$MY_SLACKBUILD"

  if [ "$OPT_LINT" = 'y' ]; then
    test_slackbuild "$itemid"
    [ $? -gt 1 ] && return 7
  fi

  # Apply version hint
  NEWVERSION="${HINT_VERSION[$itemid]}"
  if [ -n "$NEWVERSION" -a "${INFOVERSION[$itemid]}" != "$NEWVERSION" ]; then
    # Fiddle with $VERSION -- usually doomed to failure, but not always ;-)
    log_info -a "Setting VERSION=$NEWVERSION (was ${INFOVERSION[$itemid]})"
    sed -i -e "s/^VERSION=.*/VERSION=$NEWVERSION/" "$MY_SLACKBUILD/$itemfile"
    # Let's assume shell globbing chars won't appear in any sane VERSION ;-)
    INFODOWNLIST[$itemid]="${INFODOWNLIST[$itemid]//${INFOVERSION[$itemid]}/$NEWVERSION}"
    INFOVERSION[$itemid]="$NEWVERSION"
  fi

  # Save the existing source to a temporary stash.
  allsourcedir="$SR_SRCREPO"/"$itemdir"
  archsourcedir="$allsourcedir"/"$SR_ARCH"
  TMP_SRCSTASH="$MYTMP"/prev_source
  archsourcestash="${TMP_SRCSTASH}_${SR_ARCH}"
  SOURCESTASH=""
  if [ -d "$archsourcedir" ]; then
    SOURCESTASH="$archsourcestash"
    mkdir -p "$SOURCESTASH"
    find "$SOURCESTASH" -type f -maxdepth 1 -exec rm -f {} \;
    find "$archsourcedir" -type f -maxdepth 1 -exec cp {} "$SOURCESTASH" \;
  elif [ -d "$allsourcedir" ]; then
    SOURCESTASH="$TMP_SRCSTASH"
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
      cp -a "${SRCDIR[$itemid]}"/* "$MY_SLACKBUILD/"
    else
      # "Copy / is dandy / but linky / is quicky" [after Ogden Nash]
      ln -sf -t "$MY_SLACKBUILD/" "${SRCDIR[$itemid]}"/*
    fi
  fi

  # Work out BUILD
  # Get the value from the SlackBuild
  unset BUILD
  buildassign=$(grep -a '^BUILD=' "$MY_SLACKBUILD"/"$itemfile")
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

  # Setup TMP_OUTPUT
  TMP_OUTPUT="$MYTMP/output_$itemprgnam"
  # initial wipe of $TMP_OUTPUT, even if $OPT_KEEP_TMP is set
  rm -rf "$TMP_OUTPUT"
  mkdir -p "$TMP_OUTPUT"

  # Setup TMP_BUILD
  if [ "$OPT_KEEP_TMP" = 'y' ]; then
    TMP_BUILD="$SR_TMP"
  else
    TMP_BUILD="$MYTMP"/tmp
  fi
  mkdir -p "$TMP_BUILD"

  export \
    ARCH="$SR_ARCH" \
    BUILD="$SR_BUILD" \
    TAG="$SR_TAG" \
    TMP="$TMP_BUILD" \
    OUTPUT="$TMP_OUTPUT" \
    PKGTYPE="$SR_PKGTYPE" \
    NUMJOBS="$SR_NUMJOBS"

  SLACKBUILDOPTS="env"
  SLACKBUILDRUN="bash ./$itemfile"

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
  hintneednet='n'
  hintneedX='n'
  restorevars=''
  removestubs=''
  for pragma in ${HINT_PRAGMA[$itemid]}; do
    case "$pragma" in
    'multilib_ldflags' )
      if [ "$SYS_MULTILIB" = 'y' ]; then
        # This includes the rare case when an i486 cross-compile on x86_64 needs -L/usr/lib
        log_info -a "Pragma: multilib_ldflags"
        libdirsuffix=''
        [ "$SR_ARCH" = 'x86_64' ] && libdirsuffix='64'
        sed -i -e "s;^\./configure ;LDFLAGS=\"-L/usr/lib$libdirsuffix\" &;" "$MY_SLACKBUILD/$itemfile"
      fi
      ;;
    'stubs-32' )
      if [ "$SYS_ARCH" = 'x86_64' ] && [ ! -e /usr/include/gnu/stubs-32.h ]; then
        log_info -a "Pragma: stubs-32"
        cp -a /usr/share/slackrepo/stubs-32.h /usr/include/gnu/
        removestubs='y'
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
          ( cd "$MY_SLACKBUILD"; [ -n "$target" ] && [ ! -e "$target" ] && ln -s "$source" "$target" )
          count=$(( count + 1 ))
        fi
      done < <(ls -rt "$SR_SRCREPO"/"$itemdir" 2>/dev/null)
      ;;
    'no_make_test' )
      log_info -a "Pragma: no_make_test"
      sed -i -e "s/make test/: # make test/" "$MY_SLACKBUILD"/"$itemfile"
      ;;
    'x86arch'* )
      fixarch="${pragma/x86arch=/}"
      log_info -a "Pragma: ${pragma}"
      sed -i -e "s/^PRGNAM=.*/&; ARCH='$fixarch'/" "$MY_SLACKBUILD"/"$itemfile"
      unset ARCH
      ;;
    'noexport_ARCH' )
      log_info -a "Pragma: noexport_ARCH"
      sed -i -e "s/^PRGNAM=.*/&; ARCH='$SR_ARCH'/" "$MY_SLACKBUILD"/"$itemfile"
      unset ARCH
      ;;
    'noexport_BUILD' | 'noexport_TAG' )
      log_info -a "Pragma: ${pragma}"
      var="${pragma/noexport_/}"
      sed -i -e "s/^${var}=.*/${var}='${!var}'/" "$MY_SLACKBUILD"/"$itemfile"
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
      sed -i -e "s/^tar .*/& --absolute-names/" "$MY_SLACKBUILD"/"$itemfile"
      ;;
    'need_net' )
      log_info -a "Pragma: need_net"
      hintneednet='y'
      ;;
    'need_X' )
      log_info -a "Pragma: need_X"
      hintneedX='y'
      ;;
    * )
      log_warning -a "${itemid}: Hint PRAGMA=\"$pragma\" not recognised"
      ;;
    esac
  done

  # blocking the net and X will only take effect in a chroot (see chroot_setup)
  BLOCKNET='n'
  [ "$OPT_LINT" = 'y' ] && [ "$hintneednet" != 'y' ] && BLOCKNET='y'
  BLOCKX='n'
  [ "$OPT_LINT" = 'y' ] && [ "$hintneedX" != 'y' ] && BLOCKX='y'

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
  chroot_setup || return 1

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

  # Start the resource monitor
  resourcemon "$ITEMLOGDIR"/resource.log &

  # Remember the build start time and estimate the build finish time
  estbuildsecs=''
  read prevsecs prevmhz guessflag < <(db_get_buildsecs "$itemid")
  if [ -n "$prevsecs" ] && [ -n "$prevmhz" ] && [ -n "$SYS_MHz" ]; then
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
  MY_STARTSTAMP="$MYTMP"/startstamp
  touch "$MY_STARTSTAMP"
  log_normal -a "Running $itemfile ..." "$eta"
  log_info -a "$SLACKBUILDCMD"
  if [ "$OPT_VERBOSE" = 'y' ]; then
    log_verbose '\n---->8-------->8-------->8-------->8-------->8-------->8-------->8-------->8----\n' >&41
    set -o pipefail
    if [ "$SYS_MULTILIB" = "y" ] && [ "$ARCH" = 'i486' -o "$ARCH" = 'i686' ]; then
      ${CHROOTCMD}sh -c ". /etc/profile.d/32dev.sh; cd \"${MY_SLACKBUILD}\"; ${SLACKBUILDCMD}" 2>&1 | \
        tee >(sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b[()].//' -e 's/\x0e//g' -e 's/\x0f//g' >>"$ITEMLOG") >&41
      buildstat=$?
    else
      ${CHROOTCMD}sh -c "cd \"${MY_SLACKBUILD}\"; ${SLACKBUILDCMD}" 2>&1 | \
        tee >(sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b[()].//' -e 's/\x0e//g' -e 's/\x0f//g' >>"$ITEMLOG") >&41
      buildstat=$?
    fi
    set +o pipefail
    log_verbose '\n----8<--------8<--------8<--------8<--------8<--------8<--------8<--------8<----\n' >&41
  else
    if [ "$SYS_MULTILIB" = "y" ] && [ "$ARCH" = 'i486' -o "$ARCH" = 'i686' ]; then
      ${CHROOTCMD}sh -c ". /etc/profile.d/32dev.sh; cd \"${MY_SLACKBUILD}\"; ${SLACKBUILDCMD}" \
        &> >(sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b[()].//' -e 's/\x0e//g' -e 's/\x0f//g' >>"$ITEMLOG")
      buildstat=$?
    else
      ${CHROOTCMD}sh -c "cd \"${MY_SLACKBUILD}\"; ${SLACKBUILDCMD}" \
        &> >(sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b[()].//' -e 's/\x0e//g' -e 's/\x0f//g' >>"$ITEMLOG")
      buildstat=$?
    fi
  fi

  buildfinishtime="$(date '+%s')"
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS
  [ -n "$restorevars" ] && eval "$restorevars"
  [ -n "$removestubs" ] && rm /usr/include/gnu/stubs-32.h

  # Stop the resource monitor
  kill %resourcemon

  # If there's a config.log in the obvious place, save it
  configlog="${TMP_BUILD}/${itemprgnam}-${INFOVERSION[$itemid]}/config.log"
  if [ -f "$configlog" ]; then
    cp "$configlog" "$ITEMLOGDIR"
  fi

  if [ "$buildstat" != 0 ]; then
    log_error -a "${itemid}: $itemfile failed (status $buildstat)" "$(date +%T)"
    build_failed "$itemid"
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=( "${TMP_CHRDIR}${TMP_OUTPUT}"/*.t?z )
  if [ "${pkglist[0]}" = "${TMP_CHRDIR}${TMP_OUTPUT}"/'*.t?z' ]; then
    # no packages: let's get sneaky and snarf it/them from where makepkg said it/them was/were going ;-)
    logpkgs=( $(grep "Slackware package .* created." "$ITEMLOG" | cut -f3 -d" ") )
    if [ "${#logpkgs[@]}" = 0 ]; then
      log_error -a "${itemid}: No packages were created"
      build_failed "$itemid"
      return 6
    else
      for pkgpath in "${logpkgs[@]}"; do
        if [ -f "$MY_SLACKBUILD/README" -a -f "$MY_SLACKBUILD"/"$(basename "$itemfile" .SlackBuild)".info ]; then
          # it's probably an SBo SlackBuild, so complain and don't retag
          if [ -f "${TMP_CHRDIR}$pkgpath" ]; then
            log_warning -a "${itemid}: Package should have been in \$OUTPUT: $pkgpath"
            mv "${TMP_CHRDIR}$pkgpath" "$TMP_OUTPUT"
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
            mv "${TMP_CHRDIR}$pkgpath" "$TMP_OUTPUT"/"${pkgnam/$currtag.$pkgtype/${SR_TAG}.$pkgtype}"
          else
            mv "${TMP_CHRDIR}$pkgpath" "$TMP_OUTPUT"/
          fi
        fi
      done
      pkglist=( "$TMP_OUTPUT"/*.t?z )
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
  rm -f "$MY_STARTSTAMP" 2>/dev/null

  if [ "${HINT_INSTALL[$itemid]}" = 'y' ] || [ "$OPT_INSTALL" = 'y' -a "${HINT_INSTALL[$itemid]}" != 'n' ]; then
    install_packages "${pkglist[@]}" || { build_failed "$itemid"; return 8; }
    #### set the new pkgbase in KEEPINSTALLED[$pkgnam] ????
  else
    uninstall_deps "$itemid"
  fi

  [ "$OPT_KEEP_TMP" != 'y' ] && ${SUDO}rm -rf "${TMP_BUILD:?NotSetTMP_BUILD}"

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

  [ "$OPT_KEEP_TMP" != 'y' ] && rm -rf "$MY_SLACKBUILD"

  # ---- Store the packages ----
  if [ "$OPT_DRY_RUN" = 'y' ]; then
    # put the packages into the special dryrun repo
    mkdir -p "$TMP_DRYREPO"/"$itemdir"
    rm -rf "${TMP_DRYREPO:?NotSetTMP_DRYREPO}"/"$itemdir"/*
    mv "$TMP_OUTPUT"/* "$TMP_DRYREPO"/"$itemdir"/
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
    mv "$TMP_OUTPUT"/* "$SR_PKGREPO"/"$itemdir"/
  fi
  rmdir "$TMP_OUTPUT"

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

  if [ -n "${TMP_CHRDIR}" ]; then
    chroot_destroy
  elif [ "${HINT_INSTALL[$itemid]}" = 'n' ] || [ "$OPT_INSTALL" != 'y' -a "${HINT_INSTALL[$itemid]}" != 'y' ]; then
    uninstall_deps "$itemid"
    #### reinstate packages that we uninstalled prior to building
  fi

  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    ${SUDO}rm -rf "$MY_SLACKBUILD" "$TMP_OUTPUT"
    [ -n "${TMP_BUILD}" ] && ${SUDO}rm -rf "${TMP_BUILD}"
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

  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    ${SUDO}rm -rf "$MY_SLACKBUILD" "$TMP_OUTPUT"
    [ -n "${TMP_BUILD}" ] && ${SUDO}rm -rf "${TMP_BUILD}"
  fi

  log_itemfinish "$itemid" "${STATUS[$itemid]}" "$2" "$3"

  return 0
}

#-------------------------------------------------------------------------------

function chroot_setup
# Setup a temporary chroot environment at $MYTMP/chroot using overlayfs
# Also sets the global variables $CHROOTCMD and $TMP_CHRDIR
# Return status:
# 0 = it worked
# 1 = OPT_CHROOT is not set, or could not mount the overlay
{
  CHROOTCMD=''
  [ "$OPT_CHROOT" != 'y' ] && return 1

  TMP_CHRDIR="$MYTMP"/chrootdir/  # note the trailing slash
  ${SUDO}mkdir -p "$TMP_CHRDIR"
  CHROOTCMD="chroot ${TMP_CHRDIR} "  # note the trailing space
  [ -n "$SUDO" ] && CHROOTCMD="${SUDO} chroot --userspec=${USER} ${TMP_CHRDIR} "

  # Track chroot-related mounts in a nice array so they can be unmounted
  CHRMOUNTS=()

  # Create another tmpfs for the overlay so we can instantly empty it by unmounting
  # (note, upperdir and workdir need to be on the same fs)
  TMP_OVLDIR="$MYTMP"/ovldir
  ${SUDO}mkdir -p "$TMP_OVLDIR"
  ${SUDO}mount -t tmpfs -o defaults,mode=1777 tmpfs "$TMP_OVLDIR"  || \
    { log_error "Failed to mount $TMP_OVLDIR"; exit_cleanup 5; }
  CHRMOUNTS+=( "$TMP_OVLDIR" )
  OVL_DIRTY="$TMP_OVLDIR"/dirty
  OVL_WORK="$TMP_OVLDIR"/work
  ${SUDO}mkdir -p "$OVL_DIRTY" "$OVL_WORK"

  # Setup the chroot environment with all the trimmings
  ${SUDO}mount -t overlay overlay -olowerdir=/,upperdir="$OVL_DIRTY",workdir="$OVL_WORK" "$TMP_CHRDIR" || \
    { log_error "Failed to mount $TMP_CHRDIR"; exit_cleanup 5; }
  CHRMOUNTS+=( "$TMP_CHRDIR" )
  ${SUDO}mount --bind /dev "$TMP_CHRDIR"/dev
  CHRMOUNTS+=( "$TMP_CHRDIR"/dev )
  ${SUDO}mount --bind /dev/pts "$TMP_CHRDIR"/dev/pts
  CHRMOUNTS+=( "$TMP_CHRDIR"/dev/pts )
  ${SUDO}mount --bind /dev/shm "$TMP_CHRDIR"/dev/shm
  CHRMOUNTS+=( "$TMP_CHRDIR"/dev/shm )
  ${SUDO}mount -t proc  proc  "$TMP_CHRDIR"/proc
  CHRMOUNTS+=( "$TMP_CHRDIR"/proc )
  ${SUDO}mount -t sysfs sysfs "$TMP_CHRDIR"/sys
  CHRMOUNTS+=( "$TMP_CHRDIR"/sys )
  if [ "$BLOCKNET" = 'y' ]; then
    ${SUDO}rm -f "$TMP_CHRDIR"/etc/resolv.conf
    ${SUDO}touch "$TMP_CHRDIR"/etc/resolv.conf
  else
    ${SUDO}touch "$TMP_CHRDIR"/etc/resolv.conf
    ${SUDO}mount --bind /etc/resolv.conf "$TMP_CHRDIR"/etc/resolv.conf
    CHRMOUNTS+=( "$TMP_CHRDIR"/etc/resolv.conf )
  fi
  if [ -n "$SUDO" ]; then
    if [ ! -d "$TMP_CHRDIR"/"$HOME" ]; then
      # create $HOME as a (mostly) empty directory
      ${SUDO}mkdir -p "$TMP_CHRDIR"/"$HOME"
      ${SUDO}chown -R "$EUID" "$TMP_CHRDIR"/"$HOME"
      for subdir in .ccache .distcc ; do
        if [ -d "$HOME"/"$subdir" ]; then
          ${SUDO}mkdir -p "$TMP_CHRDIR"/"$HOME"/"$subdir"
          ${SUDO}mount --bind "$HOME"/"$subdir" "$TMP_CHRDIR"/"$HOME"/"$subdir"
          CHRMOUNTS+=( "$TMP_CHRDIR/$HOME"/"$subdir" )
        fi
      done
    fi
    if [ "$BLOCKX" = 'y' ]; then
      export -n DISPLAY
    else
      if [ -f "$HOME"/.Xauthority ]; then
        #### would a dummy X server be a lot of bother?
        ${SUDO}touch "$TMP_CHRDIR"/"$HOME"/.Xauthority
        ${SUDO}mount --bind "$HOME"/.Xauthority "$TMP_CHRDIR"/"$HOME"/.Xauthority
        CHRMOUNTS+=( "$TMP_CHRDIR/$HOME"/.Xauthority )
      fi
    fi
  fi

  # Import build stuff from $MYTMP
  ${SUDO}mkdir -p "$TMP_CHRDIR"/"$MY_SLACKBUILD"
  ${SUDO}mount --bind "$MY_SLACKBUILD" "$TMP_CHRDIR"/"$MY_SLACKBUILD"
  CHRMOUNTS+=( "$TMP_CHRDIR"/"$MY_SLACKBUILD" )
  ${SUDO}mkdir -p "$TMP_CHRDIR"/"$TMP_OUTPUT"
  ${SUDO}mount --bind "$TMP_OUTPUT" "$TMP_CHRDIR"/"$TMP_OUTPUT"
  CHRMOUNTS+=( "$TMP_CHRDIR"/"$TMP_OUTPUT" )
  ${SUDO}mkdir -p "$TMP_CHRDIR"/"$TMP_BUILD"
  ${SUDO}mount --bind "$TMP_BUILD" "$TMP_CHRDIR"/"$TMP_BUILD"
  CHRMOUNTS+=( "$TMP_CHRDIR"/"$TMP_BUILD" )

  return 0
}

#-------------------------------------------------------------------------------

function chroot_report
# Warn about modified files and directories in the chroot
# Return status: always 0
{
  [ -z "$TMP_CHRDIR" ] && return 0

  if [ -f "$MY_STARTSTAMP" ]; then
    crap=$(cd "$OVL_DIRTY"; find . -path './tmp' -prune -o  -path ".$HOME/.*/*" -prune -o -newer ../startstamp -print 2>/dev/null)
    if [ -n "$crap" ]; then
      excludes="^/dev/ttyp|^$HOME/\\.distcc|^$HOME/\\.cache|^$HOME\$|^/var/tmp|\\.pyc\$|^/etc/ld.so.cache\$|^/var/cache/ldconfig\$"
      significant="$(echo "$crap" | sed -e "s#^\./#/#" | grep -v -E "$excludes" | sort)"
      if [ -n "$significant" ]; then
        log_warning -a "$itemid: Files/directories were modified in the chroot"
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
  [ -z "$TMP_CHRDIR" ] && return 0
  log_normal -a "Unmounting chroot ... "

  # unmount the chroot mounts, in reverse order
  for rev in $(seq $(( ${#CHRMOUNTS[@]} - 1)) -1 0); do
    ${SUDO}umount "${CHRMOUNTS[$rev]}" 2>/dev/null || true
  done
  CHRMOUNTS=()
  unset CHROOTCMD TMP_CHRDIR

  log_done
  return 0
}
