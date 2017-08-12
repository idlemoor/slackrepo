#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for slackrepo
#   build_item_packages
#   build_ok
#   build_failed
#   build_skipped
#   build_cleanup
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

  TMP_SLACKBUILD="$BIGTMP/slackbuild_$itemprgnam"
  # initial wipe of $TMP_SLACKBUILD, even if $OPT_KEEP_TMP is set
  rm -rf "$TMP_SLACKBUILD"
  cp -a "$SR_SBREPO/$itemdir" "$TMP_SLACKBUILD"

  test_slackbuild "$itemid"
  [ $? -gt 1 ] && return 7

  # Apply version hint
  NEWVERSION="${HINT_VERSION[$itemid]}"
  if [ -n "$NEWVERSION" ] && [ "${INFOVERSION[$itemid]}" != "$NEWVERSION" ]; then
    # Fiddle with $VERSION -- usually doomed to failure, but not always ;-)
    log_info -a "Setting VERSION=$NEWVERSION (was ${INFOVERSION[$itemid]})"
    sed -i -e "s/^VERSION=.*/VERSION=$NEWVERSION/" "$TMP_SLACKBUILD/$itemfile"
    # Let's assume shell globbing chars won't appear in any sane VERSION ;-)
    INFODOWNLIST[$itemid]="${INFODOWNLIST[$itemid]//${INFOVERSION[$itemid]}/$NEWVERSION}"
    INFOVERSION[$itemid]="$NEWVERSION"
  fi

  # Save the existing source to a temporary stash.
  allsourcedir="$SR_SRCREPO"/"$itemdir"
  archsourcedir="$allsourcedir"/"$SR_ARCH"
  TMP_SRCSTASH="$BIGTMP"/prev_source
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
       [ -z "${HINT_NODOWNLOAD[$itemid]}" ] && test_download "$itemid"
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
      cp -a "${SRCDIR[$itemid]}"/* "$TMP_SLACKBUILD/"
    else
      # "Copy / is dandy / but linky / is quicky" [after Ogden Nash]
      ln -sf -t "$TMP_SLACKBUILD/" "${SRCDIR[$itemid]}"/*
    fi
  fi

  # Work out BUILD
  # Get the value from the SlackBuild
  unset BUILD
  buildassign=$(grep -a '^BUILD=' "$TMP_SLACKBUILD"/"$itemfile")
  if [ -z "$buildassign" ]; then
    buildassign="BUILD=1"
    log_warning -a "${itemid}: no \"BUILD=\" in $itemfile; using 1"
  fi
  eval $buildassign
  if [ "${STATUSINFO[$itemid]:0:3}" = 'add' ] || [ "${STATUSINFO[$itemid]:0:18}" = 'update for version' ]; then
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
  TMP_OUTPUT="$BIGTMP/output_$itemprgnam"
  # initial wipe of $TMP_OUTPUT, even if $OPT_KEEP_TMP is set
  rm -rf "$TMP_OUTPUT"
  mkdir -p "$TMP_OUTPUT"

  # Setup TMP_BUILD
  if [ "$OPT_KEEP_TMP" = 'y' ]; then
    TMP_BUILD="$SR_TMP"
  else
    TMP_BUILD="$BIGTMP/build_$itemprgnam"
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

  # Reproducible building (* experimental *)
  # Don't do it if this isn't a git repo or if git is dirty.
  canreprod='n'
  if [ "${OPT_REPROD:-n}" != 'n' ]; then
    if [ "$GOTGIT" = 'y' ] && [ "${GITDIRTY[$itemid]}" != 'y' ]; then
      canreprod='y'
      # Use the newest revision time of the package and its first-level deps.
      latest="$(git log -n 1 --pretty=format:%ct "${GITREV[$itemid]}")"
      for parentid in ${DIRECTDEPS[$itemid]}; do
        if [ "${GITDIRTY[$parentid]}" != 'y' ]; then
          parentstamp="$(git log -n 1 --pretty=format:%ct "${GITREV[$parentid]}")"
          [ "$parentstamp" -gt "$latest" ] && latest="$parentstamp"
        else
          canreprod='n'
          break
        fi
      done
    fi
  fi
  if [ "$canreprod" = 'y' ]; then
    export SOURCE_DATE_EPOCH="$latest"
    # Use our modified makepkg
    sed -i -e "s#/sbin/makepkg #makepkg #" "$TMP_SLACKBUILD/$itemfile"
  else
    unset SOURCE_DATE_EPOCH
  fi

  SLACKBUILDOPTS="env"
  SLACKBUILDRUN="bash ./$itemfile"
  [ "$OPT_VERY_VERBOSE" = 'y' ] && SLACKBUILDRUN="bash -x ./$itemfile"

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
        sed -i -e "s;^\./configure ;LDFLAGS=\"-L/usr/lib$libdirsuffix\" &;" "$TMP_SLACKBUILD/$itemfile"
      fi
      ;;
    'python3' )
      # If python3 support isn't included, add it
      if ! grep -q python3 "$TMP_SLACKBUILD/$itemfile" ; then
        log_info -a "Pragma: python3"
        SEARCH="python setup.py install --root[= ]\\\$PKG"
        ADD="if python3 -c 'import sys' 2>/dev/null; then\n  rm -rf build\n  python3 setup.py install --root=\\\$PKG\nfi"
        sed -i -e "/$SEARCH/a$ADD" "$TMP_SLACKBUILD/$itemfile"
      fi
      # Add 'PYTHON3=yes' to options, for the 'other' kind of python3 SlackBuild
      SLACKBUILDOPTS="$SLACKBUILDOPTS PYTHON3=yes"
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
      while read -r sourcefile; do
        source="${sourcefile##*/}"
        # skip subdirectories (and don't increment count)
        if [ -f "$SR_SRCREPO"/"$itemdir"/"$sourcefile" ]; then
          target="${tempdownlist[$count]##*/}"
          ( cd "$TMP_SLACKBUILD"; [ -n "$target" ] && [ ! -e "$target" ] && ln -s "$source" "$target" )
          count=$(( count + 1 ))
        fi
      done < <(ls -rt "$SR_SRCREPO"/"$itemdir" 2>/dev/null)
      ;;
    'no_make_test' )
      log_info -a "Pragma: no_make_test"
      sed -i -e "s/make test/: # make test/" "$TMP_SLACKBUILD"/"$itemfile"
      ;;
    'x86arch'* )
      if [ "$SR_ARCH" = 'i486' ] || [ "$SR_ARCH" = 'i586' ] || [ "$SR_ARCH" = 'i686' ]; then
        log_info -a "Pragma: ${pragma}"
        fixarch="${pragma/x86arch=/}"
        sed -i -e "s/^PRGNAM=.*/&; ARCH='$fixarch'/" "$TMP_SLACKBUILD"/"$itemfile"
        unset ARCH
      fi
      ;;
    'noexport_ARCH' )
      log_info -a "Pragma: noexport_ARCH"
      sed -i -e "s/^PRGNAM=.*/&; ARCH='$SR_ARCH'/" "$TMP_SLACKBUILD"/"$itemfile"
      unset ARCH
      ;;
    'noexport_BUILD' | 'noexport_TAG' )
      log_info -a "Pragma: ${pragma}"
      var="${pragma/noexport_/}"
      sed -i -e "s/^${var}=.*/${var}='${!var}'/" "$TMP_SLACKBUILD"/"$itemfile"
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
      sed -i -e "s/^tar .*/& --absolute-names/" "$TMP_SLACKBUILD"/"$itemfile"
      ;;
    'need_net' )
      log_info -a "Pragma: need_net"
      hintneednet='y'
      ;;
    'need_X' )
      log_info -a "Pragma: need_X"
      hintneedX='y'
      ;;
    'kernel'* | curl | wget )
      ;;
    * )
      log_warning -a "${itemid}: Hint PRAGMA=\"$pragma\" not recognised"
      ;;
    esac
  done

  # Block X by unexporting DISPLAY
  if [ "$OPT_LINT_X" = 'y' ] && [ "$hintneedX" != 'y' ]; then
    export -n DISPLAY
  else
    export DISPLAY
  fi
  # Blocking the net will only take effect in a chroot (see chroot_setup)
  BLOCKNET='n'
  [ "$OPT_LINT_NET" = 'y' ] && [ "$hintneednet" != 'y' ] && BLOCKNET='y'

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
  [ "$OPT_VERBOSE" = 'y' ] && [ "$DOCOLOUR" = 'y' ] && SLACKBUILDRUN="${LIBEXECDIR}/unbuffer $SLACKBUILDRUN"

  # Assemble the command line
  SLACKBUILDCMD="${SLACKBUILDOPTS} ${SLACKBUILDRUN}"

  # Multilib fixup
  if [ "$SYS_MULTILIB" = "y" ]; then
    if [ "$ARCH" = 'i486' ] || [ "$ARCH" = 'i586' ] || [ "$ARCH" = 'i686' ]; then
      SLACKBUILDCMD=". /etc/profile.d/32dev.sh; ${SLACKBUILDCMD}"
    fi
  fi

  # Setup the chroot
  # (to be destroyed below, or by build_failed if necessary)
  if [ "$OPT_CHROOT" = 'y' ]; then
    chroot_setup || return 1
  fi

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
  read -r prevsecs prevmhz guessflag < <(db_get_buildsecs "$itemid")
  if [ -n "$prevsecs" ] && [ -n "$prevmhz" ] && [ -n "$SYS_MHz" ]; then
    estbuildsecs=$(echo "scale=3; ${prevsecs}*${prevmhz}/${SYS_MHz}+1" | bc | sed 's/\..*//')
  fi
  BUILDSTARTTIME="$(date '+%s')"
  eta=""
  if [ -n "$estbuildsecs" ]; then
    eta="ETA $(date --date=@"$(( BUILDSTARTTIME + estbuildsecs + 30 ))" '+%H:%M'):??"
    [ "$guessflag" = '~' ] && [ "$estbuildsecs" -gt "1200" ] && eta="${eta:0:8}?:??"
    [ "$guessflag" = '~' ] && eta="eta ~${eta:4:8}"
  fi

  # Start the resource monitor
  resource_monitor "$ITEMLOGDIR"/resource.log &
  resmonpid=$!

  # Build it
  MY_STARTSTAMP="$MYTMP"/startstamp
  touch "$MY_STARTSTAMP"
  log_normal -a "Running $itemfile ..." "$eta"
  log_info -a "$SLACKBUILDCMD"
  if [ "$OPT_VERBOSE" = 'y' ]; then
    log_verbose '\n---->8-------->8-------->8-------->8-------->8-------->8-------->8-------->8----\n' >&41
    set -o pipefail
    ${CHROOTCMD}sh -c "cd \"${TMP_SLACKBUILD}\"; ${SLACKBUILDCMD}" 2>&1 | \
      tee >(sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b[()].//' -e 's/\x0e//g' -e 's/\x0f//g' >>"$ITEMLOG") >&41
    buildstat=$?
    set +o pipefail
    log_verbose '\n----8<--------8<--------8<--------8<--------8<--------8<--------8<--------8<----\n' >&41
  else
    ${CHROOTCMD}sh -c "cd \"${TMP_SLACKBUILD}\"; ${SLACKBUILDCMD}" \
      &> >(sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b[()].//' -e 's/\x0e//g' -e 's/\x0f//g' >>"$ITEMLOG")
    buildstat=$?
  fi

  BUILDFINISHTIME="$(date '+%s')"
  # add 1 to round it up so it's never zero
  BUILDELAPSED=$(( BUILDFINISHTIME - BUILDSTARTTIME + 1 ))
  kill -9 "$resmonpid" 2>/dev/null
  wait "$resmonpid" 2>/dev/null
  resmonpid=''
  # report the resource usage even if the build failed (it may be relevant)
  resource_report "$ITEMLOGDIR"/resource.log

  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS
  [ -n "$restorevars" ] && eval "$restorevars"
  [ -n "$removestubs" ] && rm /usr/include/gnu/stubs-32.h

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
  pkglist=( "${MY_CHRDIR}${TMP_OUTPUT}"/*.t?z )
  if [ "${pkglist[0]}" = "${MY_CHRDIR}${TMP_OUTPUT}"/'*.t?z' ]; then
    # no packages: let's get sneaky and snarf it/them from where makepkg said it/them was/were going ;-)
    logpkgs=( $(grep "Slackware package .* created." "$ITEMLOG" | cut -f3 -d" ") )
    if [ "${#logpkgs[@]}" = 0 ]; then
      log_error -a "${itemid}: No packages were created"
      build_failed "$itemid"
      return 6
    else
      for pkgpath in "${logpkgs[@]}"; do
        if [ -f "$TMP_SLACKBUILD/README" ] && [ -f "$TMP_SLACKBUILD"/"$(basename "$itemfile" .SlackBuild)".info ]; then
          # it's probably an SBo SlackBuild, so complain and don't retag
          if [ -f "${MY_CHRDIR}$pkgpath" ]; then
            log_warning -a "${itemid}: Package should have been in \$OUTPUT: $pkgpath"
            mv "${MY_CHRDIR}$pkgpath" "$TMP_OUTPUT"
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
            mv "${MY_CHRDIR}$pkgpath" "$TMP_OUTPUT"/"${pkgnam/$currtag.$pkgtype/${SR_TAG}.$pkgtype}"
          else
            mv "${MY_CHRDIR}$pkgpath" "$TMP_OUTPUT"/
          fi
        fi
      done
      pkglist=( "$TMP_OUTPUT"/*.t?z )
    fi
  fi

  # update build time information
  db_set_buildsecs "$itemid" "$BUILDELAPSED"

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

  test_package "$itemid" "${pkglist[@]}"
  [ $? -gt 1 ] && { build_failed "$itemid"; return 7; }

  [ "$OPT_CHROOT" = 'y' ] && chroot_destroy
  rm -f "$MY_STARTSTAMP" 2>/dev/null

  if [ "${HINT_INSTALL[$itemid]}" = 'y' ] || [ "$OPT_INSTALL" = 'y' -a "${HINT_INSTALL[$itemid]}" != 'n' ]; then
    install_packages "${pkglist[@]}" || { build_failed "$itemid"; return 8; }
    #### set the new pkgbase in KEEPINSTALLED[$pkgnam] ????
  else
    uninstall_deps "$itemid"
  fi

  build_ok "$itemid"  # \o/
  return 0
}

#-------------------------------------------------------------------------------

function build_ok
# Store packages, write metadata, call cleanup and log for a build that has succeeded
# $1 = itemid
# Return status: always 0
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  # ---- Store the packages ----
  if [ "$OPT_DRY_RUN" = 'y' ]; then
    # put the packages into the special dryrun repo
    mkdir -p "$TMP_DRYREPO"/"$itemdir"
    rm -rf "${TMP_DRYREPO:?NotSetTMP_DRYREPO}"/"$itemdir"/*
    mv "$TMP_OUTPUT"/* "$TMP_DRYREPO"/"$itemdir"/
  else
    # save any existing packages and metadata to the backup repo
    if [ -d "$SR_PKGREPO"/"$itemdir" ] && [ -n "$SR_PKGBACKUP" ]; then
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

  # ---- Write the metadata ----
  write_pkg_metadata "$itemid"  # sets $CHANGEMSG

  # ---- Cleanup ----
  build_cleanup

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
# Log and call cleanup for a build that has failed
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

  if [ -n "${MY_CHRDIR}" ]; then
    chroot_destroy
  elif [ "${HINT_INSTALL[$itemid]}" = 'n' ] || [ "$OPT_INSTALL" != 'y' -a "${HINT_INSTALL[$itemid]}" != 'y' ]; then
    uninstall_deps "$itemid"
    #### reinstate packages that we uninstalled prior to building
  fi

  build_cleanup
  log_itemfinish "$itemid" 'failed'

  return 0
}

#-------------------------------------------------------------------------------

function build_skipped
# Log and call cleanup for a build that has been skipped or is unsupported
# $1 = itemid
# $2 = message (optional -- supplied to log_itemfinish as $3)
# $3 = extra message for next line (optional -- supplied to log_itemfinish as $4)
# Return status: always 0
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"

  build_cleanup
  log_itemfinish "$itemid" "${STATUS[$itemid]}" "$2" "$3"

  return 0
}

#-------------------------------------------------------------------------------

function build_cleanup
# Remove temporary files at the end of a build
# Return status: always 0
{
  ${SUDO}rm -rf \
    "$TMP_SLACKBUILD" \
    "$TMP_OUTPUT" \
    "$TMP_OVLDIR" \
    "$TMP_SRCSTASH" \
    "$MYTMP"/*
  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    ${SUDO}rm -rf "${TMP_BUILD}"
  fi
  return 0
}

#-------------------------------------------------------------------------------

function chroot_setup
# Setup a temporary chroot environment at $MYTMP/chrootdir using overlayfs
# Also sets the global variables $CHROOTCMD and $MY_CHRDIR
# Return status:
# 0 = it worked
# 1 = OPT_CHROOT is not set
# Exits completely (status=6) if the overlay failed to mount
{
  CHROOTCMD=''
  [ "$OPT_CHROOT" != 'y' ] && return 1

  MY_CHRDIR="$MYTMP"/chrootdir/  # note the trailing slash
  ${SUDO}mkdir -p "$MY_CHRDIR"
  CHROOTCMD="chroot ${MY_CHRDIR} "  # note the trailing space
  [ -n "$SUDO" ] && CHROOTCMD="${SUDO} chroot --userspec=${USER} ${MY_CHRDIR} "

  # Track chroot-related mounts in a nice array so they can be unmounted
  CHRMOUNTS=()

  # Setup the overlay
  # (note, upperdir and workdir must be on the same fs and must not be overlayfs)
  TMP_OVLDIR="$BIGTMP"/ovldir
  ${SUDO}mkdir -p "$TMP_OVLDIR"
  OVL_DIRTY="$TMP_OVLDIR"/dirty
  OVL_WORK="$TMP_OVLDIR"/work
  ${SUDO}mkdir -p "$OVL_DIRTY" "$OVL_WORK"
  ${SUDO}mount -t overlay overlay -olowerdir=/,upperdir="$OVL_DIRTY",workdir="$OVL_WORK" "$MY_CHRDIR" || \
    { log_error "Failed to mount $MY_CHRDIR"; exit_cleanup 6; }
  CHRMOUNTS+=( "$MY_CHRDIR" )

  # Setup a chroot environment with all the trimmings
  ${SUDO}mount --bind /dev "$MY_CHRDIR"/dev
  CHRMOUNTS+=( "$MY_CHRDIR"/dev )
  ${SUDO}mount --bind /dev/pts "$MY_CHRDIR"/dev/pts
  CHRMOUNTS+=( "$MY_CHRDIR"/dev/pts )
  ${SUDO}mount --bind /dev/shm "$MY_CHRDIR"/dev/shm
  CHRMOUNTS+=( "$MY_CHRDIR"/dev/shm )
  ${SUDO}mount -t proc  proc  "$MY_CHRDIR"/proc
  CHRMOUNTS+=( "$MY_CHRDIR"/proc )
  ${SUDO}mount -t sysfs sysfs "$MY_CHRDIR"/sys
  CHRMOUNTS+=( "$MY_CHRDIR"/sys )
  if [ "$BLOCKNET" = 'y' ]; then
    ${SUDO}rm -f "$MY_CHRDIR"/etc/resolv.conf
    ${SUDO}touch "$MY_CHRDIR"/etc/resolv.conf
  else
    ${SUDO}touch "$MY_CHRDIR"/etc/resolv.conf
    ${SUDO}mount --bind /etc/resolv.conf "$MY_CHRDIR"/etc/resolv.conf
    CHRMOUNTS+=( "$MY_CHRDIR"/etc/resolv.conf )
  fi
  if [ -n "$SUDO" ]; then
    # setup $HOME as a (mostly) empty directory
    [ -d "$MY_CHRDIR"/"$HOME" ] || ${SUDO}mkdir -p "$MY_CHRDIR"/"$HOME"
    # use yet another "small" tmpfs
    ${SUDO}mount -t tmpfs -o defaults,uid="$EUID",mode=755 tmpfs "$MY_CHRDIR"/"$HOME"
    CHRMOUNTS+=( "$MY_CHRDIR"/"$HOME" )
    # bind in useful subdirs from the real home
    for subdir in .ccache .distcc ; do
      if [ -d "$HOME"/"$subdir" ]; then
        ${SUDO}mkdir -p "$MY_CHRDIR"/"$HOME"/"$subdir"
        ${SUDO}mount --bind "$HOME"/"$subdir" "$MY_CHRDIR"/"$HOME"/"$subdir"
        CHRMOUNTS+=( "$MY_CHRDIR"/"$HOME"/"$subdir" )
      fi
    done
  fi
  if [ "$BLOCKX" != 'y' ] || [ -f "$HOME"/.Xauthority ]; then
    #### would a dummy X server be a lot of bother?
    ${SUDO}touch "$MY_CHRDIR"/"$HOME"/.Xauthority
    ${SUDO}mount --bind "$HOME"/.Xauthority "$MY_CHRDIR"/"$HOME"/.Xauthority
    CHRMOUNTS+=( "$MY_CHRDIR/$HOME"/.Xauthority )
  fi

  # if $SR_TMP is not on the root fs, we need to bind-mount it into the chroot
  if [ "$(findmnt -n -o TARGET -T /tmp)" != / ]; then
    ${SUDO}mkdir -p "$MY_CHRDIR"/"$SR_TMP"
    ${SUDO}mount --bind "$SR_TMP" "$MY_CHRDIR"/"$SR_TMP"
    CHRMOUNTS+=( "$MY_CHRDIR"/"$SR_TMP" )
  fi

  # Import build stuff from $MYTMP
  ${SUDO}mkdir -p "$MY_CHRDIR"/"$TMP_SLACKBUILD"
  ${SUDO}mount --bind "$TMP_SLACKBUILD" "$MY_CHRDIR"/"$TMP_SLACKBUILD"
  CHRMOUNTS+=( "$MY_CHRDIR"/"$TMP_SLACKBUILD" )
  ${SUDO}mkdir -p "$MY_CHRDIR"/"$TMP_OUTPUT"
  ${SUDO}mount --bind "$TMP_OUTPUT" "$MY_CHRDIR"/"$TMP_OUTPUT"
  CHRMOUNTS+=( "$MY_CHRDIR"/"$TMP_OUTPUT" )
  ${SUDO}mkdir -p "$MY_CHRDIR"/"$TMP_BUILD"
  ${SUDO}mount --bind "$TMP_BUILD" "$MY_CHRDIR"/"$TMP_BUILD"
  CHRMOUNTS+=( "$MY_CHRDIR"/"$TMP_BUILD" )

  return 0
}

#-------------------------------------------------------------------------------

function chroot_report
# Warn about modified files and directories in the chroot
# Return status: always 0
{
  [ -z "$MY_CHRDIR" ] && return 0

  if [ -f "$MY_STARTSTAMP" ]; then
    crap=$(cd "$OVL_DIRTY"; find . -path './tmp' -prune -o  -path ".$HOME/.*/*" -prune -o -newer ../startstamp -print 2>/dev/null)
    if [ -n "$crap" ]; then
      excludes="^/dev/ttyp|^$HOME/\\.distcc|^$HOME/\\.cache|^$HOME\$|^/var/tmp|\\.pyc\$|^/etc/ld.so.cache\$|^/var/cache/ldconfig\$"
      significant="$(echo "$crap" | sed -e "s#^\./#/#" | grep -v -E "$excludes" | sort)"
      if [ -n "$significant" ]; then
        log_warning -a -s "$itemid: Files/directories were modified in the chroot" && \
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
  [ -z "$MY_CHRDIR" ] && return 0
  log_normal -a "Unmounting chroot ... "

  # unmount the chroot mounts, in reverse order
  for rev in $(seq $(( ${#CHRMOUNTS[@]} - 1)) -1 0); do
    ${SUDO}umount "${CHRMOUNTS[$rev]}" 2>/dev/null || true
  done
  CHRMOUNTS=()
  unset CHROOTCMD MY_CHRDIR

  log_done
  return 0
}
