#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# qafunctions.sh - functions for various quality assurance tests in slackrepo
#   qa_sbfiles
#   qa_package
#-------------------------------------------------------------------------------

function qa_sbfiles
# Test prg.info, prg.SlackBuild, README and slack-desc files
# $1 = itemname
# Return status:
# 0 = all good or warnings only
# 1 = significant error
{
  local itemname="$1"
  local prg=$(basename $itemname)

  local PRGNAM VERSION HOMEPAGE
  local DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH}
  local REQUIRES MAINTAINER EMAIL

  log_normal "Testing SlackBuild files..."

  #-----------------------------#
  # (1) Check the .SlackBuild
  [ -f $SR_GITREPO/$itemname/$prg.SlackBuild ] || \
    { log_error "${itemname}: $prg.SlackBuild not found"; return 1; }

  #-----------------------------#
  # (2) check the slack-desc
  SLACKDESC="$SR_GITREPO/$itemname/slack-desc"
  [ -f $SLACKDESC ] || \
    { log_error "${itemname}: slack-desc file not found"; return 1; }
  HR='|-----handy-ruler------------------------------------------------------|'
  # 11 line description pls
  lc=$(grep "^${prg}:" $SLACKDESC | wc -l)
  [ "$lc" != 11 ] && \
    log_warning "${itemname}: slack-desc: $lc lines of description, should be 11"
  # no trailing spaces kthxbye
  grep -q "^${prg}:.* $"  $SLACKDESC && \
    log_warning "${itemname}: slack-desc: description has trailing spaces"
  # dont mess with my handy ruler
  grep -q "^ *$HR\$" $SLACKDESC || \
    log_warning "${itemname}: slack-desc: handy-ruler is corrupt or missing"
  [ $(grep "^ *$HR\$" $SLACKDESC | sed "s/|.*|//" | wc -c) -ne $(( ${#prg} + 1 )) ] && \
    log_warning "${itemname}: slack-desc: handy-ruler is misaligned"
  # check line length
  [ $(grep "^${prg}:" $SLACKDESC | sed "s/^${prg}://" | wc -L) -gt 73 ] && \
    log_warning "${itemname}: slack-desc: description lines too long"
  # did u get teh wrong appname dude
  grep -q -v -e '^#' -e "^${prg}:" -e '^$' -e '^ *|-.*-|$' $SLACKDESC && \
    log_warning "${itemname}: slack-desc: unrecognised text (appname wrong?)"
  # This one turns out to be far too picky:
  # [ "$(grep "^${prg}:" $SLACKDESC | head -n 1 | sed "s/^${prg}: ${prg} (.*)$//")" != '' ] && \
  #   log_warning "${itemname}: slack-desc: first line of description is unconventional"

  #-----------------------------#
  # (3) Check the .info
  [ -f $SR_GITREPO/$itemname/$prg.info ] || \
    { log_error "${itemname}: $prg.info not found"; return 1; }
  trap "log_error \"${itemname}: command error in $prg.info\"; return 1" ERR
  . $SR_GITREPO/$itemname/$prg.info
  trap - ERR

  [ "$PRGNAM" = "$prg" ] || \
    log_warning "${itemname}: PRGNAM in $prg.info is '$PRGNAM', not $prg"
  [ -n "$VERSION" ] || \
    log_warning "${itemname}: VERSION not set in $prg.info"
  [ -v REQUIRES ] || \
    log_warning "${itemname}: REQUIRES not set in $prg.info"
  #### would be good to check URLs to see if they still exist

  #-----------------------------#
  # (4) Check the README
  [ -f $SR_GITREPO/$itemname/README ] || \
    { log_error "${itemname}: README not found"; return 1; }
  [ "$(wc -L < $SR_GITREPO/$itemname/README)" -le 76 ] || \
    log_warning "${itemname}: long lines in README"

  return 0
}

#-------------------------------------------------------------------------------

function qa_package
# Test a package (check its name, and check its contents)
# $* = paths of packages to be checked
# Return status:
# 0 = all good or warnings only
# 1 = significant error
{
  while [ $# != 0 ]; do
    local pkgpath=$1
    local pkgname=$(basename $pkgpath)
    shift
    log_normal "Testing $pkgpath..."
    # Check the package name
    parse_package_name $pkgname
    [  "$PN_PRGNAM" != "$PRGNAM"     ] && log_warning "${pkgname}: PRGNAM is $PN_PRGNAM not $PRGNAM"
    [ "$PN_VERSION" != "$VERSION"    ] && log_warning "${pkgname}: VERSION is $PN_VERSION not $VERSION"
    [    "$PN_ARCH" != "$SR_ARCH" -a "$PN_ARCH" != "noarch" -a "$PN_ARCH" != "fw" ] && \
      log_warning "${pkgname}: ARCH is $PN_ARCH not $SR_ARCH or noarch or fw"
    [   "$PN_BUILD" != "$SR_BUILD"   ] && log_warning "${pkgname}: BUILD is $PN_BUILD not $SR_BUILD"
    [     "$PN_TAG" != "$SR_TAG"     ] && log_warning "${pkgname}: TAG is '$PN_TAG' not '$SR_TAG'"
    [ "$PN_PKGTYPE" != "$SR_PKGTYPE" ] && log_warning "${pkgname}: Package type is .$PN_PKGTYPE not .$SR_PKGTYPE"
    # Check the package contents
    tar tf $pkgpath > $TMP/sr_pkgt
    if grep -q -v -E '^(bin)|(boot)|(dev)|(etc)|(lib)|(opt)|(sbin)|(usr)|(var)|(install)|(./$)' $TMP/sr_pkgt; then
      log_warning "${pkgname}: files are installed in unusual locations"
    fi
    if ! grep -q 'install/slack-desc' $TMP/sr_pkgt; then
      log_warning "${pkgname}: package does not contain slack-desc"
    fi
    #### TODO: check modes of package contents
    #### TODO: check whether a noarch package is really noarch
    # If this is the top level item, install it to see what happens :D
    if [ "$PRGNAM" = "$(basename $ITEMNAME)" ]; then
      install_package $ITEMNAME || return 1
      uninstall_package $ITEMNAME
    # else it's a dep and it'll be installed soon anyway.
    fi

  done
  return
}
