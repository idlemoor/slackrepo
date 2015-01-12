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
#-------------------------------------------------------------------------------
# If you're looking for build_with_deps, see depfunctions.sh
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
    # Increment the existing packages' BUILD, or use the SlackBuild's (whichever is greater).
    #### Need to check if there is a backed up greater build
    oldpkgs=( "$SR_PKGREPO"/"$itemdir"/*.t?z )
    if [ "${oldpkgs[0]}" = "$SR_PKGREPO"/"$itemdir"/'*.t?z' ]; then
      # no existing packages
      oldbuild=0
    else
      # If there are multiple packages from one SlackBuild, and they all have
      # different BUILD numbers, frankly we are screwed, so just use the first:
      oldbuild=$(echo "${oldpkgs[0]}" | sed -e 's/^.*-//' -e 's/[^0-9]*$//' )
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
  [ "$DOCOLOUR"  = 'y' -a -x /usr/bin/unbuffer ] && SLACKBUILDCMD="unbuffer $SLACKBUILDCMD"

  # Process other hints for the build:

  # GROUPADD and USERADD ...
  do_groupadd_useradd "$itemid"

  # ... NUMJOBS (with MAKEFLAGS and NUMJOBS env vars) ...
  NUMJOBS=" ${HINT_NUMJOBS[$itemid]:-$SR_NUMJOBS} "
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
  # The term '30' in the following expression is dedicated to the memory of James Doohan.
  [ -n "$prevbuildsecs" ] && eta="ETA $(date --date=@"$(( buildstarttime + prevbuildsecs + 30 ))" '+%H:%M')"
  runmsg=$(format_left_right "Running $itemfile ..." "$eta")
  log_normal -a "$runmsg"
  log_verbose -a "$SLACKBUILDCMD"
  if [ "$OPT_VERY_VERBOSE" = 'y' ]; then
    echo ''
    echo '---->8-------->8-------->8-------->8-------->8-------->8-------->8-------->8---'
    echo ''
    set -o pipefail
    if [ "$SYS_MULTILIB" = "y" -a "$ARCH" = 'i486' ]; then
      ( cd "$MYTMPIN"; . /etc/profile.d/32dev.sh; eval "$SLACKBUILDCMD" ) 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    else
      ( cd "$MYTMPIN"; eval "$SLACKBUILDCMD" ) 2>&1 | tee -a "$ITEMLOG"
      buildstat=$?
    fi
    set +o pipefail
    echo '----8<--------8<--------8<--------8<--------8<--------8<--------8<--------8<---'
    echo ''
  else
    if [ "$SYS_MULTILIB" = "y" -a "$ARCH" = 'i486' ]; then
      ( cd "$MYTMPIN"; . /etc/profile.d/32dev.sh; eval "$SLACKBUILDCMD" ) >> "$ITEMLOG" 2>&1
      buildstat=$?
    else
      ( cd "$MYTMPIN"; eval "$SLACKBUILDCMD" ) >> "$ITEMLOG" 2>&1
      buildstat=$?
    fi
  fi
  buildfinishtime="$(date '+%s')"
  unset ARCH BUILD TAG TMP OUTPUT PKGTYPE NUMJOBS

  # If there's a config.log in the obvious place, save it
  configlog="$SR_TMP"/"$itemprgnam"-"${INFOVERSION[$itemid]}"/config.log
  if [ -f "$configlog" ]; then
    cp "$configlog" "$ITEMLOGDIR"
  fi

  if [ "$buildstat" != 0 ]; then
    log_error -a "${itemid}: $itemfile failed (status $buildstat)"
    build_failed "$itemid"
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=( "$MYTMPOUT"/*.t?z )
  if [ "${pkglist[0]}" = "$MYTMPOUT"/'*.t?z' ]; then
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
          log_warning -a "${itemid}: Package should have been in \$OUTPUT: $pkgpath"
          mv "$pkgpath" "$MYTMPOUT"
        else
          pkgnam=$(basename "$pkgpath")
          currtag=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
          if [ "$currtag" != "$SR_TAG" ]; then
            # retag it
            pkgtype=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
            mv "$pkgpath" "$MYTMPOUT"/"${pkgnam/%$currtag.$pkgtype/${SR_TAG}.$pkgtype}"
          else
            mv "$pkgpath" "$MYTMPOUT"/
          fi
        fi
      done
      pkglist=( "$MYTMPOUT"/*.t?z )
    fi
  fi

  for pkgpath in "${pkglist[@]}"; do
    log_normal "Built ok:  $(basename "$pkgpath")"
  done

  db_set_buildsecs "$itemid" $(( buildfinishtime - buildstarttime ))

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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

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
    # save any existing packages and metadata to the backup repo
    if [ -d "$SR_PKGREPO"/"$itemdir" -a -n "$SR_PKGBACKUP" ]; then
      if [ -d "$SR_PKGBACKUP"/"$itemdir" ]; then
        mv "$SR_PKGBACKUP"/"$itemdir" "$SR_PKGBACKUP"/"$itemdir".prev
      else
        mkdir -p "$(dirname "$SR_PKGBACKUP"/"$itemdir")"
      fi
      mv "$SR_PKGREPO"/"$itemdir" "$SR_PKGBACKUP"/"$itemdir"
      rm -rf "$SR_PKGBACKUP"/"$itemdir".prev
      for backpack in "$SR_PKGBACKUP"/"$itemdir"/*.t?z; do
        [ -e "$backpack" ] || break
        log_normal "Backed up: $(basename "$backpack")"
      done
    fi
    # put the new packages into the real package repo
    mkdir -p "$SR_PKGREPO"/"$itemdir"
    mv "$MYTMPOUT"/* "$SR_PKGREPO"/"$itemdir"/
  fi

  create_pkg_metadata "$itemid"  # sets $CHANGEMSG

  # MYTMPOUT is empty now, so remove it even if OPT_KEEP_TMP is set
  rm -rf "$MYTMPOUT"

  if [ "${HINT_INSTALL[$itemid]}" = 'n' ] || [ "$OPT_INSTALL" != 'y' -a "${HINT_INSTALL[$itemid]}" != 'y' ]; then
    uninstall_deps "$itemid"
  fi

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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  if [ "$OPT_KEEP_TMP" != 'y' ]; then
    rm -rf "$MYTMPIN" "$MYTMPOUT"
    rm -rf "$SR_TMP"/"$itemprgnam"* "$SR_TMP"/package-"$itemprgnam"
  fi

  buildtype="$(echo "$BUILDINFO" | cut -f1 -d" ")"
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
# Create metadata files in package dir, and changelog entries
# $1 = itemid
# Return status:
# 9 = bizarre existential error, otherwise 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local -a pkglist

  MYREPO="$SR_PKGREPO"
  [ "$OPT_DRY_RUN" = 'y' ] && MYREPO="$DRYREPO"

  pkglist=( "$MYREPO"/"$itemdir"/*.t?z )


  #-----------------------------#
  # changelog entry             #
  # (gratuitously elaborate :-) #
  #-----------------------------#

  operation="$(echo "$BUILDINFO" | sed -e 's/^add/Added/' -e 's/^update/Updated/' -e 's/^rebuild.*/Rebuilt/' )"
  extrastuff=''
  case "$BUILDINFO" in
  add*)
      # add short description from slack-desc (if there's no slack-desc, this should be null)
      extrastuff="($(grep "^${pkgnam}: " "$SR_SBREPO"/"$itemdir"/slack-desc 2>/dev/null| head -n 1 | sed -e 's/.*(//' -e 's/).*//'))"
      ;;
  'update for git'*)
      # add title of the latest commit message
      extrastuff="($(cd "$SR_SBREPO"/"$itemdir"; git log --pretty=format:%s -n 1 . | sed -e 's/.*: //' -e 's/\.$//'))"
      ;;
  *)  :
      ;;
  esac
  # build_ok will need this:
  CHANGEMSG="$operation"
  [ -n "$extrastuff" ] && CHANGEMSG="${CHANGEMSG} ${extrastuff}"
  # write the changelog entry:
  changelog "$itemid" "$operation" "$extrastuff" "${pkglist[@]}"


  #-----------------------------#
  # metadata files              #
  #-----------------------------#

  for pkgpath in "${pkglist[@]}"; do

    pkgbasename=$(basename "$pkgpath")
    pkgnam=$(echo "$pkgbasename" | rev | cut -f4- -d- | rev)

    nosuffix="${pkgpath%.t?z}"
    dotlst="${nosuffix}.lst"
    dotrev="${nosuffix}.rev"
    dotdep="${nosuffix}.dep"
    dottxt="${nosuffix}.txt"
    dotmeta="${nosuffix}.meta"
    # but the .md5, .sha256 and .asc filenames include the suffix:
    dotmd5="${pkgpath}.md5"
    dotsha256="${pkgpath}.sha256"
    dotasc="${pkgpath}.asc"

    # Although gen_repos_files.sh can create most of the following files,
    # it's quicker to create them here (we can probably get the slack-desc from the
    # packaging directory, and if test_package has been run we can reuse its list
    # of the package contents).

    #-----------------------------#
    # .lst                        #
    #-----------------------------#
    # do this first so we have a quick way of seeing what's in the package

    if [ ! -f "$dotlst" ]; then
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
    fi

    #-----------------------------#
    # .rev                        #
    #-----------------------------#

    oldstylerev=$(dirname "$dotrev")/.revision
    if [ -f "$oldstylerev" ]; then
      mv "$oldstylerev" "$dotrev"
    elif [ ! -f "$dotrev" ]; then
      print_current_revinfo "$itemid" > "$dotrev"
    fi

    #-----------------------------#
    # .dep (no deps => no file)   #
    #-----------------------------#

    if [ ! -f "$dotdep" ]; then
      if [ -n "${FULLDEPS[$itemid]}" ]; then
        for dep in ${FULLDEPS[$itemid]}; do
          printf "%s\n" "$(basename "$dep")" >> "$dotdep"
        done
      fi
    fi

    #-----------------------------#
    # .txt                        #
    #-----------------------------#

    if [ ! -f "$dottxt" ]; then
      if [ -f "$SR_SBREPO"/"$itemdir"/slack-desc ]; then
        sed -n '/^#/d;/:/p' < "$SR_SBREPO"/"$itemdir"/slack-desc > "$dottxt"
      elif grep -q install/slack-desc "$dotlst"; then
        tar xf "$pkgpath" -O install/slack-desc 2>/dev/null | sed -n '/^#/d;/:/p' > "$dottxt"
      else
        # bad egg!
        > "$dottxt"
      fi
    fi

    #-----------------------------#
    # .meta                       #
    #-----------------------------#

    if [ ! -f "$dotmeta" ]; then

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

        # slack-required
        # from packaging dir, or extract from package, or synthesise it from DIRECTDEPS
        if [ -f "$TMP"/package-"$pkgnam"/install/slack-required ]; then
          SLACKREQUIRED=$(tr -d ' ' < "$TMP"/package-"$pkgnam"/install/slack-required | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
        elif grep -q install/slack-required "$dotlst"; then
          SLACKREQUIRED=$(tar xf "$pkgpath" -O install/slack-required 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
        elif [ -n "${DIRECTDEPS[$itemid]}" ]; then
          SLACKREQUIRED=$(for dep in ${DIRECTDEPS[$itemid]}; do printf "%s\n" "$(basename "$dep")"; done | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
        else
          SLACKREQUIRED=""
        fi
        echo "PACKAGE REQUIRED:  $SLACKREQUIRED" >> "$dotmeta"

        # slack-conflicts
        # from packaging dir, or extract from package, or get it from the hintfile
        if [ -f "$TMP"/package-"$pkgnam"/install/slack-conflicts ]; then
          SLACKCONFLICTS=$(tr -d ' ' < "$TMP"/package-"$pkgnam"/install/slack-conflicts | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
        elif grep -q install/slack-conflicts "$dotlst"; then
          SLACKCONFLICTS=$(tar xf "$pkgpath" -O install/slack-conflicts 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
        elif [ -n "${HINT_CONFLICTS[$itemid]}" ]; then
          SLACKCONFLICTS="${HINT_CONFLICTS[$itemid]}"
        else
          SLACKCONFLICTS=""
        fi
        echo "PACKAGE CONFLICTS:  $SLACKCONFLICTS" >> "$dotmeta"

        # slack-suggests
        # from packaging dir, or extract from package
        if [ -f "$TMP"/package-"$pkgnam"/install/slack-suggests ]; then
          SLACKSUGGESTS=$(tr -d ' ' < "$TMP"/package-"$pkgnam"/install/slack-suggests | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
        elif grep -q install/slack-suggests "$dotlst"; then
          SLACKCONFLICTS=$(tar xf "$pkgpath" -O install/slack-suggests 2>/dev/null | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
        else
          SLACKSUGGESTS=""
        fi
        echo "PACKAGE SUGGESTS:  $SLACKSUGGESTS" >> "$dotmeta"

      fi

      echo "PACKAGE DESCRIPTION:" >> "$dotmeta"
      cat  "$dottxt" >> "$dotmeta"
      echo "" >> "$dotmeta"

    fi

    #-----------------------------#
    # .md5                        #
    #-----------------------------#

    if [ ! -f "$dotmd5" ]; then
      ( cd "$MYREPO"/"$itemdir"/; md5sum "$pkgbasename" > "$dotmd5" )
    fi

    #-----------------------------#
    # .sha256                     #
    #-----------------------------#

    if [ ! -f "$dotsha256" ]; then
      ( cd "$MYREPO"/"$itemdir"/; sha256sum "$pkgbasename" > "$dotsha256" )
    fi

    #-----------------------------#
    # .asc                        #
    #-----------------------------#
    # gen_repos_files.sh will do it later :-)

    # Finally, we can get rid of this:
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
          eval "$gaddcmd"
        fi
        uaddcmd="useradd  -u $unum -g $ugroup -c $itemprgnam -d $udir -s $ushell $uargs $uname"
        log_verbose -a "Adding user:  $uaddcmd"
        eval "$uaddcmd"
      else
        log_verbose -a "User $uname already exists."
      fi
    done
  fi

  return 0
}
