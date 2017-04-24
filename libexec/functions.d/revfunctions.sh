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
  if [ -n "${HINTFILE[$itemdir]}" ] && [ -s "${HINTFILE[$itemdir]}" ]; then
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

declare -a TODOLIST
declare -A STATUS STATUSINFO DIRECTDEPS FULLDEPS

function calculate_deps_and_status
# Works out dependencies and their build statuses.
# Populates ${STATUS[$itemid]}, ${STATUSINFO[$itemid]}, ${TODOLIST[@]},
#   ${DIRECTDEPS[$itemid]}, and ${FULLDEPS[$itemid]}.
# Writes a pretty tree to $DEPTREE.
# Arguments:
#   $1 = itemid
#   $2 = parent's itemid, or null if no parent
#   $3 = indentation for pretty tree
# Return status: always 0.
#   If anything really bad happened, TODOLIST will be empty ;-)
{
  local itemid="$1"
  local parentid="${2:-}"
  local indent="${3:-}"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"

  # These variables are used both here and in calculate_item_status.
  # This isn't terribly efficient, but at least db_get_rev has a cache.
  local pkgdeps pkgver pkgblt pkgrev pkgos pkghnt
  read  pkgdeps pkgver pkgblt pkgrev pkgos pkghnt < <(db_get_rev "$itemid")
  local pardeps parver parblt parrev paros parhnt
  if [ -n "$parentid" ]; then
    read pardeps parver parblt parrev paros parhnt < <(db_get_rev "$parentid" "$itemid")
  fi

  # Examine the current item
  [ -z "${STATUS[$itemid]}" ] && parse_info_and_hints "$itemid"
  calculate_item_status "$itemid" "$parentid"

  if [ "${DIRECTDEPS[$itemid]-unset}" = 'unset' ]; then
    # Verify all the dependencies in the info+hints, and make a list of them
    local dep
    local -a deplist=()
    for dep in ${INFOREQUIRES[$itemid]}; do
      if [ "$dep" = '%README%' ]; then
        # %README% is now removed unconditionally, but we'll leave this check here for now:
        log_warning "${itemid}: Unhandled %README% in ${itemprgnam}.info"
      elif [ "$dep" = "$itemprgnam" ]; then
        log_warning "${itemid}: Ignoring dependency of ${itemprgnam} on itself"
      else
        parse_arg "${dep}" "${itemid}"
        [ "${#PARSEDARGS[@]}" != 0 ] && deplist+=( "${PARSEDARGS[@]}" )
      fi
    done
    # Canonicalise the list of deps so we can detect changes in the future.
    deplist=( $(printf '%s\n' ${deplist[*]} | sort -u) )
    DIRECTDEPS[$itemid]="${deplist[*]}"
  fi

  # Recursively walk the whole dependency tree for the item.
  if [ -z "${DIRECTDEPS[$itemid]}" ]; then
    # if there are no direct deps, then there are no recursive deps ;-)
    FULLDEPS[$itemid]=''
  else
    local dep newdep olddep alreadygotnewdep
    local -a myfulldeps=()
    for dep in ${DIRECTDEPS[$itemid]}; do
      calculate_deps_and_status "$dep" "$itemid" "$indent  "
      for newdep in ${FULLDEPS[$dep]} "$dep"; do
        alreadygotnewdep='n'
        for olddep in "${myfulldeps[@]}"; do
          if [ "$newdep" = "$olddep" ]; then
            alreadygotnewdep='y'
            break
          elif [ "$newdep" = "$itemid" ]; then
            alreadygotnewdep='y'
            log_error "${itemid}: Circular dependency via $dep (ignored)"
            break
          fi
        done
        if [ "$alreadygotnewdep" = 'n' ]; then
          myfulldeps+=( "$newdep" )
        fi
      done
    done
    FULLDEPS[$itemid]="${myfulldeps[*]}"
  fi

  # Now that we know about the deps, adjust the item's status:

  # (1) has the list of deps changed => rebuild
  [ "${pkgdeps}" = '/' ] && pkgdeps=""
  if [ "${pkgdeps/ */}" != "${DIRECTDEPS[$itemid]// /,}" ]; then
    if [ "${STATUS[$itemid]}" = 'ok' ]; then
      STATUS[$itemid]="rebuild"
      STATUSINFO[$itemid]="rebuild for added/removed deps"
    elif [ "${STATUS[$itemid]}" = 'updated' ]; then
      STATUS[$itemid]='updated+rebuild'
      STATUSINFO[$itemid]="updated + rebuild for added/removed deps"
    fi
  fi

  for dep in ${DIRECTDEPS[$itemid]}; do
    case "${STATUS[$dep]}" in
      # (2) is this dep ok, or merely being rebuilt => no need to adjust the item
      'ok' | 'rebuild' )
        :
        ;;
      # (3) have any of the deps been updated => rebuild the item
      'add' | 'update' | 'updated' | 'updated+rebuild' )
        if [ "${STATUS[$itemid]}" = 'ok' ]; then
          STATUS[$itemid]="rebuild"
          STATUSINFO[$itemid]="rebuild for updated deps"
        elif [ "${STATUS[$itemid]}" = 'updated' ]; then
          STATUS[$itemid]='updated+rebuild'
          STATUSINFO[$itemid]="updated + rebuild for updated deps"
        fi
        ;;
      # (4) are any of the deps skipped, unsupported, aborted, failed, whatever
      #     => abort the item unless it is skipped/unsupported
      'skipped' | 'unsupported' | 'remove' | 'removed' | 'aborted' | 'failed' | '*' )
        if [ "${STATUS[$itemid]}" != "skipped" ] && [ "${STATUS[$itemid]}" != "unsupported" ] ; then
          STATUS[$itemid]="aborted"
          STATUSINFO[$itemid]="aborted"
        fi
        ;;
    esac
  done

  if [ "$CMD" = 'rebuild' ] && [ "$itemid" = "$ITEMID" ] && [ "${STATUS[$itemid]}" = 'ok' ]; then
    # (5) force a rebuild of the top level item if it hasn't previously been
    # built in this session (as a dep of something else)
    found='n'
    for previously in "${OKLIST[@]}"; do
      if [ "$previously" = "$itemid" ]; then found='y'; break; fi
    done
    if [ "$found" = 'n' ]; then
      STATUS[$itemid]="rebuild"
      STATUSINFO[$itemid]="rebuild"
    fi
  fi

  # Add this item to the dependency tree and TODOLIST.
  # Everything except 'ok' and 'updated' is added to TODOLIST for logging purposes.

  if [ "${STATUS[$itemid]}" = 'ok' ]; then
    prettystatus=" ${colour_ok}(ok)${colour_normal}"
  elif [ "${STATUS[$itemid]}" = 'updated' ]; then
    prettystatus=" ${colour_updated}(${STATUS[$itemid]})${colour_normal}"
  else
    if [ "${STATUS[$itemid]}" = 'add' ] || [ "${STATUS[$itemid]}" = 'update' ] || [ "${STATUS[$itemid]}" = 'rebuild' ] || [ "${STATUS[$itemid]}" = 'updated+rebuild' ]; then
      prettystatus=" ${colour_build}(${STATUSINFO[$itemid]})${colour_normal}"
    elif [ "${STATUS[$itemid]}" = 'remove' ] || [ "${STATUS[$itemid]}" = 'skipped' ] || [ "${STATUS[$itemid]}" = 'unsupported' ]; then
      prettystatus=" ${colour_skip}(${STATUS[$itemid]})${colour_normal}"
    else # removed, failed, aborted, and other not-yet-invented catastrophes
      prettystatus=" ${colour_fail}(${STATUS[$itemid]})${colour_normal}"
    fi
    additem='y'
    for todo in "${TODOLIST[@]}"; do
      [ "$todo" != "$itemid" ] && continue
      additem='n'
      break
    done
    [ "$additem" = 'y' ] && TODOLIST+=( "$itemid" )
  fi
  DEPTREE="${indent}${itemid}${prettystatus}"$'\n'"$DEPTREE"

  return 0
}

#-------------------------------------------------------------------------------

function calculate_item_status
# Works out whether the package needs to be built etc
# $1 = itemid
# $2 = parentid (or null)
# Return status: always 0, sets STATUS[$itemid] and STATUSINFO[$itemid]
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local parentid="$2"
  local -a pkglist modifilelist

  # Quick checks if we've already seen this item:
  if [ "${STATUS[$itemid]}" = "ok" ] || [ "${STATUS[$itemid]}" = "updated" ]; then
    if [ -n "$parentid" ]; then
      # check revisions - $itemid may be more recent than $parentid
      # proceed only if the parent exists in the database
      if [ -n "$parver" ]; then
        # ignore built field (merely rebuilt deps don't matter)
        # and ignore hintfile field (significant changes will show up as version or deplist changes)
        if [ "$pardeps $parver $parrev $paros" != "$pkgdeps $pkgver $pkgrev $pkgos" ]; then
          STATUS[$itemid]="updated"
          STATUSINFO[$itemid]="updated"
          return 0
        fi
      fi
    fi
    STATUS[$itemid]="ok"
    STATUSINFO[$itemid]="ok"
    return 0
  elif [ "${STATUS[$itemid]}" = "aborted" ] || [ "${STATUS[$itemid]}" = "failed" ]  || \
       [ "${STATUS[$itemid]}" = "removed" ] || [ "${STATUS[$itemid]}" = "skipped" ] || \
       [ "${STATUS[$itemid]}" = "unsupported" ]; then
    # the situation is not going to improve ;-)
    return 0
  fi

  # No SlackBuild => remove
  if [ -z "$itemdir" ] || [ ! -d "$SR_SBREPO"/"$itemdir" ]; then
    STATUS[$itemid]="remove"
    STATUSINFO[$itemid]=""
    return 0
  fi

  # Package dir not in either repo => add
  if [ ! -d "$SR_PKGREPO"/"$itemdir" ]; then
    if [ -z "$DRYREPO" ] || [ ! -d "$DRYREPO"/"$itemdir" ]; then
      STATUS[$itemid]="add"
      STATUSINFO[$itemid]="add version ${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
    fi
    return 0
  fi

  # Package dir has no packages => add
  pkglist=( "$SR_PKGREPO"/"$itemdir"/*.t?z )   ####
  if [ ! -f "${pkglist[0]}" ]; then
    # Nothing in the main repo, so look in dryrun repo
    pkglist=( "$DRYREPO"/"$itemdir"/*.t?z )    ####
    if [ ! -f "${pkglist[0]}" ]; then
      STATUS[$itemid]="add"
      STATUSINFO[$itemid]="add version ${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
      return 0
    fi
  fi

  # Are we upversioning => update
  currver="${HINT_VERSION[$itemid]:-${INFOVERSION[$itemid]}}"
  if [ "$pkgver" != "$currver" ]; then
    STATUS[$itemid]="update"
    STATUSINFO[$itemid]="update for version $currver"
    return 0
  fi

  if [ "$GOTGIT" = 'n' ]; then

    # If this isn't a git repo, and any of the files have been modified since the package was built => update
    readarray -t modifilelist < <(find -L "$SR_SBREPO"/"$itemdir" -newermt @"$pkgblt" 2>/dev/null)
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
        # if only README, slack-desc and .info have changed, don't build
        # (the VERSION in the .info file has already been checked ;-)
        modifilelist=( $(cd "$SR_SBREPO"; git diff --name-only "$pkgrev" "$currrev" -- "$itemdir" 2>/dev/null) )
        if [ $? = 0 ]; then
          for modifile in "${modifilelist[@]}"; do
            bn="${modifile##*/}"
            [ "$bn" = "README" ] && continue
            [ "$bn" = "slack-desc" ] && continue
            [ "$bn" = "$itemprgnam.info" ] && continue
            STATUS[$itemid]="update"
            STATUSINFO[$itemid]="update for git $shortcurrrev"
            # get title of the latest commit message
            title="$(cd "$SR_SBREPO"/"$itemdir"; git log --pretty=format:%s -n 1 . | sed -e "s/.*${itemprgnam}: //" -e 's/\.$//')"
            [ -n "$title" ] && STATUSINFO[$itemid]="${STATUSINFO[$itemid]} \"$title\""
            return 0
          done
        else
          # nonzero status means $pkgrev is no longer valid (e.g. upstream has rewritten history) => update
          STATUS[$itemid]="update"
          STATUSINFO[$itemid]="update for git $shortcurrrev"
          return 0
        fi
      else
        # we can't do the above check if git is or was dirty
        STATUS[$itemid]="update"
        STATUSINFO[$itemid]="update for git $shortcurrrev"
        return 0
      fi
    fi

    # If git is dirty, and any file has been modified since the package was built => update
    if [ "${GITDIRTY[$itemid]}" = 'y' ]; then
      readarray -t modifilelist < <(find -L "$SR_SBREPO"/"$itemdir" -newermt @"$pkgblt" 2>/dev/null)
      if [ ${#modifilelist[@]} != 0 ]; then
        STATUS[$itemid]="update"
        STATUSINFO[$itemid]="update for git $shortcurrrev"
        return 0
      fi
    fi

  fi

  # check revisions - $itemid may be more recent than $parentid
  # (proceed only if $parentid has an entry in the database)
  if [ "$parver" != '' ]; then
    # ignore built field (merely rebuilt deps don't matter)
    # and ignore hintfile field (significant changes will show up as version or deplist changes)
    if [ "$pardeps $parver $parrev $paros" != "$pkgdeps $pkgver $pkgrev $pkgos" ]; then
      STATUS[$itemid]="updated"
      STATUSINFO[$itemid]="updated"
      # don't return -- it may need a rebuild (see below)
    fi
  fi

  # Has the OS changed => rebuild
  curros="${SYS_OSNAME}${SYS_OSVER}"
  if [ "$pkgos" != "$curros" ]; then
    if [ "${STATUS[$itemid]}" = 'updated' ]; then
      STATUS[$itemid]="updated+rebuild"
      STATUSINFO[$itemid]="updated + rebuild for upgraded ${SYS_OSNAME}"
    else
      STATUS[$itemid]="rebuild"
      STATUSINFO[$itemid]="rebuild for upgraded ${SYS_OSNAME}"
    fi
    return 0
  fi

  # Has the hintfile changed => rebuild
  currhnt='/'
  if [ -n "${HINTFILE[$itemdir]}" ] && [ -s "${HINTFILE[$itemdir]}" ]; then
    currhnt="$(md5sum "${HINTFILE[$itemdir]}")"; currhnt="${currhnt/ */}"
  fi
  if [ "$pkghnt" != "$currhnt" ]; then
    if [ "${STATUS[$itemid]}" = 'updated' ]; then
      STATUS[$itemid]="updated+rebuild"
      STATUSINFO[$itemid]="updated + rebuild for hintfile changes"
    else
      STATUS[$itemid]="rebuild"
      STATUSINFO[$itemid]="rebuild for hintfile changes"
    fi
    return 0
  fi

  # It seems to be up to date! although it may have been updated (see above)
  if [ "${STATUS[$itemid]}" != 'updated' ]; then
    STATUS[$itemid]="ok"
    STATUSINFO[$itemid]="ok"
  fi
  return 0

}

#-------------------------------------------------------------------------------

function write_pkg_metadata
# Update database, write changelog entries, and create metadata files in package dir
# $1 = itemid
# Return status:
# 9 = bizarre existential error, otherwise 0
{
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

  operation="$(echo "${STATUSINFO[$itemid]}" | sed -e 's/^add/Added/' -e 's/^updated + //' -e 's/^update /Updated /' -e 's/^rebuild/Rebuilt/' )"
  extrastuff=''
  if [ "${STATUSINFO[$itemid]:0:3}" = 'add' ]; then
    # append short description from slack-desc (if there's no slack-desc, this should be null)
    extrastuff="($(grep "^${pkgnam}: " "$SR_SBREPO"/"$itemdir"/slack-desc 2>/dev/null| head -n 1 | sed -e 's/.*(//' -e 's/).*//'))"
    [ "$extrastuff" = '()' ] && extrastuff=''
  fi

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
      MY_PKGCONTENTS="$MYTMP"/pkgcontents_"$pkgbasename"
      if [ ! -f "$MY_PKGCONTENTS" ]; then
        tar tvf "$pkgpath" > "$MY_PKGCONTENTS"
      fi
      cat "$MY_PKGCONTENTS" >> "$dotlst"
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
      uncsize=$(awk '{t+=int($3/1024)+1} END {print t}' "$MY_PKGCONTENTS")
      echo "PACKAGE NAME:  $pkgbasename" > "$dotmeta"
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
    [ "$OPT_KEEP_TMP" != 'y' ] && rm -f "$MY_PKGCONTENTS"

  done

  return 0
}
