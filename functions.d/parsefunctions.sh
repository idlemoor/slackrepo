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
# Returns canonical [<directory>/]<prgnam> name (or names) in $ITEMLIST
# and populates associative arrays with values from the .info file:
# INFOVERSION INFODOWNLIST INFOMD5LIST INFOREQUIRES
# Return status:
# 0 = all ok
# 1 = any item not found
# 9 = existential crisis
{
  ITEMLIST=''
  errstat=0
  local blamemsg=''
  [ -n "$BLAME" ] && blamemsg="${BLAME}: "

  if [ "$1" = '-s' ]; then
    SEARCHFILE='.SlackBuild'
    TOPLEVEL="$SR_SBREPO"
    shift
  elif [ "$1" = '-p' ]; then
    SEARCHFILE='-*.t?z'
    TOPLEVEL="$SR_PKGREPO"
    shift
  else
    log_error "parse_items: invalid argument '$1'"
    return 9
  fi

  while [ $# != 0 ]; do

    local item="${1##/}"
    a=$(echo "$item/" | cut -f1 -d/)
    b=$(echo "$item/" | cut -f2 -d/)
    shift

    # We can have zero, one, or two names in $a and $b.
    if [ -z "$a" -a -n "$b" ]; then
      # this can't happen due to '${1##/}' above, but if it *does* happen,
      # put the only name we've got in $a and make $b empty:
      a="$b"; b=''
    fi

    if [ -z "$a" -a -z "$b" ]; then
      # zero names supplied
      log_warning "$(basename $0): ${blamemsg}Empty item specified"
      errstat=1
      continue
    fi

    if [ -z "$b" ]; then
      # one name supplied
      if [ -f $TOPLEVEL/$a/$a$SEARCHFILE ]; then
        # one-level repo, exact match :-)
        ITEMLIST="$ITEMLIST $a"
      else
        # is it a prog in a two-level repo?
        progcount=$(ls $TOPLEVEL/*/$a/$a$SEARCHFILE 2>/dev/null | wc -l)
        if [ $progcount = 1 ]; then
          # two-level repo, one matching prog :-)
          ITEMLIST="$ITEMLIST $(cd $TOPLEVEL/*/$a/..; basename $(pwd))/$a"
        elif [ $progcount != 0 ]; then
          log_warning "${blamemsg}Multiple matches for $a in $TOPLEVEL, please specify the category"
          errstat=1
          continue
        else
          # is it a category in a two-level repo?
          if [ -d "$TOPLEVEL/$a" ]; then
            # push the whole category onto $*
            cd $TOPLEVEL
            ITEMLIST="$ITEMLIST $(ls -d $a/*)"
            cd - >/dev/null
          else
            log_warning "${blamemsg}${a} not found in $TOPLEVEL"
            errstat=1
            continue
          fi
        fi
      fi
    else
      # two names supplied, so it should be a prog in a two-level repo:
      if [ -f $TOPLEVEL/$a/$b/$b$SEARCHFILE ]; then
        # two-level repo, exact match :-)
        ITEMLIST="$ITEMLIST $a/$b"
      else
        # let's try to be user-friendly:
        if [ -d "$TOPLEVEL/$a/$b" ]; then
          log_warning "${blamemsg}$TOPLEVEL/$a/$b/$b$SEARCHFILE not found"
        elif [ -d "$TOPLEVEL/$a" ]; then
          log_warning "${blamemsg}${b} not found in $TOPLEVEL/$a"
        else
          log_warning "${blamemsg}${a}/${b} not found in $TOPLEVEL"
        fi
        errstat=1
        continue
      fi
    fi

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
      # if this doesn't work, we can confidently assert that the SlackBuild is broken :P
      versioncmd="$(grep '^VERSION=' $SR_SBREPO/$itempath/$prgnam.SlackBuild)"
      cd $SR_SBREPO/$itempath/
        eval $versioncmd
      cd - >/dev/null
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
      log_normal "Note: could not determine REQUIRES from $prgnam.info, dependencies will not be processed"
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
