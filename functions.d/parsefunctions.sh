#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# parsefunctions.sh - parse functions for slackrepo
#   parse_items
#   scan_dir
#   scan_queuefile
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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

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
    # or a file.  Queue files are special.

    # Queue file?
    if [ -f "$item" -a "${item##*.}" = 'sqf' ]; then
      scan_queuefile "$item"
      continue
    fi

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
      scan_dir "$searchtype" .
      continue
    fi

    # Assume it's a relative path - does it exist?
    if [ -f "$item" ]; then
      add_item_file "$searchtype" "$item"
      continue
    elif [ -d "$item" ]; then
      scan_dir "$searchtype" "$item"
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
        scan_dir "$searchtype" "${gotitems[0]}"
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
# Adds an item ID for the file to the global array $ITEMLIST. The ID is a
# user-friendly name for the item: if the item is cat/prg/prg.(SlackBuild|sh),
# then the ID will be shortened to "cat/prg".
# Also sets the following:
# $ITEMDIR[$id] = the directory of the item relative to SR_SBREPO
# $ITEMFILE[$id] = the full basename of the file (prgnam.SlackBuild, mate-build-base.sh, etc)
# $ITEMPRGNAM[$id] = the basename of the item with .(SlackBuild|sh) removed
# $1 = -s => look up in SlackBuild repo, or -p => look up in Package repo
# $2 = pathname (relative to the repo) of the file to add as an item
# Returns: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

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

function scan_dir
# Looks in directories (and subdirectories) for files to add.
# $1 = -s => look up in SlackBuild repo, or -p => look up in Package repo
# $2 = pathname (relative to the repo) of the directory to scan
# Returns: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

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
    scan_dir "$searchtype" "$subdir"
  done
  return 0
}

#-------------------------------------------------------------------------------

function scan_queuefile
# Scans a queuefile, adding its component items (with options and inferred deps).
# $1 = -s => look up in SlackBuild repo, or -p => look up in Package repo
# $2 = pathname (not necessarily in the repo) of the queuefile to scan
# Return status: always 0
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local sqfile="$1"

  if [ ! -f "$sqfile" ]; then
    log_warning "No such queue file: $sqfile"
    return 0
  fi

  while read sqfitem sqfoptions ; do
    case $sqfitem
    in
      @*) parse_queuefile "${sqfitem:1}.sqf"
          ;;
      -*) log_verbose "Note: ignoring unselected queuefile item ${sqfitem:1}"
          ;;
      * ) parse_items -s "$sqfitem"
          #### set deps and possibly HINT_OPTIONS
          ;;
    esac
  done < "$sqfile"
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
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
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
  HINT_SKIP HINT_MD5IGNORE HINT_NUMJOBS HINT_INSTALL HINT_ARCH \
  HINT_CLEANUP HINT_USERADD HINT_GROUPADD HINT_ANSWER HINT_NODOWNLOAD \
  HINT_OPTIONS HINT_VERSION HINT_SUMMARY HINTFILE

#-------------------------------------------------------------------------------

function parse_info_and_hints
# Load up .info file into variables INFO*, and hints into variables HINT_*
# Also populates SRCDIR, GITREV and GITDIRTY
# $1 = itemid
# Return status:
# 0 = normal
# 1 = skip/unsupported/untested, or cannot determine VERSION
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"


  # INFO DEPARTMENT
  # ===============
  # INFOVERSION[$itemid] non-null => other variables have already been set.
  #
  # If there is no proper SBo info file, we can try to discover it from the
  # SlackBuild etc, but it's tricky (e.g. Slackware info files may be SBo style,
  # or *almost* SBo style, or *not* SBo style, but often also have repackaged
  # source that doesn't match DOWNLOAD=.  If any of this breaks for a specific
  # SlackBuild, fix it with a hintfile :P

  if [ "${INFOVERSION[$itemid]+yesitisset}" != 'yesitisset' ]; then

    # Set GITREV and GITDIRTY from repo
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

    # These are the variables we want:
    local VERSION DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH} REQUIRES
    # Preferably, get them from the info file:
    if [ -f "$SR_SBREPO/$itemdir/$itemprgnam.info" ]; then
      # is prgnam.info plausibly in SBo format?
      if grep -q '^VERSION=' "$SR_SBREPO/$itemdir/$itemprgnam.info" ; then
        . "$SR_SBREPO/$itemdir/$itemprgnam.info"
      fi
    fi
    # Vape the variables we don't need:
    unset PRGNAM MAINTAINER EMAIL

    # If VERSION isn't set, snarf it from the SlackBuild:
    if [ -z "$VERSION" ]; then
      # The next bit is necessarily dependent on the empirical characteristics
      # of the SlackBuilds in Slackware, msb, csb, etc :-/
      versioncmds="$(grep -E '^(PKGNAM|SRCNAM|VERSION)=' "$SR_SBREPO"/"$itemdir"/"$itemfile")"
      # execute $versioncmds in the SlackBuild's directory so it can use the source tarball's name:
      cd "$SR_SBREPO/$itemdir/"
        eval $versioncmds
      cd - >/dev/null
      unset PKGNAM SRCNAM
    fi
    # If $VERSION is still unset, we'll deal with it after any hints have been parsed.
    INFOVERSION[$itemid]="$VERSION"
    unset VERSION

    # Process DOWNLOAD[_ARCH] and MD5SUM[_ARCH] from info file
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
    if [ -z "${INFODOWNLIST[$itemid]}" ]; then
      # Another sneaky slackbuild snarf ;-)
      # The url might contain $PRGNAM and $VERSION, or even SRCNAM :-(
      local PRGNAM SRCNAM
      eval $(grep 'PRGNAM=' "$SR_SBREPO"/"$itemdir"/"$itemfile")
      eval $(grep 'SRCNAM=' "$SR_SBREPO"/"$itemdir"/"$itemfile")
      eval INFODOWNLIST[$itemid]="$(grep 'wget -c ' "$SR_SBREPO"/"$itemdir"/"$itemfile" | sed 's/^.* //')"
      HINT_MD5IGNORE[$itemid]='y'
    fi
    unset DOWNLOAD MD5SUM
    eval unset DOWNLOAD_"$SR_ARCH" MD5SUM_"$SR_ARCH"

    # Save REQUIRES from info file (the hintfile may or may not supersede this)
    [ -v REQUIRES ] && INFOREQUIRES[$itemid]="$REQUIRES"

  fi

  # Check for unsupported/untested:
  if [ "${INFODOWNLIST[$itemid]}" = "UNSUPPORTED" -o "${INFODOWNLIST[$itemid]}" = "UNTESTED" ]; then
    log_warning -n ":-/ $itemid is ${INFODOWNLIST[$itemid]} on $SR_ARCH /-:"
    SKIPPEDLIST+=( "$itemid" )
    if [ "$itemid" != "$ITEMID" ]; then
      log_error -n ":-( $ITEMID ABORTED )-:"
      ABORTEDLIST+=( "$ITEMID" )
    fi
    return 1
  fi


  # HINT DEPARTMENT
  # ===============
  # HINTFILE[$itemid] not set => we need to check for a hintfile
  # HINTFILE[$itemid] set to null => there is no hintfile
  # HINTFILE[$itemid] non-null => other HINT_xxx variables have already been set

  if [ "${HINTFILE[$itemid]+yesitisset}" != 'yesitisset' ]; then
    hintfile=''
    hintpath=( "$SR_HINTDIR"/"$itemdir" "$SR_HINTDIR" "$SR_SBREPO"/"$itemdir" )
    for trydir in $hintpath; do
      if [ -f "$trydir"/"$itemprgnam".hint ]; then
        hintfile="$trydir"/"$itemprgnam".hint
        break
      fi
    done
    HINTFILE[$itemid]="$hintfile"
  fi

  if [ -n "${HINTFILE[$itemid]}" ]; then
    local SKIP \
          VERSION OPTIONS GROUPADD USERADD INSTALL NUMJOBS ANSWER CLEANUP \
          ARCH DOWNLOAD MD5SUM \
          REQUIRES ADDREQUIRES
    . "${HINTFILE[$itemid]}"

    # Process hint file's SKIP first.
    if [ -n "$SKIP" ]; then
      if [ "$SKIP" != 'no' ]; then
        log_warning -n ":-/ SKIPPED $itemid due to hint /-:"
        [ "$SKIP" != 'yes' ] && echo -e "$SKIP"
        SKIPPEDLIST+=( "$itemid" )
        if [ "$itemid" != "$ITEMID" ]; then
          log_error -n ":-( $ITEMID ABORTED )-:"
          ABORTEDLIST+=( "$ITEMID" )
        fi
        return 0
      fi
    fi

    # Process the hint file's variables individually (looping for each variable would need
    # 'eval', which would mess up the payload, so we don't do that).
    [ -n "$VERSION"  ] &&  HINT_VERSION[$itemid]="$VERSION"
    [ -n "$OPTIONS"  ] &&  HINT_OPTIONS[$itemid]="$OPTIONS"
    [ -n "$GROUPADD" ] && HINT_GROUPADD[$itemid]="$GROUPADD"
    [ -n "$USERADD"  ] &&  HINT_USERADD[$itemid]="$USERADD"
    [ -n "$INSTALL"  ] &&  HINT_INSTALL[$itemid]="$INSTALL"
    [ -n "$NUMJOBS"  ] &&  HINT_NUMJOBS[$itemid]="$NUMJOBS"
    [ -n "$ANSWER"   ] &&   HINT_ANSWER[$itemid]="$ANSWER"
    [ -n "$CLEANUP"  ] &&  HINT_CLEANUP[$itemid]="$CLEANUP"

    # Process hint file's ARCH, DOWNLOAD[_ARCH] and MD5SUM[_ARCH] together:
    [ -v ARCH ] && HINT_ARCH[$itemid]="$ARCH"
    if [ -n "$ARCH" ]; then
      dlvar="DOWNLOAD_$ARCH"
      [ -n "${!dlvar}" ] && DOWNLOAD="${!dlvar}"
      md5var="MD5SUM_$ARCH"
      [ -n "${!md5var}" ] && MD5SUM="${!md5var}"
    fi
    if [ "$DOWNLOAD" = 'no' ]; then
      HINT_NODOWNLOAD["$itemid"]='y'
    elif [ -n "$DOWNLOAD" ]; then
      INFODOWNLIST["$itemid"]="$DOWNLOAD"
    fi
    if [ "$MD5SUM" = 'no' ]; then
      HINT_MD5IGNORE["$itemid"]='y'
    elif [ -n "$MD5SUM" ]; then
      INFOMD5LIST["$itemid"]="$MD5SUM"
    fi

    # Fix INFOREQUIRES from hint file's REQUIRES and ADDREQUIRES
    [ "${INFOREQUIRES[$itemid]+yesitisset}" = 'yesitisset' ] && req="${INFOREQUIRES[$itemid]}"
    [ -v REQUIRES ] && req="$REQUIRES"
    [ -n "$ADDREQUIRES" ] && req=$(echo $req $ADDREQUIRES)
    if [ -v req ]; then
      INFOREQUIRES[$itemid]="$req"
    fi

    log_verbose "Hints for $itemid:"
    log_verbose ' ' ${VERSION+VERSION} \
                ${OPTIONS+OPTIONS} ${GROUPADD+GROUPADD} ${USERADD+USERADD} ${INSTALL+INSTALL} \
                ${NUMJOBS+NUMJOBS} ${ANSWER+ANSWER+} ${CLEANUP+CLEANUP} \
                ${ARCH+ARCH} ${DOWNLOAD+DOWNLOAD} ${MD5SUM+MD5SUM} \
                ${REQUIRES+REQUIRES} ${ADDREQUIRES+ADDREQUIRES}
    unset SKIP \
          VERSION OPTIONS GROUPADD USERADD INSTALL NUMJOBS ANSWER CLEANUP \
          ARCH DOWNLOAD MD5SUM \
          REQUIRES ADDREQUIRES

  fi

  # Fix INFOVERSION from hint file's VERSION, or git, or SlackBuild's modification time
  ver="${INFOVERSION[$itemid]}"
  [ -z "$ver" ] && ver="${HINT_VERSION[$itemid]}"
  [ -z "$ver" -a "$GOTGIT" = 'y' ] && ver="${GITREV[$itemid]:0:7}"
  [ -z "$ver" ] && ver="$(date --date=@$(stat --format-='%Y' "$SR_SBREPO"/"$itemdir"/"$itemfile") '+%Y%m%d')"
  INFOVERSION[$itemid]="$ver"

  # Complain and fix INFOREQUIRES if still not set
  if [ "${INFOREQUIRES[$itemid]+yesitisset}" != 'yesitisset' ]; then
    log_normal "Dependencies of $itemid could not be determined."
    INFOREQUIRES[$itemid]=""
  fi

  return 0

}

#-------------------------------------------------------------------------------

function do_hint_skipme
# Is there a skipme hint for this item?
# $1 = itemid
# Return status:
# 0 = skipped
# 1 = not skipped
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"

  # called before parse_info_and_hints runs, so check the file directly:
  hintfile="$SR_HINTDIR"/"$itemdir"/"$itemprgnam".hint
  if [ -f "$hintfile" ]; then
    if grep -q '^SKIP=' "$hintfile"; then
      eval $(grep '^SKIP=' "$hintfile")
      if [ "$SKIP" != 'no' ]; then
        log_warning -n "SKIPPED $itemid due to hint"
        [ "$SKIP" != 'yes' ] && echo "$SKIP"
        SKIPPEDLIST+=( "$itemid" )
        return 0
      fi
    fi
  fi
  return 1
}
