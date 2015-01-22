#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#
# Contains code and concepts from 'gen_repos_files.sh' 1.90
#   Copyright (c) 2006-2013  Eric Hameleers, Eindhoven, The Netherlands
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#   http://www.slackware.com/~alien/tools/gen_repos_files.sh
#
#-------------------------------------------------------------------------------
# revfunctions.sh - revision functions for slackrepo
#   print_current_revinfo
#   needs_build
#   write_pkg_metadata
#-------------------------------------------------------------------------------

function print_current_revinfo
# Prints an item's revision info on standard output.
# Arguments:
# $1 = itemid
# Return status always 0
#
# The first line of output is revision info for itemid itself:
#   itemid / depid1,depid2... version built rev os hintcksum
# and then there is a line for each depid in deplist:
#   itemid depid1 / version built rev os hintcksum
# Fields are as follows, note that / is used as a placeholder for empty fields.
#   itemid
#   / (or depid)         (for dependency's revision info)
#   deplist (or /)       (comma separated list of itemid's dependencies, or / if no deps)
#   version              (arbitrary string)
#   built                (secs since epoch)
#   rev                  (gitrevision, or secs since epoch if not git)
#   os                   (<osname><osversion>)
#   hintcksum            (md5sum, or / if no hintfile)
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemdir="${ITEMDIR[$itemid]}"

  # (1) Get the item's own stuff.
  # For calculating whether an item needs to be built, or for recording the
  # revision of a new package, we need the revision in the SlackBuild repo,
  # not the Package repo, so the database and REVCACHE are not used for itemid.

  depid="/"
  deplist="${DIRECTDEPS[$itemid]:-/}"
  verstuff="${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
  bltstuff="$(date +%s)"

  if [ "$GOTGIT" = 'y' ]; then
    revstuff="${GITREV[$itemid]}"
    [ "${GITDIRTY[$itemid]}" = 'y' ] && revstuff="${revstuff}+dirty"
  else
    # Use newest file's seconds since epoch ;-)
    revstuff="$(cd "$SR_SBREPO"/"$itemdir"; ls -t | head -n 1 | xargs stat --format='%Y')"
  fi

  osstuff="${SYS_OSNAME}${SYS_OSVER}"

  hintstuff='/'
  if [ -n "${HINTFILE[$itemdir]}" ]; then
    hintstuff="$(md5sum "${HINTFILE[$itemdir]}" | sed 's/ .*//')"
  fi

  echo "$itemid" '/' "${deplist// /,}" "${verstuff} ${bltstuff} ${revstuff} ${osstuff} ${hintstuff}"

  # (2) Get each dependency's stuff.
  # We can use the database.

  if [ "$deplist" != '/' ]; then
    for depid in ${deplist}; do
      deprevdata=$(db_get_rev "$depid")
      [ -n "$deprevdata" ] && echo "$itemid" "$depid" "$deprevdata"
    done
  fi

  return 0
}

#-------------------------------------------------------------------------------

function needs_build
# Works out whether the package needs to be built.
# $1 = itemid
# Return status:
# 0 = yes, needs to be built
# 1 = no, does not need to be built
# Also sets these variables when status=0:
# BUILDINFO = friendly changelog-style message describing the build
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam=${ITEMPRGNAM[$itemid]}
  local itemdir=${ITEMDIR[$itemid]}
  local -a pkglist revfilelist deprevfilelist modifilelist
  local prgnam version built revision depends os hintfile

  # Package dir not in either repo => add
  if [ ! -d "$DRYREPO"/"$itemdir" ] && [ ! -d "$SR_PKGREPO"/"$itemdir" ]; then
    BUILDINFO="add version ${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
    return 0
  fi

  # Package dir has no packages => add
  pkglist=( "$SR_PKGREPO"/"$itemdir"/*.t?z )
  if [ ! -f "${pkglist[0]}" ]; then
    # Nothing in the main repo, so look in dryrun repo
    pkglist=( "$DRYREPO"/"$itemdir"/*.t?z )
    if [ ! -f "${pkglist[0]}" ]; then
      BUILDINFO="add version ${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
      return 0
    fi
  fi

  # Get info about the existing package from the database
  read pkgdeps pkgver pkgblt pkgrev pkgos pkghnt < <(db_get_rev "$itemid")
  [ "$pkgdeps" = '/' ] && pkgdeps=''

  # Are we upversioning => update
  currver="${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
  if [ "$pkgver" != "$currver" ]; then
    BUILDINFO="update for version $currver"
    return 0
  fi

  if [ "$GOTGIT" = 'n' ]; then

    # If this isn't a git repo, and any of the files have been modified since the package was built => update
    modifilelist=( $(find -L "$SR_SBREPO"/"$itemdir" -newermt @"$pkgblt" 2>/dev/null) )
    if [ ${#modifilelist[@]} != 0 ]; then
      BUILDINFO="update for modified files"
      return 0
    fi

  else

    # The next couple of checks require git:
    dirtymark=''
    [ "${GITDIRTY[$itemid]}" = 'y' ] && dirtymark='+dirty'
    currrev="${GITREV[$itemid]}$dirtymark"
    shortcurrrev="${currrev:0:7}$dirtymark"

    # If the git rev has changed => update
    if [ "$pkgrev" != "$currrev" ]; then
      #   if only README, slack-desc and .info have changed, don't build
      #   (the VERSION in the .info file has already been checked ;-)
      modifilelist=( $(cd "$SR_SBREPO"; git diff --name-only "$currrev" "$pkgrev" -- "$itemdir") )
      for modifile in "${modifilelist[@]}"; do
        bn=$(basename "$modifile")
        [ "$bn" = "README" ] && continue
        [ "$bn" = "slack-desc" ] && continue
        [ "$bn" = "$itemprgnam.info" ] && continue
        BUILDINFO="update for git $shortcurrrev"
        return 0
      done
    fi

    # If git is dirty, and any file has been modified since the package was built => update
    if [ "${GITDIRTY[$itemid]}" = 'y' ]; then
      modifilelist=( $(find -L "$SR_SBREPO"/"$itemdir" -newermt @"$pkgblt" 2>/dev/null) )
      if [ ${#modifilelist[@]} != 0 ]; then
        BUILDINFO="update for git $shortcurrrev"
        return 0
      fi
    fi

  fi

  # Is this the top-level item and are we in rebuild mode
  #   => rebuild if it hasn't previously been rebuilt (as a dep of something else)
  if [ "$itemid" = "$ITEMID" -a "$CMD" = 'rebuild' ]; then
    found='n'
    for previously in "${OKLIST[@]}"; do
      if [ "$previously" = "$ITEMID" ]; then found='y'; break; fi
    done
    if [ "$found" = 'n' ]; then
      BUILDINFO="rebuild"
      return 0
    fi
  fi

  # Has the list of deps changed => rebuild
  currdeps="${DIRECTDEPS[$itemid]// /,}"
  if [ "$pkgdeps" != "$currdeps" ]; then
    BUILDINFO="rebuild for added/removed deps"
    return 0
  fi

  # Have any of the deps been updated => rebuild
  local -a updeps
  updeps=()
  for dep in ${DIRECTDEPS[$itemid]}; do
    # ignore built field (merely rebuilt deps don't matter) and hintfile field
    # (significant hintfile changes will affect version or deps, which have already been checked)
    pkgdeprev=$(db_get_rev "$itemid" "$dep" | cut -f1,2,4,5 -d" ")
    currdeprev=$(db_get_rev "$dep" | cut -f1,2,4,5 -d" ")
    [ "$pkgdeprev" != "$currdeprev" ] && updeps+=( "$dep" )
  done
  if [ "${#updeps}" != 0 ]; then
    log_verbose "Updated dependencies of ${itemid}:"
    log_verbose "$(printf '  %s\n' "${updeps[@]}")"
    BUILDINFO="rebuild for updated deps"
    return 0
  fi

  # Has the OS changed => rebuild
  curros="${SYS_OSNAME}${SYS_OSVER}"
  if [ "$pkgos" != "$curros" ]; then
    BUILDINFO="rebuild for upgraded ${SYS_OSNAME}"
    return 0
  fi

  # Has the hintfile changed => rebuild
  currhnt='/'
  if [ -n "${HINTFILE[$itemdir]}" ]; then
    currhnt="$(md5sum "${HINTFILE[$itemdir]}" | sed 's/ .*//')"
  fi
  if [ "$pkghnt" != "$currhnt" ]; then
    BUILDINFO="rebuild for hintfile changes"
    return 0
  fi

  # ok, it is genuinely up to date!
  if [ "$itemid" = "$ITEMID" ]; then
    log_important "$itemid is up-to-date."
  else
    log_normal "$itemid is up-to-date."
  fi
  return 1

}

#-------------------------------------------------------------------------------

function write_pkg_metadata
# Update database, write changelog entries, and create metadata files in package dir
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

  #-----------------------------#
  # Update database             #
  #-----------------------------#

  if [ "$OPT_DRY_RUN" = 'y' ]; then
    # don't update the database -- just set REVCACHE
    REVCACHE[$itemid]=$(print_current_revinfo "$itemid" | head -n 1 | cut -f3- -d" ")
  else
    currentrevinfo="$(print_current_revinfo "$itemid")"
    db_del_rev "$itemid"
    echo "$currentrevinfo" | while read revinfo; do
      db_set_rev $revinfo
    done
  fi

  #-----------------------------#
  # Write changelog entries     #
  # (gratuitously elaborate :-) #
  #-----------------------------#

  myrepo="$SR_PKGREPO"
  [ "$OPT_DRY_RUN" = 'y' ] && myrepo="$DRYREPO"
  pkglist=( "$myrepo"/"$itemdir"/*.t?z )

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
  [ "$extrastuff" = '()' ] && extrastuff=''
  # build_ok will need this:
  CHANGEMSG="$operation"
  [ -n "$extrastuff" ] && CHANGEMSG="${CHANGEMSG} ${extrastuff}"
  # write the changelog entry:
  changelog "$itemid" "$operation" "$extrastuff" "${pkglist[@]}"


  #-----------------------------#
  # Create metadata files       #
  #-----------------------------#

  for pkgpath in "${pkglist[@]}"; do
    # pkglist should be 100% valid, but this can't hurt:
    [ ! -f "$pkgpath" ] && continue

    pkgdirname=$(dirname "$pkgpath")
    pkgbasename=$(basename "$pkgpath")
    pkgnam=$(echo "$pkgbasename" | rev | cut -f4- -d- | rev)

    nosuffix="${pkgpath%.t?z}"
    dotlst="${nosuffix}.lst"
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
      ( cd "$pkgdirname"; md5sum "$pkgbasename" > "$dotmd5" )
    fi

    #-----------------------------#
    # .sha256                     #
    #-----------------------------#

    if [ ! -f "$dotsha256" ]; then
      ( cd "$pkgdirname"; sha256sum "$pkgbasename" > "$dotsha256" )
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
