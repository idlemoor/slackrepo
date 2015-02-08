#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#
# write_pkg_metadata contains code and concepts from 'gen_repos_files.sh' 1.90
#   Copyright (c) 2006-2013  Eric Hameleers, Eindhoven, The Netherlands
#   All rights reserved.  For licence details, see the file 'LICENCE'.
#   http://www.slackware.com/~alien/tools/gen_repos_files.sh
#
#-------------------------------------------------------------------------------
# revfunctions.sh - revision functions for slackrepo
#   print_current_revinfo
#   calculate_deps_and_status
#   calculate_item_status
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
    hintstuff="$(md5sum "${HINTFILE[$itemdir]}")"; hintstuff="${hintstuff/ */}"
  fi

  echo "$itemid" '/' "${deplist// /,}" "${verstuff} ${bltstuff} ${revstuff} ${osstuff} ${hintstuff}"

  # (2) Get each dependency's stuff.
  # Because the dep tree is processed bottom up, it should already be in the database.
  if [ "$deplist" != '/' ]; then
    for depid in ${deplist}; do
      deprevdata=$(db_get_rev "$depid")
      [ -n "$deprevdata" ] && echo "$itemid" "$depid" "$deprevdata"
    done
  fi

  return 0
}

#-------------------------------------------------------------------------------

declare -a NEEDSBUILD
declare -A STATUS STATUSINFO DIRECTDEPS FULLDEPS

function calculate_deps_and_status
# Works out dependencies and their build statuses.
# Populates ${STATUS[$itemid]}, ${STATUSINFO[$itemid]}, ${NEEDSBUILD[@]},
#   ${DIRECTDEPS[$itemid]}, and ${FULLDEPS[$itemid]}.
# Writes a pretty tree to $DEPTREE.
# Arguments:
#   $1 = itemid
#   $2 = parent's itemid, or null if no parent
#   $3 = indentation for pretty tree
# Return status:
#   0 = ok
#   1 = any error, e.g. a previous build fail remembered somewhere in the dep tree
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local parentid="${2:-}"
  local indent="${3:-}"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"

  # Examine the current item
  if [ -z "${STATUS[$itemid]}" ]; then
    parse_info_and_hints "$itemid"
    calculate_item_status "$itemid" "$parentid" || return 1
  fi

  # Verify all the dependencies in the info+hints, and make a list of them
  local dep
  local -a deplist=()
  for dep in ${INFOREQUIRES[$itemid]}; do
    if [ "$dep" = '%README%' ]; then
      log_warning "${itemid}: Unhandled %README% in ${itemprgnam}.info"
    elif [ "$dep" = "$itemprgnam" ]; then
      log_warning "${itemid}: Ignoring dependency of ${itemprgnam} on itself"
    else
      find_slackbuild "$dep"
      fstat=$?
      if [ $fstat = 0 ]; then
        deplist+=( "${R_SLACKBUILD}" )
      elif [ $fstat = 1 ]; then
        log_warning "${itemid}: Dependency $dep does not exist"
      elif [ $fstat = 2 ]; then
        log_warning "${itemid}: Dependency $dep matches more than one SlackBuild"
      fi
    fi
  done

  # Canonicalise the list of deps so we can detect changes in the future.
  deplist=( $(printf '%s\n' ${deplist[*]} | sort -u) )
  DIRECTDEPS[$itemid]="${deplist[*]}"

  # Walk the whole dependency tree for the item.
  if [ -z "${DIRECTDEPS[$itemid]}" ]; then
    # if there are no direct deps, then there are no recursive deps ;-)
    FULLDEPS[$itemid]=''
  else
    local -a myfulldeps=()
    for dep in "${deplist[@]}"; do
      calculate_deps_and_status "$dep" "$itemid" "$indent  "
      for newdep in ${FULLDEPS[$dep]} "$dep"; do
        gotnewdep='n'
        for olddep in "${myfulldeps[@]}"; do
          if [ "$newdep" = "$olddep" ]; then
            gotnewdep='y'
            break
          elif [ "$newdep" = "$itemid" ]; then
            log_error "${itemid}: Circular dependency via $dep"
            return 1
          fi
        done
        if [ "$gotnewdep" = 'n' ]; then
          myfulldeps+=( "$newdep" )
        fi
      done
    done
    FULLDEPS[$itemid]="${myfulldeps[*]}"
  fi

  # Adjust the item's build status now that we know about its deps.

  # Has the list of deps changed => rebuild
  pkgdeps=$(db_get_rev "$itemid")
  [ "${pkgdeps/ */}" = '/' ] && pkgdeps=""
  if [ "${STATUS[$itemid]}" = 'ok' ] && [ "${pkgdeps/ */}" != "${DIRECTDEPS[$itemid]// /,}" ]; then
    STATUS[$itemid]="rebuild"
    STATUSINFO[$itemid]="rebuild for added/removed deps"
  fi

  # Have any of the deps been updated => rebuild
  # Are any of the deps skipped or unsupported => abort unless item is the same
  # Are any of the deps aborted or failed => abort
  for dep in ${DIRECTDEPS[$itemid]}; do
    case "${STATUS[$dep]}" in
      'add' | 'update' | 'updated' )
        if [ "${STATUS[$itemid]}" = 'ok' ]; then
          STATUS[$itemid]="rebuild"
          STATUSINFO[$itemid]="rebuild for updated deps"
        fi
        ;;
      'ok' | 'rebuild' )
        :
        ;;
      'skipped' | 'unsupported' )
        if [ "${STATUS[$itemid]}" != "${STATUS[$dep]}" ]; then
          STATUS[$itemid]="aborted"
          STATUSINFO[$itemid]=""
        fi
        ;;
      'aborted' | 'failed' | '*' )
        STATUS[$itemid]="aborted"
        STATUSINFO[$itemid]=""
        ;;
    esac
  done

  if [ "${STATUS[$itemid]}" = 'ok' ]; then
    prettystatus=' [ok]'
  elif [ "${STATUS[$itemid]}" = 'add' ] || [ "${STATUS[$itemid]}" = 'update' ] || [ "${STATUS[$itemid]}" = 'rebuild' ]; then
    prettystatus=" [${tputgreen}${STATUS[$itemid]}${tputnormal}]"
    additem='y'
    for todo in "${NEEDSBUILD[@]}"; do
      [ "$todo" != "$itemid" ] && continue
      additem='n'
      break
    done
    [ "$additem" = 'y' ] && NEEDSBUILD+=( "$itemid" )
  elif [ "${STATUS[$itemid]}" = 'updated' ] || [ "${STATUS[$itemid]}" = 'skipped' ] || [ "${STATUS[$itemid]}" = 'unsupported' ]; then
    prettystatus=" [${tputyellow}${STATUS[$itemid]}${tputnormal}]"
  else # failed, aborted, and other not-yet-invented catastrophes
    prettystatus=" [${tputred}${STATUS[$itemid]}${tputnormal}]"
    # Add the item to NEEDSBUILD anyway, for logging purposes
    additem='y'
    for todo in "${NEEDSBUILD[@]}"; do
      [ "$todo" != "$itemid" ] && continue
      additem='n'
      break
    done
    [ "$additem" = 'y' ] && NEEDSBUILD+=( "$itemid" )
  fi
  DEPTREE="${indent}${itemid}${prettystatus}"$'\n'"$DEPTREE"

  if [ "${STATUS[$itemid]}" = 'aborted' ] || [ "${STATUS[$itemid]}" = 'failed' ] || [ "${STATUS[$itemid]}" = 'skipped' ] || [ "${STATUS[$itemid]}" = 'unsupported' ]; then
    return 1
  else
    return 0
  fi
}

#-------------------------------------------------------------------------------

function calculate_item_status
# Works out whether the package needs to be built etc
# $1 = itemid
# $2 = parentid (or null)
# Return status:
# 0 = success, STATUS[$itemid] (and optionally STATUSINFO[$itemid]) have been set
# 1 = any failure
# Also sets these variables when status=0:
# BUILDEXTRA = friendly changelog-style message describing the build
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[*]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam=${ITEMPRGNAM[$itemid]}
  local itemdir=${ITEMDIR[$itemid]}
  local -a pkglist modifilelist

  # Quick checks if we've already seen this item:
  if [ "${STATUS[$itemid]}" = "ok" ] || [ "${STATUS[$itemid]}" = "updated" ]; then
    if [ -n "$parentid" ]; then
      # check revisions - $itemid may be more recent than $parentid
      read pkgdeps pkgver pkgblt pkgrev pkgos pkghnt < <(db_get_rev "$itemid")
      read pardeps parver parblt parrev paros parhnt < <(db_get_rev "$parentid" "$itemid")
      # proceed only if the parent exists in the database
      if [ "$parver" != '' ]; then
        # ignore built field (merely rebuilt deps don't matter)
        # and ignore hintfile field (significant changes will show up as version or deplist changes)
        if [ "$pardeps $parver $parrev $paros" != "$pkgdeps $pkgver $pkgrev $pkgos" ]; then
          STATUS[$itemid]="updated"
          STATUSINFO[$itemid]=""
          return 0
        fi
      fi
    fi
    STATUS[$itemid]="ok"
    STATUSINFO[$itemid]=""
    return 0
  elif [ "${STATUS[$itemid]}" = "aborted" ] || [ "${STATUS[$itemid]}" = "failed" ] || [ "${STATUS[$itemid]}" = "skipped" ] || [ "${STATUS[$itemid]}" = "unsupported" ]; then
    # the situation is not going to improve ;-)
    return 0
  fi

  # Package dir not in either repo => add
  if [ ! -d "$DRYREPO"/"$itemdir" ] && [ ! -d "$SR_PKGREPO"/"$itemdir" ]; then
    STATUS[$itemid]="add"
    STATUSINFO[$itemid]="add version ${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
    return 0
  fi

  # Package dir has no packages => add
  pkglist=( "$SR_PKGREPO"/"$itemdir"/*.t?z )
  if [ ! -f "${pkglist[0]}" ]; then
    # Nothing in the main repo, so look in dryrun repo
    pkglist=( "$DRYREPO"/"$itemdir"/*.t?z )
    if [ ! -f "${pkglist[0]}" ]; then
      STATUS[$itemid]="add"
      STATUSINFO[$itemid]="add version ${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
      return 0
    fi
  fi

  # Get info about the existing build from the database
  read pkgdeps pkgver pkgblt pkgrev pkgos pkghnt < <(db_get_rev "$itemid")

  # Are we upversioning => update
  currver="${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
  if [ "$pkgver" != "$currver" ]; then
    STATUS[$itemid]="update"
    STATUSINFO[$itemid]="update for version $currver"
    return 0
  fi

  if [ "$GOTGIT" = 'n' ]; then

    # If this isn't a git repo, and any of the files have been modified since the package was built => update
    modifilelist=( $(find -L "$SR_SBREPO"/"$itemdir" -newermt @"$pkgblt" 2>/dev/null) )
    if [ ${#modifilelist[@]} != 0 ]; then
      STATUS[$itemid]="update"
      STATUSINFO[$itemid]="update for modified files"
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
      if [ "${GITDIRTY[$itemid]}" != 'y' -a "${pkgrev/*+/+}" != '+dirty' ]; then
        #   if only README, slack-desc and .info have changed, don't build
        #   (the VERSION in the .info file has already been checked ;-)
        modifilelist=( $(cd "$SR_SBREPO"; git diff --name-only "$pkgrev" "$currrev" -- "$itemdir") )
        for modifile in "${modifilelist[@]}"; do
          bn="${modifile##*/}"
          [ "$bn" = "README" ] && continue
          [ "$bn" = "slack-desc" ] && continue
          [ "$bn" = "$itemprgnam.info" ] && continue
          STATUS[$itemid]="update"
          STATUSINFO[$itemid]="update for git $shortcurrrev"
          return 0
        done
      else
        # we can't do the above check if git is or was dirty
        STATUS[$itemid]="update"
        STATUSINFO[$itemid]="update for git $shortcurrrev"
        return 0
      fi
    fi

    # If git is dirty, and any file has been modified since the package was built => update
    if [ "${GITDIRTY[$itemid]}" = 'y' ]; then
      modifilelist=( $(find -L "$SR_SBREPO"/"$itemdir" -newermt @"$pkgblt" 2>/dev/null) )
      if [ ${#modifilelist[@]} != 0 ]; then
        STATUS[$itemid]="update"
        STATUSINFO[$itemid]="update for git $shortcurrrev"
        return 0
      fi
    fi

  fi

  # check revisions - $itemid may be more recent than $parentid
  if [ -n "$parentid" ]; then
    read pardeps parver parblt parrev paros parhnt < <(db_get_rev "$parentid" "$itemid")
    # proceed only if the parent exists in the database
    if [ "$parver" != '' ]; then
      # ignore built field (merely rebuilt deps don't matter)
      # and ignore hintfile field (significant changes will show up as version or deplist changes)
      if [ "$pardeps $parver $parrev $paros" != "$pkgdeps $pkgver $pkgrev $pkgos" ]; then
        STATUS[$itemid]="updated"
        STATUSINFO[$itemid]=""
        return 0
      fi
    fi
  fi

  # Is this the top-level item and are we in rebuild mode
  #   => rebuild if it hasn't previously been built in this session (as a dep of something else)
  if [ "$itemid" = "$ITEMID" -a "$CMD" = 'rebuild' ]; then
    found='n'
    for previously in "${OKLIST[@]}"; do
      if [ "$previously" = "$ITEMID" ]; then found='y'; break; fi
    done
    if [ "$found" = 'n' ]; then
      STATUS[$itemid]="rebuild"
      STATUSINFO[$itemid]="rebuild"
      return 0
    fi
  fi

  # Has the OS changed => rebuild
  curros="${SYS_OSNAME}${SYS_OSVER}"
  if [ "$pkgos" != "$curros" ]; then
    STATUS[$itemid]="rebuild"
    STATUSINFO[$itemid]="rebuild for upgraded ${SYS_OSNAME}"
    return 0
  fi

  # Has the hintfile changed => rebuild
  currhnt='/'
  if [ -n "${HINTFILE[$itemdir]}" ]; then
    currhnt="$(md5sum "${HINTFILE[$itemdir]}")"; currhnt="${currhnt/ */}"
  fi
  if [ "$pkghnt" != "$currhnt" ]; then
    STATUS[$itemid]="rebuild"
    STATUSINFO[$itemid]="rebuild for hintfile changes"
    return 0
  fi

  # It seems to be up to date!
  STATUS[$itemid]="ok"
  STATUSINFO[$itemid]=""
  return 0

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

  operation="$(echo "${STATUSINFO[$itemid]}" | sed -e 's/^add/Added/' -e 's/^update/Updated/' -e 's/^rebuild/Rebuilt/' )"
  extrastuff=''
  case "${STATUSINFO[$itemid]}" in
  add*)
      # append short description from slack-desc (if there's no slack-desc, this should be null)
      extrastuff="($(grep "^${pkgnam}: " "$SR_SBREPO"/"$itemdir"/slack-desc 2>/dev/null| head -n 1 | sed -e 's/.*(//' -e 's/).*//'))"
      ;;
  'update for git'*)
      # append title of the latest commit message
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

    pkgdirname="${pkgpath%/*}"
    pkgbasename="${pkgpath##*/}"
    pkgnam="${pkgbasename%-*-*-*}"

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
          printf "%s\n" "${dep##*/}" >> "$dotdep"
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
          SLACKREQUIRED=$(for dep in ${DIRECTDEPS[$itemid]}; do printf "%s\n" "${dep##*/}"; done | tr -d ' ' | xargs -r -iZ echo -n "Z," | sed -e "s/,$//")
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
