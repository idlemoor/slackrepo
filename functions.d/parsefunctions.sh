#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# parsefunctions.sh - parse functions for slackrepo
#   parse_items
#   parse_package_name
#   parse_info
#   parse_hints
#-------------------------------------------------------------------------------

function parse_items
# Parse item names
# $1 = -s => look up in SlackBuild repo, or -p => look up in Package repo
# $* = the item names to be parsed :-)
#    - can be <prgnam>, or <directory>/.../<prgnam>
#    - any number of directories are supported
#    - if <prgnam> is unambiguous, directories can be omitted
# Also uses $BLAME which the caller can set for extra info in errors and warnings
# Returns relative pathname (or names) in $ITEMLIST of the directory containing
# the SlackBuild or package -- this is identical in the source and package repos
# (unless the package hasn't been built yet, or the SlackBuild has been removed).
#
# Current restrictions:
# (1) The SlackBuild has to have the same name as its containing directory, but
# the package can have a different name.
# (2) Will go horribly wrong if the SlackBuild or package is in the top level
# directory :-(
# 
# Return status:
# 0 = all ok
# 1 = any item not found
# 9 = existential crisis
{
  local blamemsg=''
  [ -n "$BLAME" ] && blamemsg="${BLAME}: "

  if [ "$1" = '-s' ]; then
    TOPLEVEL="$SR_SBREPO"
    SEARCHSUFFIX='.SlackBuild'
    shift
  elif [ "$1" = '-p' ]; then
    TOPLEVEL="$SR_PKGREPO"
    SEARCHSUFFIX='-*.t?z'
    # Note that SEARCHSUFFIX might match multiple packages in a single directory!
    shift
  else
    log_error "parse_items: invalid argument '$1'"
    return 9
  fi

  cd "$TOPLEVEL"
  ITEMLIST=''
  errstat=0

  while [ $# != 0 ]; do
    local item="${1##/}"
    shift

    case $item in

    '' )
      # null item?  No thanks.
      log_warning "${blamemsg}Empty item specified"
      errstat=1
      ;;

    */*$SEARCHSUFFIX )
      # relative path to a SlackBuild or package: it should be right here
      if [ ! -f "$item" ]; then
        log_warning "${blamemsg}${TOPLEVEL}/${item} not found"
        errstat=1
      else
        # check name of SlackBuild
        ITEMLIST="$ITEMLIST $(dirname $item)"
      fi
      ;;

    *$SEARCHSUFFIX )
      # simple SlackBuild or package name: it could be anywhere under here
      found=$(find . type f -name "$item" | sed 's:^\./::')
      wc=$(echo $found | wc -w)
      if [ "$wc" = 0 ]; then
        log_warning "${blamemsg}${item} not found in ${TOPLEVEL}"
        errstat=1
      elif [ "$wc" != 1 ]; then
        log_warning "${blamemsg}Multiple matches for ${item} within ${TOPLEVEL}, please specify a relative path"
        errstat=1
      else
        ITEMLIST="$ITEMLIST $(dirname $found)"
      fi
      ;;

    */* )
      # relative path to a directory: it should be right here
      if [ ! -d "$item" ]; then
        log_warning "${blamemsg}${TOPLEVEL}/${item} not found"
        errstat=1
      else
        # does it contain packages or a slackbuild?
        if [ -f "$(ls $item/$(basename $item)$SEARCHSUFFIX 2>/dev/null | head -n 1)" ]; then
          # yes => return the containing directory
          ITEMLIST="$ITEMLIST $item"
        else
          # no => it should contain subdirectories that we can expand later
          subdirs=$(find . -mindepth 1 -maxdepth 1 -type d | sed 's:^\./::')
          if [ -z "$subdirs" ]; then
            log_warning "${blamemsg}${item} contains nothing useful"
            errstat=1
          else
            ITEMLIST="$ITEMLIST $subdirs"
          fi
        fi
      fi
      ;;

    * )
      # simple name: somewhere under here there should be exactly one directory with that name
      found=$(find . -type d -name "$item" -print | sed 's:^\./::')
      wc=$(echo $found | wc -w)
      if [ "$wc" = 0 ]; then
        log_warning "${blamemsg}${item} not found in ${TOPLEVEL}"
        errstat=1
      elif [ "$wc" != 1 ]; then
        log_warning "${blamemsg}Multiple matches for ${item} within ${TOPLEVEL}, please specify a relative path"
        errstat=1
      else
        # does it contain packages or a slackbuild?
        if [ -f "$(ls $found/${item}${SEARCHSUFFIX} 2>/dev/null | head -n 1)" ]; then
          # yes => return the containing directory
          ITEMLIST="$ITEMLIST $found"
        else
          # no => it should contain subdirectories that we can expand later
          subdirs=$(find $found -mindepth 1 -maxdepth 1 -type d | sed 's:^\./::')
          if [ -z "$subdirs" ]; then
            log_warning "${blamemsg}${found} contains nothing useful"
            errstat=1
          else
            ITEMLIST="$ITEMLIST $subdirs"
          fi
        fi
      fi
      ;;

   esac

  done

  return $errstat

}

#-------------------------------------------------------------------------------

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

function parse_info
# Load up .info file into variables INFO*.  If no .info file, be creative :-)
# Also populates SRCDIR, GITREV and GITDIRTY
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  # It's not straightforward to tell an SBo style SlackBuild from a Slackware
  # style SlackBuild.  Some Slackware SlackBuilds have partial or full .info,
  # but also have source (often repackaged) that clashes with DOWNLOAD=. 
  # Maybe it needs another kind of hint :-(

  if [ "${INFOVERSION[$itempath]+yesitisset}" != 'yesitisset' ]; then

    # These are the variables we need:
    unset VERSION DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH} REQUIRES
    # Preferably, get them from prgnam.info:
    if [ -f $SR_SBREPO/$itempath/$prgnam.info ]; then
      # is prgnam.info plausibly in SBo format?
      if grep -q '^VERSION=' $SR_SBREPO/$itempath/$prgnam.info ; then
        . $SR_SBREPO/$itempath/$prgnam.info
      fi
    fi
    # Backfill anything still unset:
    # VERSION
    if [ -z "$VERSION" ]; then
      # The next bit is necessarily dependent on the empirical characteristics of Slackware's SlackBuilds :-/
      versioncmds="$(grep -E '^(PKGNAM)|(SRCNAM)|(VERSION)=' $SR_SBREPO/$itempath/$prgnam.SlackBuild)"
      cd $SR_SBREPO/$itempath/
        eval $versioncmds
      cd - >/dev/null
      unset PKGNAM SRCNAM
      if [ -z "$VERSION" ]; then
        log_error "Could not determine VERSION from $prgnam.info or $prgnam.SlackBuild"
        return 1
      fi
    fi
    INFOVERSION[$itempath]=$VERSION
    # DOWNLOAD[_ARCH] and MD5SUM[_ARCH]
    # Don't bother checking if they are improperly paired (it'll become apparent later).
    # If they are unset, set empty strings in INFODOWNLIST / INFOMD5LIST.
    # Also set SRCDIR (even if there is no source, SRCDIR is needed to hold .version)
    if [ -n "$(eval echo \$DOWNLOAD_$SR_ARCH)" ]; then
      INFODOWNLIST[$itempath]="$(eval echo \$DOWNLOAD_$SR_ARCH)"
      INFOMD5LIST[$itempath]="$(eval echo \$MD5SUM_$SR_ARCH)"
      SRCDIR[$itempath]=$SR_SRCREPO/$itempath/$SR_ARCH
    else
      INFODOWNLIST[$itempath]="${DOWNLOAD:-}"
      INFOMD5LIST[$itempath]="${MD5SUM:-}"
      SRCDIR[$itempath]=$SR_SRCREPO/$itempath
    fi
    # REQUIRES
    if [ "${REQUIRES+yesitisset}" != "yesitisset" ]; then
      log_normal "Dependencies of $itempath could not be determined."
    fi
    INFOREQUIRES[$itempath]="${REQUIRES:-}"

    # Not from prgnam.info -- GITREV and GITDIRTY
    if [ "$GOTGIT" = 'y' ]; then
      GITREV[$itempath]="$(cd $SR_SBREPO/$itempath; git log -n 1 --format=format:%H .)"
      GITDIRTY[$itempath]="n"
      if [ -n "$(cd $SR_SBREPO/$itempath; git status -s .)" ]; then
        GITDIRTY[$itempath]="y"
      fi
    else
      GITREV[$itempath]=''
      GITDIRTY[$itempath]="n"
    fi

  fi

  return 0
}

#-------------------------------------------------------------------------------

function parse_hints
# Load up hint files into variables HINT_*
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  gothints=''

  FLAGHINTS="md5ignore makej1 no_uninstall"
  # These are Boolean hints.
  # Query them like this: '[ "${HINT_xxx[$itempath]}" = 'y' ]'
  for hint in $FLAGHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itempath]='y'
    else
      eval HINT_$hint[$itempath]=''
    fi
  done

  FILEHINTS="skipme cleanup uidgid answers"
  # These are hints where the file contents will be used.
  # Query them like this: '[ -n "${HINT_xxx[$itempath]}" ]'
  for hint in $FILEHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itempath]="$SR_HINTS/$itempath.$hint"
    else
      eval HINT_$hint[$itempath]=''
    fi
  done

  VARHINTS="options optdeps readmedeps version"
  # These are hints where the file contents will be used by slackrepo itself.
  # '%NONE%' indicates the file doesn't exist (vs. readmedeps exists and is empty).
  # Query them like this: '[ "${HINT_xxx[$itempath]}" != '%NONE%' ]'
  for hint in $VARHINTS; do
    if [ -f $SR_HINTS/$itempath.$hint ]; then
      gothints="$gothints $hint"
      eval HINT_$hint[$itempath]=\"$(cat $SR_HINTS/$itempath.$hint)\"
    else
      eval HINT_$hint[$itempath]='%NONE%'
    fi
  done

  # Log hints, unless skipme is set (in which case we are about to bail out noisily).
  if [ -z "${HINT_skipme[$itempath]}" -a -n "$gothints" ]; then
    log_normal "Hints for ${itempath}:"
    log_normal " $gothints"
  fi

  return 0
}
