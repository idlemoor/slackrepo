#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# parsefunctions.sh - parse functions for slackrepo
#   parse_args
#   scan_dir
#   scan_queuefile
#   add_parsed_file
#   find_slackbuild
#   find_queuefile
#   parse_package_name
#   parse_info_and_hints
#-------------------------------------------------------------------------------

declare -a PARSEDLIST UNPARSEDLIST

function parse_args
# Parse item names
# $1 = -s => look up in SlackBuild repo, or -p => look up in Package repo
# $* = the item names to be parsed :-)
# Also uses $BLAME which the caller can set to prefix errors and warnings
# PARSEDLIST and UNPARSEDLIST must be unset before calling parse_args
#
# Results are returned in the following global arrays:
#   PARSEDLIST -- a list of item IDs that need to be processed
#   ITEMFILE -- the filename of the SlackBuild or package to be processed
#   ITEMDIR -- the path (relative to the repo root) of the directory that contains ITEMFILE
#   ITEMPRGNAM -- the prgnam of the SlackBuild or package
#   UNPARSEDLIST -- a list of newly discovered subdirectory names that need to be parsed
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

  while [ $# != 0 ]; do

    item=$(realpath -m "$1")
    shift

    # An item can be an absolute pathname of an object; or a relative pathname
    # of an object; or the basename of an object deep in the repo, provided that
    # there is only one object with that name.  An object can be either a directory
    # or a file.  Queuefiles are special.

    # Queuefile?
    if [ "${item##*.}" = 'sqf' ]; then
      find_queuefile $item
      if [ $? = 0 ]; then
        scan_queuefile "$R_QUEUEFILE"
      else
        log_warning "${itemid}: Queuefile $item not found"
      fi
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
      add_parsed_file "$searchtype" "$item"
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
    gotitems=( $(find -L . -name "$item" -print | sed 's:^\./::') )
    if [ "${#gotitems}" = 0 ]; then
      log_error "${blamemsg}Item $item not found"
      errstat=1
      continue
    elif [ "${#gotitems[@]}" = 1 ]; then
      if [ -f "${gotitems[0]}" ]; then
        add_parsed_file "$searchtype" "${gotitems[0]}"
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

function add_parsed_file
# Adds an item ID for the file to the global array $PARSEDLIST. The ID is a
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
  PARSEDLIST+=( "$id" )
  return 0
}

#-------------------------------------------------------------------------------

function find_slackbuild
# Find a SlackBuild in the repo.  Populates arrays ITEM{DIR,FILE,PRGNAM}, and
# returns the SlackBuild's itemid (key for ITEM{DIR,FILE,PRGNAM}) in $R_SLACKBUILD.
# $1 = prgnam
# Return status:
# 0 = all ok
# 1 = not found
# 2 = multiple matches
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  unset R_SLACKBUILD
  local prgnam="$1"
  local file="${prgnam}.SlackBuild"

  sblist=( $(find -L "$SR_SBREPO" -name "$file" 2>/dev/null) )
  if [ "${#sblist[@]}" = 0 ]; then
    return 1
  elif [ "${#sblist[@]}" != 1 ]; then
    return 2
  fi

  dir=$(dirname "${sblist[0]:$(( ${#SR_SBREPO} + 1 ))}")
  dirbase=$(basename "$dir")

  id="$dir"/"$file"
  [ "$prgnam" = "$dirbase" ] && id="$dir"

  ITEMDIR[$id]="$dir"
  ITEMFILE[$id]="$file"
  ITEMPRGNAM[$id]="$prgnam"
  R_SLACKBUILD="$id"
  return 0
}

#-------------------------------------------------------------------------------

function find_queuefile
# Find a queuefile.  Returns its pathname in R_QUEUEFILE.
# $1 = queuefile pathname (with or without .sqf suffix)
# Return status:
# 0 = all ok
# 1 = not found
# 2 = multiple matches
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  unset R_QUEUEFILE
  local qpath="$1"
  # try a quick win
  if [ -f "$qpath" ]; then
    R_QUEUEFILE="$qpath"
    return 0
  fi

  local -a qlist
  local qbase="$(basename $1)"
  local qfound=''
  local -a qsearch=( "$SR_QUEUEDIR" "$SR_HINTDIR" "$SR_SBREPO" )
  for trydir in $qsearch; do
    qlist=( $(find -L "$trydir" -name "$qbase" 2>/dev/null) )
    if [ "${#qlist[@]}" = 0 ]; then
      continue
    elif [ "${#qlist[@]}" = 1 ]; then
      qfound="${qlist[0]}"
      break
    else
      return 2
    fi
  done
  [ "$qfound" = '' ] && return 1
  R_QUEUEFILE="$qfound"
  return 0
}

#-------------------------------------------------------------------------------

# Queuefile processing needs a special hint to stop factorial explosion when
# enumerating the fake deps:
declare -A HINT_Q

function scan_queuefile
# Scans a queuefile, finding its slackbuilds (with options and inferred deps).
# Sets the itemid of the last slackbuild in the queue in $lastinqueuefile so
# the caller (probably scan_queuefile ;-) can use it as a dep of the next item.
# $1 = pathname of the queuefile to scan
# Return status: always 0 (any bad slackbuilds are ignored)
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2

  local sqfile="$1"
  local -a fakedeps
  local depid

  if [ ! -f "$sqfile" ]; then
    if [ -f "$SR_QUEUEDIR"/"$sqfile" ]; then
      sqfile="$SR_QUEUEDIR"/"$sqfile"
    else
      log_warning "No such queuefile: $sqfile"
      return 1
    fi
  fi

  while read sqfitem sqfoptions ; do
    case $sqfitem
    in
      @*) find_queuefile ${sqfitem:1}.sqf
          if [ $? = 0 ]; then
            scan_queuefile "$R_QUEUEFILE"
            fakedeps+=( "$lastinqueuefile" )
          else
            log_warning "${itemid}: Queuefile ${sqfitem:1}.sqf not found"
          fi
          ;;
      -*) log_verbose "Note: ignoring unselected queuefile item ${sqfitem:1}"
          ;;
      * ) find_slackbuild "$sqfitem"
          fstat=$?
          if [ $fstat = 0 ]; then
            PARSEDLIST+=( "$R_SLACKBUILD" )
            HINT_Q["$R_SLACKBUILD"]="$queuefile"
            # add sqfitem to fakedeps *after* adding fakedeps to INFOREQUIRES
            # so that sqfitem won't depend on itself
            INFOREQUIRES["$R_SLACKBUILD"]="${fakedeps[@]}"
            fakedeps+=( "$sqfitem" )
          elif [ $fstat = 1 ]; then
            log_warning "${itemid}: Queuefile dep $sqfitem not found"
          elif [ $fstat = 2 ]; then
            log_warning "${itemid}: Queuefile dep $sqfitem matches more than one SlackBuild"
          fi
          if [ -n "$sqfoptions" ]; then
            HINT_OPTIONS["$R_SLACKBUILD"]="$(echo "$sqfoptions" | sed 's/^ *| *//')"
          fi
          ;;
    esac
  done < "$sqfile"
  lastinqueuefile="$sqfitem"
  return 0
}

#-------------------------------------------------------------------------------

function scan_dir
# Looks in directories for files or subdirectories.
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
      add_parsed_file "$searchtype" "$dir"/"$dirbase".SlackBuild
      return 0
    fi
  else
    if [ -f "$dir"/.revision ]; then
      #### use a wild guess for the filename
      #### interim solution, won't work for e.g. *.sh
      add_parsed_file "$searchtype" "$dir"/"$dirbase".SlackBuild
      return 0
    fi
  fi
  # Descend one level only - some SlackBuilds have subdirectories
  # (eg. for patches) that need to be ignored
  subdirlist=( $(find -L "$dir" -mindepth 1 -maxdepth 1 -type d -not -name '.*' | sort | sed 's:^\./::') )
  if [ "${#subdirlist[@]}" = 0 ]; then
    log_normal "${blamemsg}${dir} does not contain a SlackBuild"
    return 0
  fi
  # don't recurse (which would take a long time), just return the list of subdirectories
  # (the main loop will parse and process them after it has processed the parsed items)
  UNPARSEDLIST+=( "${subdirlist[@]}" )
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
  HINT_SKIP HINT_MD5IGNORE HINT_NUMJOBS HINT_INSTALL HINT_SPECIAL HINT_ARCH \
  HINT_CLEANUP HINT_USERADD HINT_GROUPADD HINT_ANSWER HINT_NODOWNLOAD \
  HINT_PREREMOVE HINT_CONFLICTS \
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
    # Save $VERSION.
    # If it is '*', this is a Slackware SlackBuild that gets the version from the
    # source tarball name, but there is no source tarball present.  Set it null.
    [ "$VERSION" = '*' ] && VERSION=''
    # If it is null, the Fixup department below will invent something.
    INFOVERSION[$itemid]="$VERSION"
    # but don't unset $VERSION yet, it'll be needed when we snarf from the SlackBuild below

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
      # Lots of SlackBuilds use 'wget -c' to download the source.
      # But the url(s) might contain $PRGNAM and $VERSION, or even $SRCNAM,
      # and might be on continuation lines.
      local PRGNAM SRCNAM
      eval $(grep 'PRGNAM=' "$SR_SBREPO"/"$itemdir"/"$itemfile")
      eval $(grep 'SRCNAM=' "$SR_SBREPO"/"$itemdir"/"$itemfile")
      eval INFODOWNLIST["$itemid"]="$(sed ':x; /\\$/ { N; s/\\\n//; tx }' <"$SR_SBREPO"/"$itemdir"/"$itemfile" | grep 'wget -c ' | sed 's/wget -c //')"
      HINT_MD5IGNORE["$itemid"]='y'
    fi
    unset DOWNLOAD MD5SUM PRGNAM SRCNAM VERSION
    eval unset DOWNLOAD_"$SR_ARCH" MD5SUM_"$SR_ARCH"

    # Conditionally save REQUIRES from info file into INFOREQUIRES
    # (which will be processed in the Fixup department below).
    [ -v REQUIRES ] && INFOREQUIRES[$itemid]="$REQUIRES"
    unset REQUIRES

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
    hintsearch=( "$SR_SBREPO"/"$itemdir" "$SR_HINTDIR" "$SR_HINTDIR"/"$itemdir" )
    for trydir in "${hintsearch[@]}"; do
      if [ -f "$trydir"/"$itemprgnam".hint ]; then
        hintfile="$trydir"/"$itemprgnam".hint
        break
      fi
    done
    HINTFILE[$itemid]="$hintfile"
  fi

  if [ -n "${HINTFILE[$itemid]}" ]; then
    local SKIP \
          VERSION ADDREQUIRES OPTIONS GROUPADD USERADD PREREMOVE CONFLICTS INSTALL NUMJOBS ANSWER CLEANUP \
          SPECIAL ARCH DOWNLOAD MD5SUM
    . "${HINTFILE[$itemid]}"

    # Process hint file's SKIP first.
    if [ -n "$SKIP" ]; then
      if [ "$SKIP" != 'no' ]; then
        log_warning -n ":-/ $itemid SKIPPED due to hint /-:"
        [ "$SKIP" != 'yes' ] && echo -e "$SKIP"
        SKIPPEDLIST+=( "$itemid" )
        if [ "$itemid" != "$ITEMID" ]; then
          log_error -n ":-( $ITEMID ABORTED )-:"
          ABORTEDLIST+=( "$ITEMID" )
        fi
        return 1
      fi
    fi

    # Process the hint file's variables individually (looping for each variable would need
    # 'eval', which would mess up the payload, so we don't do that).
    [ -n "$OPTIONS"   ] &&   HINT_OPTIONS[$itemid]="$OPTIONS"
    [ -n "$GROUPADD"  ] &&  HINT_GROUPADD[$itemid]="$GROUPADD"
    [ -n "$USERADD"   ] &&   HINT_USERADD[$itemid]="$USERADD"
    [ -n "$PREREMOVE" ] && HINT_PREREMOVE[$itemid]="$PREREMOVE"
    [ -n "$CONFLICTS" ] && HINT_CONFLICTS[$itemid]="$CONFLICTS"
    [ -n "$NUMJOBS"   ] &&   HINT_NUMJOBS[$itemid]="$NUMJOBS"
    [ -n "$ANSWER"    ] &&    HINT_ANSWER[$itemid]="$ANSWER"
    [ -n "$CLEANUP"   ] &&   HINT_CLEANUP[$itemid]="$CLEANUP"
    [ -n "$SPECIAL"   ] &&   HINT_SPECIAL[$itemid]="$SPECIAL"

    # Process hint file's INSTALL
    if [ -n "$INSTALL" ]; then
      HINT_INSTALL[$itemid]="y"
      [ "${INSTALL:0:1}" = 'Y' -o "${INSTALL:0:1}" = '1' ] && HINT_INSTALL[$itemid]="y"
      [ "${INSTALL:0:1}" = 'N' -o "${INSTALL:0:1}" = 'n' -o "${INSTALL:0:1}" = '0' ] && HINT_INSTALL[$itemid]="n"
    fi

    # Process hint file's VERSION, ARCH, DOWNLOAD[_ARCH] and MD5SUM[_ARCH] together:
    if [ -n "$ARCH" ]; then
      dlvar="DOWNLOAD_$ARCH"
      [ -n "${!dlvar}" ] && DOWNLOAD="${!dlvar}"
      md5var="MD5SUM_$ARCH"
      [ -n "${!md5var}" ] && MD5SUM="${!md5var}"
    fi
    if [ -n "$VERSION" ]; then
      HINT_VERSION[$itemid]="$VERSION"
      [ -z "$MD5SUM" ] && MD5SUM='no'
    fi
    [ -v ARCH ] && HINT_ARCH[$itemid]="$ARCH"
    if [ "$DOWNLOAD" = 'no' ]; then
      HINT_NODOWNLOAD["$itemid"]='y'
    elif [ -n "$DOWNLOAD" ]; then
      INFODOWNLIST["$itemid"]="$DOWNLOAD"
    fi
    if [ "$MD5SUM" = 'no' ]; then
      HINT_MD5IGNORE["$itemid"]='y'
    elif [ -n "$MD5SUM" ]; then
      INFOMD5LIST["$itemid"]="$MD5SUM"
      HINT_MD5IGNORE["$itemid"]=''
    fi

    # Process ADDREQUIRES in the Fixup department below.

    log_verbose "Hints for $itemid:"
    log_verbose "$(printf '  %s\n' \
      ${VERSION+"VERSION=\"$VERSION\""} \
      ${OPTIONS+"OPTIONS=\"$OPTIONS\""} \
      ${GROUPADD+"GROUPADD=\"$GROUPADD\""} \
      ${USERADD+"USERADD=\"$USERADD\""} \
      ${PREREMOVE+"PREREMOVE=\"$PREREMOVE\""} \
      ${CONFLICTS+"CONFLICTS=\"$CONFLICTS\""} \
      ${INSTALL+"INSTALL=\"$INSTALL\""} \
      ${NUMJOBS+"NUMJOBS=\"$NUMJOBS\""} \
      ${ANSWER+"ANSWER=\"$ANSWER\""} \
      ${CLEANUP+"CLEANUP=\"$CLEANUP\""} \
      ${SPECIAL+"SPECIAL=\"$SPECIAL\""} \
      ${ARCH+"ARCH=\"$ARCH\""} \
      ${DOWNLOAD+"DOWNLOAD=\"$DOWNLOAD\""} \
      ${MD5SUM+"MD5SUM=\"$MD5SUM\""} \
      ${ADDREQUIRES+"ADDREQUIRES=\"$ADDREQUIRES\""} )"
    unset SKIP \
          VERSION OPTIONS GROUPADD USERADD \
          PREREMOVE CONFLICTS \
          INSTALL NUMJOBS ANSWER CLEANUP \
          SPECIAL ARCH DOWNLOAD MD5SUM

  fi

  # FIXUP DEPARTMENT
  # ================

  # Fix INFOREQUIRES from ADDREQUIRES, if possible
  if [ "${INFOREQUIRES[$itemid]+yesitisset}" != 'yesitisset' ]; then
    if [ -v ADDREQUIRES ]; then
      INFOREQUIRES[$itemid]="$ADDREQUIRES"
    else
      log_normal "Dependencies of $itemid can not be determined."
      INFOREQUIRES[$itemid]=""
    fi
  else
    if [ -v ADDREQUIRES ]; then
      # This gets rid of %README% if and only if ADDREQUIRES is set.
      INFOREQUIRES[$itemid]="$(echo ${INFOREQUIRES[$itemid]} $ADDREQUIRES | sed -e 's/%README%//')"
      # Else %README% will remain, and calculate_deps will issue a warning.
    fi
  fi

  # Fix INFOVERSION from hint file's VERSION, or DOWNLOAD, or git, or SlackBuild's modification time
  ver="${INFOVERSION[$itemid]}"
  [ -z "$ver" ] && ver="${HINT_VERSION[$itemid]}"
  [ -z "$ver" ] && ver="$(basename $(echo "${INFODOWNLIST[$itemid]}" | sed 's/ .*//') 2>/dev/null | rev | cut -f 3- -d . | cut -f 1 -d - | rev)"
  [ -z "$ver" ] && log_normal "Version of $itemid can not be determined."
  [ -z "$ver" -a "$GOTGIT" = 'y' ] && ver="${GITREV[$itemid]:0:7}"
  [ -z "$ver" ] && ver="$(date --date=@$(stat --format='%Y' "$SR_SBREPO"/"$itemdir"/"$itemfile") '+%Y%m%d')"
  INFOVERSION[$itemid]="$ver"

  return 0

}
