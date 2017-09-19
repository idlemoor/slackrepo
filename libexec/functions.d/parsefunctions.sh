#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# parsefunctions.sh - parse functions for slackrepo
#   parse_arg
#   find_items
#   parse_package_name
#   parse_info_and_hints
#-------------------------------------------------------------------------------

declare -a PARSEDARGS
declare -A ITEMDIR ITEMFILE ITEMPRGNAM PRGNAMITEMID

#-------------------------------------------------------------------------------

declare -a R_ITEMLIST

function parse_arg
# Parse an argument into a list of item names.
# The item names returned depend on which command is running
# (e.g. the revert command will look for items that have backups).
# $1 = the argument to be parsed, shell-style globs are supported
# $2 = if looking up a dependency, the itemid we are processing, otherwise null
# Results are returned in this global array:
#   PARSEDARGS -- a list of item IDs that need to be processed
# Return status: always 0 -- if $1 is 100% rubbish, PARSEDARGS will be empty
{
  local firstarg="$1"
  local callerid="$2"
  local -a objlist dependers
  local newitemid prgnam
  PARSEDARGS=()

  # Although we only accept one arg, some args can expand (e.g. requires::arg)
  set -- "$firstarg"

  while [ $# != 0 ]; do
    arg="${1%%/}"
    shift

    # Shortcuts:
    if [ -n "${ITEMPRGNAM[$arg]}" ]; then
      # it's an already-valid itemid
      PARSEDARGS+=( "$arg" )
      continue
    elif [ -n "${PRGNAMITEMID[$arg]}" ]; then
      # it's an already-valid prgnam
      PARSEDARGS+=( "${PRGNAMITEMID[$arg]}" )
      continue
    fi

    # Special processing:
    case "$arg" in
    *::* )
      prefix="${arg%::*}"
      suffix="${arg#*::}"
      case "$prefix" in
        'requires' )
          if [ -n "$callerid" ]; then
            log_warning -a "${callerid}: ignored ${prefix}::${suffix} (invalid in a dependency list)"
          else
            #### this is experimental!
            readarray -t dependers < <(db_get_dependers "${suffix}")
            [ "${#dependers}" != 0 ] && set -- "$@" "${dependers[@]}"
          fi
          ;;
        * )
          # cross-repo support coming soon :D
          if [ -n "$callerid" ]; then
            log_warning -a "${callerid}: ignored ${prefix}::${suffix} (not yet implemented)"
          else
            log_start "$arg"; log_itemfinish "${prefix}::${suffix}" "bad" "" "Not yet implemented"
          fi
          ;;
      esac
      continue
      ;;
    esac

    case "$CMD" in
    'build' | 'rebuild' )
      find_items "$arg" -s
      ;;
    'update' | 'lint' )
      if [ -n "$callerid" ] || [ "$CMD" = 'lint' ]; then
        # update: deps can be unbuilt, so we need to search both repos
        # lint: happy to process whatever actually exists
        find_items "$arg" -ps
      else
        find_items "$arg" -p
      fi
      ;;
    'remove' )
      find_items "$arg" -p
      ;;
    'revert' )
      find_items "$arg" -b
      ;;
    * )
      find_items "$arg" -s
      ;;
    esac

    if [ -n "$callerid" ] && [ "${#R_ITEMLIST[@]}" = 0 ]; then
      # nothing in the repo :-/
      # if we need a dep, look for an installed package (poss from another repo)
      guesspkgnam="$(basename "${arg/.*/}")"
      is_installed "${guesspkgnam}-v-a-bt"
      iistat=$?
      if [ $iistat = 0 ] || [ $iistat = 1 ]; then
        log_warning -s -a "${callerid}: Found installed package ${R_INSTALLED} for ${arg} (not in repo)"
        continue
      else
        log_warning -s -a "${callerid}: Dependency ${arg} does not exist and has been ignored"
      fi
    fi

    PARSEDARGS+=( "${R_ITEMLIST[@]}" )

  done

  if [ -z "$callerid" ] && [ "${#PARSEDARGS[@]}" = 0 ]; then
    log_start "$firstarg"; log_itemfinish "$firstarg" "bad" "" "No matches found for $CMD command"
  fi

  return 0
}

#-------------------------------------------------------------------------------

function find_items
# Print a newline-separated list on standard output of itemids that match a glob
# $1 = glob
# $2 = where to find the items
#       -s = SlackBuild repo
#       -p = package database
#       -b = backup repo
#       -ps = package database with fallback to SlackBuild repo
# Also needs to inherit $callerid from parse_arg
#
# Populates arrays ITEMPRGNAM, PRGNAMITEMID, ITEMDIR, ITEMFILE
# and returns the itemids (key for ITEM{DIR,FILE,PRGNAM}) in $R_ITEMLIST.
#   ITEMPRGNAM -- the prgnam of the SlackBuild or package
#   PRGNAMITEMID -- the itemid of the prgnam
#   ITEMDIR -- the path (relative to the repo root) of the directory that contains ITEMFILE
#  and if the SlackBuild exists (note, for update/remove/revert/lint it might not exist)
#   ITEMFILE -- the filename of the SlackBuild to be processed
#
# By the way, we'll try not to barf when paths have embedded spaces, but if you're
# gormless enough to have paths with embedded newlines you can sod off right now.
# Return status: always 0
{
  local glob="$1"
  local lookuptype="$2"
  local -a objlist dirlist
  local object filenam prgnam dirnam dirbase newitemid

  R_ITEMLIST=()

  if [ "$lookuptype" = "-p" ] || [ "$lookuptype" = "-ps" ]; then
    readarray -t objlist < <(db_get_itemids "$glob")
    if [ "$lookuptype" = "-ps" ] && [ "${#objlist[@]}" = 0 ]; then
      # hey, I wonder how we can lookup the SlackBuilds?
      find_items "${glob}" -s
      return 0
      # :D
    fi

  elif [ "$lookuptype" = "-s" ]; then
    readarray -t objlist < <(db_get_slackbuilds "$glob")
    if [ "${#objlist[@]}" = 0 ]; then
      # maybe it's a script name e.g. <thing>.sh
      : #### we'll implement that later ;-)
    fi

  elif [ "$lookuptype" = '-b' ]; then
    # Performance isn't really important for 'revert', so let's do it the slow way.
    case "$glob" in
      *.t?z )
        # explicit filename, including wildcards
        readarray -t objlist < <(cd "$SR_PKGBACKUP"; find -L . -type f -path "*/${glob}" | sort)
        ;;
      * )
        readarray -t objlist < <(cd "$SR_PKGBACKUP"; find -L . -type f -path "*/${glob}.t?z" | sort)
        # found nothing?  assume it's a directory name and look inside:
        if [ "${#objlist[@]}" = 0 ]; then
          readarray -t dirlist < <(cd "$SR_PKGBACKUP"; find -L . -type d -path "*/${glob}" | sort)
          [ "${#dirlist[@]}" != 0 ] && readarray -t objlist < <(cd "$SR_PKGBACKUP"; find -L "${dirlist[@]}" -type f -name "*.t?z" | sort)
        fi
        ;;
    esac

  fi

  for object in "${objlist[@]}"; do
    if [ "$lookuptype" = '-b' ]; then
      newitemid=$(dirname "${object#./}")
      prgnam=$(basename "$newitemid")
      dirnam="$newitemid"
      filenam=""
    elif [ "$lookuptype" = '-p' ] || [ "$lookuptype" = '-ps' ]; then
      newitemid="${object}"
      prgnam=$(basename "$newitemid")
      dirnam="$newitemid"
      filenam=""
      [ -f "$SR_SBREPO/${dirnam}/${prgnam}.SlackBuild" ] && filenam="${prgnam}.SlackBuild"
      [ -f "$SR_SBREPO/${dirnam}/${prgnam}" ] && filenam="${prgnam}"
    else # "$lookuptype" = '-s'
      filenam=$(basename "${object}")
      prgnam="${filenam%.SlackBuild}"
      dirnam=$(dirname "${object#./}")
      [ -z "$dirnam" ] && dirnam="."  #### needs to support slackbuild in repo's root dir
      dirbase=$(basename "$dirnam")
      newitemid="$dirnam/$filenam"
      [ "$prgnam" = "$dirbase" ] && newitemid="$dirnam"
    fi
    ITEMPRGNAM[$newitemid]="$prgnam"
    PRGNAMITEMID[$prgnam]="$newitemid"
    ITEMDIR[$newitemid]="$dirnam"
    [ -n "$filenam" ] && ITEMFILE[$newitemid]="$filenam"
    R_ITEMLIST+=( "$newitemid" )
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
  local pkgnam=$(basename "$1")
  PN_PRGNAM=$(echo "$pkgnam" | rev | cut -f4- -d- | rev)
  PN_VERSION=$(echo "$pkgnam" | rev | cut -f3 -d- | rev)
  PN_ARCH=$(echo "$pkgnam" | rev | cut -f2 -d- | rev)
  PN_BUILD=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^\([[:digit:]][[:digit:]]*\).*$/\1/')
  PN_TAG=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[[:digit:]][[:digit:]]*\(.*\)$/\1/' | rev | sed 's/^[^\.]*\.//' | rev)
  PN_PKGTYPE=$(echo "$pkgnam" | rev | cut -f1 -d- | rev | sed 's/^[0-9]*//' | sed 's/^.*\.//')
  return 0
}

#-------------------------------------------------------------------------------

# Associative arrays to store stuff from .info files:
declare -A INFOVERSION INFOREQUIRES INFODOWNLIST INFOMD5LIST INFOSHA256LIST
# and to store source cache and git revision info:
declare -A SRCDIR GITREV GITDIRTY
# and to store hints:
declare -A \
  HINT_MD5IGNORE HINT_SHA256IGNORE HINT_NUMJOBS HINT_INSTALL HINT_PRAGMA \
  HINT_ARCH HINT_CLEANUP HINT_USERADD HINT_GROUPADD HINT_ANSWER HINT_NODOWNLOAD \
  HINT_CONFLICTS HINT_BUILDTIME HINT_NOWARNING \
  HINT_OPTIONS HINT_VERSION HINT_KERNEL HINTFILE
# and for validation in test_*
declare -A VALID_USERS VALID_GROUPS

#-------------------------------------------------------------------------------

function parse_info_and_hints
# Load up .info file into variables INFO*, and hints into variables HINT_*
# Also populates SRCDIR, GITREV and GITDIRTY
# $1 = itemid
# Return status:
# 0 = normal
# 1 = skipped/unsupported/untested
# 2 = no files (probably pending removal)
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  if [ -z "${ITEMFILE[$itemid]}" ]; then
    return 1
  fi

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
      GITREV[$itemid]="$(cd "$SR_SBREPO"/"$itemdir"; git log -n 1 --format=format:%H .)"
      GITDIRTY[$itemid]="n"
      if [ -n "$(cd "$SR_SBREPO"/"$itemdir"; git status -s .)" ]; then
        GITDIRTY[$itemid]="y"
        log_warning -s "${itemid}: git is dirty"
      fi
    else
      GITREV[$itemid]=''
      GITDIRTY[$itemid]="n"
    fi

    # These are the variables we want:
    local VERSION DOWNLOAD DOWNLOAD_${SR_ARCH} REQUIRES
    local MD5SUM MD5SUM_${SR_ARCH} SHA256SUM SHA256SUM_${SR_ARCH}
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
    local versioncmds prevdir
    if [ -z "$VERSION" ]; then
      # The next bit is necessarily dependent on the empirical characteristics
      # of the SlackBuilds in Slackware, msb, csb, etc :-/
      versioncmds="$(grep -E '^(PKGNAM|SRCNAM|VERSION)=' "$SR_SBREPO"/"$itemdir"/"$itemfile")"
      # execute $versioncmds in the SlackBuild's directory so it can use the source tarball's name:
      prevdir=$(pwd)
      cd "$SR_SBREPO"/"$itemdir"/ && eval "$versioncmds"
      unset PKGNAM SRCNAM
      cd "$prevdir"
    fi
    # Save $VERSION.
    # If it is '*', this is a Slackware SlackBuild that gets the version from the
    # source tarball name, but there is no source tarball present.  Set it null.
    [ "$VERSION" = '*' ] && VERSION=''
    # If it is null, the Fixup department below will invent something.
    # Canonicalise any silly spaces with an 'echo'.
    INFOVERSION[$itemid]="$(echo $VERSION)"
    # but don't unset $VERSION yet, it'll be needed when we snarf from the SlackBuild below.

    # Process DOWNLOAD[_ARCH] and MD5SUM[_ARCH]/SHA256SUM[_ARCH] from info file
    # Don't bother checking if they are improperly paired (it'll become apparent later).
    # If they are unset, set empty strings in INFODOWNLIST / INFOMD5LIST / INFOSHA256LIST.
    # Also set SRCDIR (even if there is no source, SRCDIR is needed to hold .version)
    if [ -n "$(eval echo \$DOWNLOAD_"$SR_ARCH")" ]; then
      INFODOWNLIST[$itemid]="$(eval echo \$DOWNLOAD_"$SR_ARCH")"
      INFOMD5LIST[$itemid]="$(eval echo \$MD5SUM_"$SR_ARCH")"
      INFOSHA256LIST[$itemid]="$(eval echo \$SHA256SUM_"$SR_ARCH")"
      SRCDIR[$itemid]="$SR_SRCREPO"/"$itemdir"/"$SR_ARCH"
    else
      INFODOWNLIST[$itemid]="${DOWNLOAD:-}"
      INFOMD5LIST[$itemid]="${MD5SUM:-}"
      INFOSHA256LIST[$itemid]="${SHA256SUM:-}"
      SRCDIR[$itemid]="$SR_SRCREPO"/"$itemdir"
    fi
    if [ -z "${INFODOWNLIST[$itemid]}" ]; then
      # Another sneaky slackbuild snarf ;-)
      # Lots of SlackBuilds use 'wget -c' to download the source.
      # But the url(s) might contain $PRGNAM and $VERSION, or $SRCNAM, or $COMMITVER,
      # and might be on continuation lines.
      local PRGNAM SRCNAM COMMITVER
      eval "$(grep 'PRGNAM=' "$SR_SBREPO"/"$itemdir"/"$itemfile")"
      eval "$(grep 'SRCNAM=' "$SR_SBREPO"/"$itemdir"/"$itemfile")"
      eval "$(grep 'COMMITVER=' "$SR_SBREPO"/"$itemdir"/"$itemfile")"
      eval "INFODOWNLIST[$itemid]=\"$(sed ':x; /\\$/ { N; s/\\\n//; tx }' <"$SR_SBREPO"/"$itemdir"/"$itemfile" | grep 'wget  *-c  *' | sed 's/wget  *-c  *//')\""
      #### Ideally if this sneaky download failed we would run the whole SlackBuild anyway...
      HINT_MD5IGNORE[$itemid]='y'
      HINT_SHA256IGNORE[$itemid]='y'
    fi
    unset DOWNLOAD MD5SUM SHA256SUM PRGNAM SRCNAM VERSION
    eval unset DOWNLOAD_"$SR_ARCH" MD5SUM_"$SR_ARCH" SHA256SUM_"$SR_ARCH"

    # Conditionally save REQUIRES from info file into INFOREQUIRES
    # (which will be processed in the Fixup department below).
    # Canonicalise any silly spaces with an 'echo'.
    [ -v REQUIRES ] && INFOREQUIRES[$itemid]="$(echo $REQUIRES)"
    unset REQUIRES

  fi

  # Check for unsupported/untested:
  if [ "${INFODOWNLIST[$itemid]}" = "UNSUPPORTED" ] || [ "${INFODOWNLIST[$itemid]}" = "UNTESTED" ]; then
    STATUS[$itemid]="unsupported"
    STATUSINFO[$itemid]="${INFODOWNLIST[$itemid]} on $SR_ARCH"
    return 1
  fi


  # HINT DEPARTMENT
  # ===============
  # HINTFILE[$itemid] not set => we need to check for a hintfile
  # HINTFILE[$itemid] set to null => there is no hintfile
  # HINTFILE[$itemid] non-null => other HINT_xxx variables have already been set
  local hintfile hintsearch trydir

  if [ "${HINTFILE[$itemid]+yesitisset}" != 'yesitisset' ]; then
    hintfile=''
    hintsearch=( "$SR_SBREPO"/"$itemdir" "$SR_HINTDIR" "$SR_HINTDIR"/"$itemdir" )
    [ -n "$SR_DEFAULT_HINTDIR" ] && hintsearch+=( "$SR_DEFAULT_HINTDIR" "$SR_DEFAULT_HINTDIR"/"$itemdir" )
    for trydir in "${hintsearch[@]}"; do
      if [ -f "$trydir"/"$itemprgnam".hint ]; then
        hintfile="$trydir"/"$itemprgnam".hint
        break
      fi
    done
    HINTFILE[$itemid]="$hintfile"
  fi

  if [ -n "${HINTFILE[$itemid]}" ] && [ -s "${HINTFILE[$itemid]}" ]; then
    local SKIP \
          VERSION OPTIONS GROUPADD USERADD NOWARNING NOWARNINGS \
          ADDREQUIRES DELREQUIRES BUILDTIME CONFLICTS \
          INSTALL NUMJOBS ANSWER CLEANUP PRAGMA SPECIAL ARCH DOWNLOAD MD5SUM SHA256SUM
    . "${HINTFILE[$itemid]}"

    # Process the hint file's variables individually (looping for each variable would need
    # 'eval', which would mess up the payload, so we don't do that).
    [ -n "$OPTIONS"   ] &&   HINT_OPTIONS[$itemid]="$OPTIONS"
    [ -n "$BUILDTIME" ] && HINT_BUILDTIME[$itemid]="$BUILDTIME"
    [ -n "$CONFLICTS" ] && HINT_CONFLICTS[$itemid]="$CONFLICTS"
    [ -n "$NUMJOBS"   ] &&   HINT_NUMJOBS[$itemid]="$NUMJOBS"
    [ -n "$ANSWER"    ] &&    HINT_ANSWER[$itemid]="$ANSWER"
    [ -n "$CLEANUP"   ] &&   HINT_CLEANUP[$itemid]="$CLEANUP"
    [ -n "$PRAGMA"    ] &&    HINT_PRAGMA[$itemid]="$PRAGMA"
   [ -n "$NOWARNINGS" ] && HINT_NOWARNING[$itemid]="$NOWARNINGS"
    [ -n "$NOWARNING" ] && HINT_NOWARNING[$itemid]="$NOWARNING"
    [ -n "$SPECIAL"   ] &&    HINT_PRAGMA[$itemid]="$SPECIAL"

    # Process hint file's INSTALL
    if [ -n "$INSTALL" ]; then
      HINT_INSTALL[$itemid]="y"
      [ "${INSTALL:0:1}" = 'Y' -o "${INSTALL:0:1}" = '1' ] && HINT_INSTALL[$itemid]="y"
      [ "${INSTALL:0:1}" = 'N' -o "${INSTALL:0:1}" = 'n' -o "${INSTALL:0:1}" = '0' ] && HINT_INSTALL[$itemid]="n"
    fi

    # Process hint file's VERSION, ARCH, DOWNLOAD[_ARCH] and [MD5|SHA256]SUM[_ARCH] together:
    local dlvar md5var sha256var
    if [ -n "$ARCH" ]; then
      dlvar="DOWNLOAD_$ARCH"
      [ -n "${!dlvar}" ] && DOWNLOAD="${!dlvar}"
      md5var="MD5SUM_$ARCH"
      [ -n "${!md5var}" ] && MD5SUM="${!md5var}"
      sha256var="SHA256SUM_$ARCH"
      [ -n "${!sha256var}" ] && SHA256SUM="${!sha256var}"
    fi
    if [ -n "$VERSION" ]; then
      HINT_VERSION[$itemid]="$VERSION"
      [ -z "$MD5SUM" ] && MD5SUM='no'
      [ -z "$SHA256SUM" ] && SHA256SUM='no'
    fi
    [ -v ARCH ] && HINT_ARCH[$itemid]="$ARCH"
    if [ "$DOWNLOAD" = 'no' ]; then
      HINT_NODOWNLOAD[$itemid]='y'
    elif [ -n "$DOWNLOAD" ]; then
      INFODOWNLIST[$itemid]="$DOWNLOAD"
    fi
    if [ "$MD5SUM" = 'no' ]; then
      HINT_MD5IGNORE[$itemid]='y'
    elif [ -n "$MD5SUM" ]; then
      INFOMD5LIST[$itemid]="$MD5SUM"
      HINT_MD5IGNORE[$itemid]=''
    fi
    if [ "$SHA256SUM" = 'no' ]; then
      HINT_SHA256IGNORE[$itemid]='y'
    elif [ -n "$SHA256SUM" ]; then
      INFOSHA256LIST[$itemid]="$SHA256SUM"
      HINT_SHA256IGNORE[$itemid]=''
    fi

    # Process hint file's GROUPADD and USERADD together:
    # GROUPADD hint format: GROUPADD="<gnum>:<gname> ..."
    # USERADD hint format:  USERADD="<unum>:<uname>:[-g<ugroup>:][-d<udir>:][-s<ushell>:][-uargs:...] ..."
    # VALID_GROUPS and VALID_USERS are needed for test_package
    if [ -n "${GROUPADD}" ]; then
      local groupstring gnum gname
      for groupstring in $GROUPADD; do
        gnum=''; gname="$itemprgnam"
        for gfield in $(echo "$groupstring" | tr ':' ' '); do
          case "$gfield" in
            [0-9]* ) gnum="$gfield" ;;
            * ) gname="$gfield" ;;
          esac
        done
        [ -z "$gnum" ] && { log_warning -n "${itemid}: GROUPADD hint has no GID number" ; break ; }
        if ! getent group "$gname" | grep -q "^${gname}:" 2>/dev/null ; then
          HINT_GROUPADD[$itemid]="${HINT_GROUPADD[$itemid]}groupadd -g $gnum $gname; "
        else
          log_info -a "Group $gname already exists."
        fi
        if [ -z "${VALID_GROUPS[$itemid]}" ]; then
          VALID_GROUPS[$itemid]="$gnum|$gname"
        else
          VALID_GROUPS[$itemid]="${VALID_GROUPS[$itemid]}|$gnum|$gname"
        fi
      done
    fi
    if [ -n "$USERADD" ]; then
      local userstring unum uname udir ufield ugroup ushell uargs
      for userstring in $USERADD; do
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
        [ -z "$unum" ] && { log_warning -n "${itemid}: USERADD hint has no UID number" ; break ; }
        if ! getent passwd "$uname" | grep -q "^${uname}:" 2>/dev/null ; then
          [ -z "$ugroup" ] && ugroup="$uname"
          HINT_USERADD[$itemid]="${HINT_USERADD[$itemid]}useradd  -u $unum -g $ugroup -c $itemprgnam -d $udir -s $ushell $uargs $uname; "
        else
          log_info -a "User $uname already exists."
        fi
        if [ -z "${VALID_USERS[$itemid]}" ]; then
          VALID_USERS[$itemid]="$unum|$uname"
        else
          VALID_USERS[$itemid]="${VALID_USERS[$itemid]}|$unum|$uname"
        fi
      done
    fi

    # Process SKIP and ADDREQUIRES in the Fixup department below.
    local briefskip
    briefskip="${SKIP:0:20}"
    [ "${#SKIP}" -gt 20 ] && briefskip="${SKIP:0:17}..."

    log_info "Hints for $itemid:"
    log_info "$(printf '  %s\n' \
      ${SKIP+"SKIP=\"${briefskip}\""} \
      ${VERSION+"VERSION=\"$VERSION\""} \
      ${OPTIONS+"OPTIONS=\"$OPTIONS\""} \
      ${GROUPADD+"GROUPADD=\"$GROUPADD\""} \
      ${USERADD+"USERADD=\"$USERADD\""} \
      ${INSTALL+"INSTALL=\"$INSTALL\""} \
      ${NUMJOBS+"NUMJOBS=\"$NUMJOBS\""} \
      ${ANSWER+"ANSWER=\"$ANSWER\""} \
      ${CLEANUP+"CLEANUP=\"$CLEANUP\""} \
      ${PRAGMA+"PRAGMA=\"$PRAGMA\""} \
      ${NOWARNING+"NOWARNING=\"$NOWARNING\""} \
      ${ARCH+"ARCH=\"$ARCH\""} \
      ${DOWNLOAD+"DOWNLOAD=\"$DOWNLOAD\""} \
      ${MD5SUM+"MD5SUM=\"$MD5SUM\""} \
      ${SHA256SUM+"SHA256SUM=\"$SHA256SUM\""} \
      ${ADDREQUIRES+"ADDREQUIRES=\"$ADDREQUIRES\""} \
      ${DELREQUIRES+"DELREQUIRES=\"$DELREQUIRES\""} \
      ${BUILDTIME+"BUILDTIME=\"$BUILDTIME\""} \
      ${CONFLICTS+"CONFLICTS=\"$CONFLICTS\""} \
      )"

    unset VERSION OPTIONS GROUPADD USERADD \
          BUILDTIME CONFLICTS NOWARNING \
          INSTALL NUMJOBS ANSWER CLEANUP \
          PRAGMA SPECIAL ARCH DOWNLOAD MD5SUM SHA256SUM

  fi

  # FIXUP DEPARTMENT
  # ================

  # Fix INFOREQUIRES
  if [ "${INFOREQUIRES[$itemid]+yesitisset}" != 'yesitisset' ]; then
    # If not set, set it from ADDREQUIRES, if possible
    if [ -v ADDREQUIRES ]; then
      INFOREQUIRES[$itemid]="$ADDREQUIRES"
    else
      log_normal "Dependencies of $itemid can not be determined."
      INFOREQUIRES[$itemid]=""
    fi
  else

    # (1) Remove DELREQUIRES and %README%
    local delreq req newreqlist
    newreqlist=""
    for delreq in ${DELREQUIRES} '%README%'; do
      for req in ${INFOREQUIRES[$itemid]}; do
        [ "$req" != "$delreq" ] && newreqlist="$newreqlist $req"
      done
    done
    INFOREQUIRES[$itemid]="$(echo ${newreqlist})"

    # (2) python3 pragma implies a dep on python3
    local pragma
    for pragma in ${HINT_PRAGMA[$itemid]}; do
      case "$pragma" in
        'python3' ) ADDREQUIRES="python3 ${ADDREQUIRES}" ;;
      esac
    done

    # (3) Append ADDREQUIRES and BUILDTIME
    INFOREQUIRES[$itemid]="$(echo ${INFOREQUIRES[$itemid]} ${ADDREQUIRES} ${HINT_BUILDTIME[$itemid]})"

    # (4) Substitute SUBST
    local newrequires irqdep newdep
    if [ "${#SUBST[@]}" != 0 ] && [ -n "${INFOREQUIRES[$itemid]}" ]; then
      newrequires=''
      for irqdep in ${INFOREQUIRES[$itemid]}; do
        newdep="${SUBST[$irqdep]}"
        if [ -z "$newdep" ]; then
          newdep="$irqdep"
        else
          if [ "$newdep" = '!' ]; then
            log_info "Substitute !${irqdep}"
            newdep=''
          else
            log_info "Substitute ${irqdep} => ${newdep}"
          fi
        fi
        newrequires="$newrequires $newdep"
      done
      INFOREQUIRES[$itemid]=$(echo $newrequires)
    fi

  fi

  # Set HINT_KERNEL -- there are two PRAGMAs for user interface reasons, but because
  # they are not actioned at build-time, they are more useful in the code as HINT_KERNEL
  HINT_KERNEL[$itemid]='n'
  for pragma in ${HINT_PRAGMA[$itemid]}; do
    case "$pragma" in
      'kernel')        HINT_KERNEL[$itemid]='kernel' ;;
      'kernelmodule' ) HINT_KERNEL[$itemid]='kernelmodule' ;;
    esac
  done

  # Fix INFOVERSION from hint file's VERSION, or DOWNLOAD, or git, or SlackBuild's modification time
  local ver="${INFOVERSION[$itemid]}"
  [ -z "$ver" ] && ver="${HINT_VERSION[$itemid]}"
  [ -z "$ver" ] && ver="$(basename "$(echo "${INFODOWNLIST[$itemid]}" | sed 's/ .*//')" 2>/dev/null | rev | cut -f 3- -d . | cut -f 1 -d - | rev)"
  [ -z "$ver" ] && log_warning -n "Version of $itemid can not be determined."
  [ -z "$ver" ] && [ "$GOTGIT" = 'y' ] && ver="${GITREV[$itemid]:0:7}"
  [ -z "$ver" ] && ver="$(date --date=@"$(stat --format='%Y' "$SR_SBREPO"/"$itemdir"/"$itemfile")" '+%Y%m%d')"
  INFOVERSION[$itemid]="$ver"

  # Process SKIP last, so we've got rid of %README%.
  if [ -n "$SKIP" ]; then
    if [ "$SKIP" != 'no' ]; then
      STATUS[$itemid]="skipped"
      STATUSINFO[$itemid]=""
      [ "$SKIP" != 'yes' ] && STATUSINFO[$itemid]="$SKIP"
      return 1
    fi
  fi

  return 0

}
