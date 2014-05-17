#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# parsefunctions.sh - parse functions for slackrepo
#   parse_items
#   scan_item_dir
#   add_item_file
#   parse_package_name
#   parse_info_and_hints
#-------------------------------------------------------------------------------

declare -a ITEMLIST

function parse_items
# Parse item names
# $1 = -s => look up in SlackBuild repo, or -p => look up in Package repo
# $* = the item names to be parsed :-)
# Also uses $BLAME which the caller can set to prefix errors and warnings
#
# Return status:
# 0 = all ok
# 1 = errors logged
#
{
  local itemid
  local searchtype toplevel
  local errstat=0
  local blamemsg=''
  [ -n "$BLAME" ] && blamemsg="${BLAME}: "

  if [ "$1" = '-s' ]; then
    searchtype='-s'
    toplevel=$(realpath "$SR_SBREPO")
    shift
  elif [ "$1" = '-p' ]; then
    searchtype='-p'
    toplevel=$(realpath "$SR_PKGREPO")
    shift
  else
    # Assume it's '-s', and treat $1 as an item
    searchtype='-s'
    toplevel=$(realpath "$SR_SBREPO")
  fi

  cd "$toplevel"
  unset ITEMLIST

  while [ $# != 0 ]; do

    item=$(realpath -m "$1")
    shift

    # An item can be an absolute pathname of an object; or a relative pathname
    # of an object; or the basename of an object deep in the repo, provided that
    # there is only one object with that name.  An object can be either a directory
    # or a file.

    # Absolute path?
    if [ "${item:0:1}" = '/' ]; then
      # but is it outside the repo?
      if [ "${item:0:${#toplevel}}" = "$toplevel" ]; then
        # in the repo => make it relative
        item="${item:$(( ${#toplevel} + 1 ))}"
      else
        # not in the repo => complain
        log_error "${blamemsg}Item $item is not in $toplevel"
        errstat=1
        continue
      fi
    fi

    # Null?  Interpret that as "whatever is in the repo's root directory":
    if [ "$item" = '' ]; then
      scan_item_dir "$searchtype" .
      continue
    fi

    # Assume it's a relative path - does it exist?
    if [ -f "$item" ]; then
      add_item_file "$searchtype" "$item"
      continue
    elif [ -d "$item" ]; then
      scan_item_dir "$searchtype" "$item"
      continue
    elif [ -n "$(echo "$item" | sed 's:[^/]::g')" ]; then
      log_error "${blamemsg}Item $item not found"
      errstat=1
      continue
    fi

    # Search for anything with the right name
    gotitems=( $(find . -name "$item" -print | sed 's:^\./::') )
    if [ "${#gotitems}" = 0 ]; then
      log_error "${blamemsg}Item $item not found"
      errstat=1
      continue
    elif [ "${#gotitems[@]}" = 1 ]; then
      if [ -f "${gotitems[0]}" ]; then
        add_item_file "$searchtype" "${gotitems[0]}"
        continue
      else
        scan_item_dir "$searchtype" "${gotitems[0]}"
        continue
      fi
    else
      log_error "${blamemsg}Multiple matches for $item in $toplevel: ${gotitems[@]}"
      errstat=1
      continue
    fi

  done

  return $errstat

}

#-------------------------------------------------------------------------------

declare -A ITEMDIR ITEMFILE ITEMPRGNAM

function add_item_file
# Adds an ID for the item to the global array $ITEMLIST. The ID is a user-friendly name for the item.
#   If the item is category/prgnam/prgnam.(SlackBuild|sh), the ID will be "category/prgnam"
# Also sets the following:
# $ITEMDIR[$id] = the directory of the item relative to SR_SBREPO
# $ITEMFILE[$id] = the full basename of the file (prgnam.SlackBuild, mate-build-base.sh, etc)
# $ITEMPRGNAM[$id] = the basename of the item with .(SlackBuild|sh) removed
{
  local searchtype="$1"
  local id="$2"
  local dir=$(dirname "$id")
  local dirbase=$(basename "$dir")
  local file=$(basename "$id")
  local prgnam

  if [ "$searchtype" = '-s' ]; then
    # For SlackBuild lookups, get pkgnam from the filename:
    prgnam=$(echo "$file" | sed -r 's/\.(SlackBuild|sh)$//')
    # Simplify $id if it's unambiguous:
    [ "$prgnam" = "$dirbase" ] && id="$dir"
  else
    # For package lookups, get pkgnam from the containing directory's name:
    prgnam="$dirbase"
    # and simplify $id, just like above:
    id="$dir"
  fi
  ITEMDIR[$id]="$dir"
  ITEMFILE[$id]="$file"
  ITEMPRGNAM[$id]="$prgnam"
  ITEMLIST+=( "$id" )
  return 0
}

#-------------------------------------------------------------------------------

function scan_item_dir
{
  local searchtype="$1"
  local dir="$2"
  local dirbase
  local -a subdirlist
  dirbase=$(basename "$dir")
  if [ "$searchtype" = '-s' ]; then
    if [ -f "$dir"/"$dirbase".SlackBuild ]; then
      add_item_file "$searchtype" "$dir"/"$dirbase".SlackBuild
      return 0
    elif [ -f "$dir"/"$dirbase".sh ]; then
      add_item_file "$searchtype" "$dir"/"$dirbase".sh
      return 0
    fi
  else
    if [ -f "$dir"/.revision ]; then
      #### use a wild guess for the filename
      #### interim solution, won't work for e.g. *.sh
      add_item_file "$searchtype" "$dir"/"$dirbase".SlackBuild
      return 0
    fi
  fi
  subdirlist=( $(find "$dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort | sed 's:^\./::') )
  if [ "${#subdirlist[@]}" = 0 ]; then
    log_error "${blamemsg}${dir} contains nothing useful"
    return 0
  fi
  for subdir in "${subdirlist[@]}"; do
    scan_item_dir "$searchtype" "$subdir"
  done
  return 0
}

#-------------------------------------------------------------------------------

declare PN_PRGNAM PN_VERSION PN_ARCH PN_BUILD PN_TAG PN_PKGTYPE

function parse_package_name
# Split a package name into its component fields
# $1 = the package's pathname (or just the filename - we don't care)
# Returns global variables PN_{PRGNAM,VERSION,ARCH,BUILD,TAG,PKGTYPE}
# Return status: always 0
{
  local pkgnam=$(basename $1)
  PN_PRGNAM=$(echo $pkgnam | rev | cut -f4- -d- | rev)
  PN_VERSION=$(echo $pkgnam | rev | cut -f3 -d- | rev)
  PN_ARCH=$(echo $pkgnam | rev | cut -f2 -d- | rev)
  PN_BUILD=$(echo $pkgnam | rev | cut -f1 -d- | rev | sed 's/[^0-9]*$//')
  PN_TAG=$(echo $pkgnam | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/\..*$//')
  PN_PKGTYPE=$(echo $pkgnam | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
  return
}

#-------------------------------------------------------------------------------

# Associative arrays to store stuff from .info files:
declare -A INFOVERSION INFOREQUIRES INFODOWNLIST INFOMD5LIST
# and to store source cache and revision info:
declare -A SRCDIR GITREV GITDIRTY
# and to store hints:
declare -A \
  HINT_skipme HINT_md5ignore HINT_makej1 HINT_no_uninstall \
  HINT_cleanup HINT_uidgid HINT_answers \
  HINT_options HINT_optdeps HINT_readmedeps HINT_version \
  HINT_SUMMARY

#-------------------------------------------------------------------------------

function parse_hints_and_info
# Load up hint files into variables HINT_*, and .info file into variables INFO*
# Also populates SRCDIR, GITREV and GITDIRTY
# $1 = itemid
# Return status:
# 0 = normal
# 1 = skipme hint, or unsupported/untested in .info, or cannot determine VERSION
{

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  # HINT DEPARTMENT
  # ===============

  local -a hintlist

  if [ "${HINT_SUMMARY[$itemid]+yesitisset}" != 'yesitisset' ]; then

    FLAGHINTS="md5ignore makej1 no_uninstall"
    # These are Boolean hints.
    # HINT_xxx contains 'y' or '' ;-)
    # Query them like this: '[ "${HINT_xxx[$itemid]}" = 'y' ]'
    for hint in $FLAGHINTS; do
      if [ -f "$SR_HINTS"/"$itemdir"/"$itemprgnam"."$hint" ]; then
        eval HINT_$hint[$itemid]='y'
        hintlist+=( "$hint" )
      else
        eval HINT_$hint[$itemid]=''
      fi
    done

    FILEHINTS="skipme cleanup uidgid answers"
    # These are hints where the file contents will be used.
    # HINT_xxx contains the filename, or ''.
    # Query them like this: '[ -n "${HINT_xxx[$itemid]}" ]'
    for hint in $FILEHINTS; do
      if [ -f "$SR_HINTS"/"$itemdir"/"$itemprgnam"."$hint" ]; then
        eval HINT_$hint[$itemid]="$SR_HINTS"/"$itemdir"/"$itemprgnam"."$hint"
        hintlist+=( "$hint" )
      else
        eval HINT_$hint[$itemid]=''
      fi
    done

    VARHINTS="options version"
    # These are hints where the file contents will be used by slackrepo itself.
    # HINT_xxx contains the contents of the file, or ''.
    # Query them like this: '[ -n "${HINT_xxx[$itemid]}" ]'
    for hint in $VARHINTS; do
      if [ -f "$SR_HINTS"/"$itemdir"/"$itemprgnam"."$hint" ]; then
        eval HINT_$hint[$itemid]=\"$(cat "$SR_HINTS"/"$itemdir"/"$itemprgnam"."$hint")\"
        eval hintlist+=( "$hint=\${HINT_$hint[$itemid]}" )
      else
        eval HINT_$hint[$itemid]=''
      fi
    done

    DEPHINTS="optdeps readmedeps"
    # These are hints where the file contents will be used by slackrepo itself.
    # HINT_xxx contains the contents of the file,
    # or '%NONE%' => the file doesn't exist, or '' => the file exists and is empty.
    # Query them like this: '[ "${HINT_xxx[$itemid]}" != '%NONE%' ]'
    for hint in $DEPHINTS; do
      if [ -f "$SR_HINTS"/"$itemdir"/"$itemprgnam"."$hint" ]; then
        eval HINT_$hint[$itemid]=\"$(cat "$SR_HINTS"/"$itemdir"/"$itemprgnam"."$hint")\"
        eval hintlist+=( "$hint=\"\${HINT_$hint[$itemid]}\"" )
      else
        eval HINT_$hint[$itemid]='%NONE%'
      fi
    done

    [ ${#hintlist[@]} != 0 ] && HINT_SUMMARY["$itemid"]="$(printf '  %s\n' "${hintlist[@]}")"

  fi

  do_hint_skipme "$itemid"
  if [ $? = 0 ]; then
    if [ "$itemid" != "$ITEMID" ]; then
      log_error -n ":-( $ITEMID ABORTED"
      ABORTEDLIST+=( "$ITEMID" )
    fi
    return 1
  fi

  if [ -n "${HINT_SUMMARY[$itemid]}" ]; then
    log_normal "Hints for ${itemid}:"
    log_normal "${HINT_SUMMARY[$itemid]}"
  fi

  # INFO DEPARTMENT
  # ===============
  # It's not straightforward to tell an SBo style SlackBuild from a Slackware
  # style SlackBuild.  Some Slackware SlackBuilds have a partial or full .info,
  # but also have source (often repackaged) that clashes with DOWNLOAD=. 
  # Maybe it needs another kind of hint :-(

  if [ "${INFOVERSION[$itemid]+yesitisset}" != 'yesitisset' ]; then

    # Not from prgnam.info -- GITREV and GITDIRTY
    if [ "$GOTGIT" = 'y' ]; then
      GITREV[$itemid]="$(cd $SR_SBREPO/$itemdir; git log -n 1 --format=format:%H .)"
      GITDIRTY[$itemid]="n"
      if [ -n "$(cd $SR_SBREPO/$itemdir; git status -s .)" ]; then
        GITDIRTY[$itemid]="y"
        log_warning "${itemid}: git is dirty"
      fi
    else
      GITREV[$itemid]=''
      GITDIRTY[$itemid]="n"
    fi

    # These are the variables we need from prgnam.info:
    unset VERSION DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH} REQUIRES
    # Preferably, get them from prgnam.info:
    if [ -f "$SR_SBREPO/$itemdir/$itemprgnam.info" ]; then
      # is prgnam.info plausibly in SBo format?
      if grep -q '^VERSION=' "$SR_SBREPO/$itemdir/$itemprgnam.info" ; then
        . "$SR_SBREPO/$itemdir/$itemprgnam.info"
      fi
    fi
    # Backfill anything still unset:
    # VERSION
    if [ -z "$VERSION" ]; then
      # The next bit is necessarily dependent on the empirical characteristics of Slackware's SlackBuilds :-/
      versioncmds="$(grep -E '^(PKGNAM|SRCNAM|VERSION)=' "$SR_SBREPO"/"$itemdir"/"$itemfile")"
      cd "$SR_SBREPO/$itemdir/"
        eval $versioncmds
      cd - >/dev/null
      unset PKGNAM SRCNAM
      # increasingly desperate...
      [ -z "$VERSION" ] && VERSION="${HINT_version[$itemid]}"
      [ -z "$VERSION" ] && VERSION="${GITREV[$itemid]:0:7}"
      [ -z "$VERSION" ] && VERSION="$(date --date=@$(stat --format-='%Y' "$SR_SBREPO"/"$itemdir"/"$itemfile") '+%Y%m%d')"
    fi
    INFOVERSION[$itemid]="$VERSION"
    # DOWNLOAD[_ARCH] and MD5SUM[_ARCH]
    # Don't bother checking if they are improperly paired (it'll become apparent later).
    # If they are unset, set empty strings in INFODOWNLIST / INFOMD5LIST.
    # Also set SRCDIR (even if there is no source, SRCDIR is needed to hold .version)
    if [ -n "$(eval echo \$DOWNLOAD_$SR_ARCH)" ]; then
      INFODOWNLIST[$itemid]="$(eval echo \$DOWNLOAD_$SR_ARCH)"
      INFOMD5LIST[$itemid]="$(eval echo \$MD5SUM_$SR_ARCH)"
      SRCDIR[$itemid]="$SR_SRCREPO/$itemdir/$SR_ARCH"
    else
      INFODOWNLIST[$itemid]="${DOWNLOAD:-}"
      INFOMD5LIST[$itemid]="${MD5SUM:-}"
      SRCDIR[$itemid]="$SR_SRCREPO/$itemdir"
    fi
    # REQUIRES
    if [ "${REQUIRES+yesitisset}" != "yesitisset" ]; then
      log_normal "Dependencies of $itemid could not be determined."
    fi
    INFOREQUIRES[$itemid]="${REQUIRES:-}"

  fi

  if [ "${INFODOWNLIST[$itemid]}" = "UNSUPPORTED" -o "${INFODOWNLIST[$itemid]}" = "UNTESTED" ]; then
    log_warning -n ":-/ $itemid is ${INFODOWNLIST[$itemid]} on $SR_ARCH /-:"
    SKIPPEDLIST+=( "$itemid" )
    if [ "$itemid" != "$ITEMID" ]; then
      log_error -n ":-( $ITEMID ABORTED )-:"
      ABORTEDLIST+=( "$ITEMID" )
    fi
    return 1
  fi

  return 0

}
