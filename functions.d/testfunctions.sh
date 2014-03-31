#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# testfunctions.sh - functions for various quality assurance tests in slackrepo
#   test_slackbuild
#   test_download
#   test_package
#-------------------------------------------------------------------------------

function test_slackbuild
# Test prgnam.SlackBuild, slack-desc, prgnam.info and README files
# $1 = itempath
# Return status:
# 0 = all good or warnings only
# 1 = significant error
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  local PRGNAM VERSION HOMEPAGE
  local DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH}
  local REQUIRES MAINTAINER EMAIL

  log_normal -p "Testing SlackBuild files..."

  #-----------------------------#
  # (1) Check prgnam.SlackBuild
  [ -f $SR_SBREPO/$itempath/$prgnam.SlackBuild ] || \
    { log_error -p "${itempath}: $prgnam.SlackBuild not found"; return 1; }

  #-----------------------------#
  # (2) check slack-desc
  SLACKDESC="$SR_SBREPO/$itempath/slack-desc"
  [ -f $SLACKDESC ] || \
    { log_error -p "${itempath}: slack-desc file not found"; return 1; }
  HR='|-----handy-ruler------------------------------------------------------|'
  # 11 line description pls
  lc=$(grep "^${prgnam}:" $SLACKDESC | wc -l)
  [ "$lc" != 11 ] && \
    log_warning -p "${itempath}: slack-desc: $lc lines of description, should be 11"
  # don't mess with my handy ruler
  if ! grep -q "^ *$HR\$" $SLACKDESC ; then
    log_warning -p "${itempath}: slack-desc: handy-ruler is corrupt or missing"
  elif [ $(grep "^ *$HR\$" $SLACKDESC | sed "s/|.*|//" | wc -c) -ne $(( ${#prgnam} + 1 )) ]; then
    log_warning -p "${itempath}: slack-desc: handy-ruler is misaligned"
  fi
  # check line length
  [ $(grep "^${prgnam}:" $SLACKDESC | sed "s/^${prgnam}://" | wc -L) -gt 73 ] && \
    log_warning -p "${itempath}: slack-desc: description lines too long"
  # did u get teh wrong appname dude
  grep -q -v -e '^#' -e "^${prgnam}:" -e '^$' -e '^ *|-.*-|$' $SLACKDESC && \
    log_warning -p "${itempath}: slack-desc: unrecognised text (appname wrong?)"
  # This one turns out to be far too picky:
  # [ "$(grep "^${prgnam}:" $SLACKDESC | head -n 1 | sed "s/^${prgnam}: ${prgnam} (.*)$//")" != '' ] && \
  #   log_warning -p "${itempath}: slack-desc: first line of description is unconventional"
  # and this one: no trailing spaces kthxbye
  # grep -q "^${prgnam}:.* $"  $SLACKDESC && \
  #   log_warning -p "${itempath}: slack-desc: description has trailing spaces"

  #-----------------------------#
  # (3) Check prgnam.info
  [ -f $SR_SBREPO/$itempath/$prgnam.info ] || \
    { log_error -p "${itempath}: $prgnam.info not found"; return 1; }

  unset PRGNAM VERSION HOMEPAGE DOWNLOAD MD5SUM REQUIRES MAINTAINER EMAIL
  . $SR_SBREPO/$itempath/$prgnam.info

  [ "$PRGNAM" = "$prgnam" ] || \
    log_warning -p "${itempath}: PRGNAM in $prgnam.info is '$PRGNAM', not $prgnam"
  [ -n "$VERSION" ] || \
    log_warning -p "${itempath}: VERSION not set in $prgnam.info"
  [ -v HOMEPAGE ] || \
    log_warning -p "${itempath}: HOMEPAGE not set in $prgnam.info"
  [ -v DOWNLOAD ] || \
    log_warning -p "${itempath}: DOWNLOAD not set in $prgnam.info"
  [ -v MD5SUM ] || \
    log_warning -p "${itempath}: MD5SUM not set in $prgnam.info"
  [ -v REQUIRES ] || \
    log_warning -p "${itempath}: REQUIRES not set in $prgnam.info"
  [ -v MAINTAINER ] || \
    log_warning -p "${itempath}: MAINTAINER not set in $prgnam.info"
  [ -v EMAIL ] || \
    log_warning -p "${itempath}: EMAIL not set in $prgnam.info"

  #### would be good to check HOMEPAGE and DOWNLOAD URLs to see if they still exist

  #-----------------------------#
  # (4) Check README
  [ -f $SR_SBREPO/$itempath/README ] || \
    { log_error -p "${itempath}: README not found"; return 1; }
  [ "$(wc -L < $SR_SBREPO/$itempath/README)" -le 79 ] || \
    log_warning -p "${itempath}: long lines in README"

  return 0
}

#-------------------------------------------------------------------------------

function test_download
# Test whether URLs are 404
# $1    = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  headertmp=$TMPDIR/sr_header.$$.tmp

  log_normal -p "Testing download URLs ..."
  DOWNLIST="${INFODOWNLIST[$itempath]}"
  for url in $DOWNLIST; do
    case $url in
    *.googlecode.com/*)
      # Let's hear it for googlecode.com, HTTP HEAD support missing since 2008
      # https://code.google.com/p/support/issues/detail?id=660
      # "Don't be evil, but totally lame is fine"
      curl -q -s -k --connect-timeout 240 --retry 2 -J -L -o /dev/null $url >> $SR_LOGDIR/$itempath.log 2>&1
      curlstat=$?
      if [ $curlstat != 0 ]; then
        log_warning -p "${itempath}: $url failed (curl status $curlstat), but it could just be googlecode.com being stupid again"
        cat $headertmp ######
      fi
      ;;
    *)
      curl -q -s -k --connect-timeout 240 --retry 2 -J -L -I -o $headertmp $url >> $SR_LOGDIR/$itempath.log 2>&1
      curlstat=$?
      if [ $curlstat != 0 ]; then
        log_warning -p "${itempath}: $url failed (curl status $curlstat)"
        cat $headertmp ######
      else
        : # check 'Content-Length:' against cached files. You can't be too careful ;-)
      fi
      ;;
    esac
  done
  rm -f $headertmp
  return 0
}

#-------------------------------------------------------------------------------

function test_package
# Test a package (check its name, and check its contents)
# $1    = itempath
# $2... = paths of packages to be checked
# Return status:
# 0 = all good or warnings only
# 1 = significant error
{
  local itempath="$1"
  local prgnam=${itempath##*/}
  shift

  while [ $# != 0 ]; do
    local pkgpath=$1
    local pkgnam=${pkgpath##*/}
    shift
    log_normal -p "Testing $pkgnam..."
    # Check the package name
    parse_package_name $pkgnam
    [ "$PN_PRGNAM" != "$prgnam" ] && \
      log_warning -p "${itempath}: ${pkgnam}: PRGNAM is \"$PN_PRGNAM\" not \"$prgnam\""
    [ "$PN_VERSION" != "${INFOVERSION[$itempath]}" -a \
      "$PN_VERSION" != "${INFOVERSION[$itempath]}_$(uname -r)" ] && \
      log_warning -p "${itempath}: ${pkgnam}: VERSION is \"$PN_VERSION\" not \"${INFOVERSION[$itempath]}\""
    [ "$PN_ARCH" != "$SR_ARCH" -a \
      "$PN_ARCH" != "noarch" -a \
      "$PN_ARCH" != "fw" ] && \
      log_warning -p "${itempath}: ${pkgnam}: ARCH is $PN_ARCH not $SR_ARCH or noarch or fw"
    [ "$PN_BUILD" != "$SR_BUILD" ] && \
      log_warning -p "${itempath}: ${pkgnam}: BUILD is $PN_BUILD not $SR_BUILD"
    [ "$PN_TAG" != "$SR_TAG" ] && \
      log_warning -p "${itempath}: ${pkgnam}: TAG is \"$PN_TAG\" not \"$SR_TAG\""
    [ "$PN_PKGTYPE" != "$SR_PKGTYPE" ] && \
      log_warning -p "${itempath}: ${pkgnam}: Package type is .$PN_PKGTYPE not .$SR_PKGTYPE"
    # Check the package contents

    #### check the compression matches the suffix
    #### COMPEXE=$( pkgcomp $pkg )
    #### if $COMPEXE -cd $pkg | tar tOf - install/slack-desc 1>/dev/null 2>&1 ; then
    #### check that install/slack-desc exists

    #### TODO: check it's tar-1.13 compatible
    temptarlist=$TMPDIR/sr_tarlist.$$.tmp
    tar tf $pkgpath > $temptarlist
    if grep -q -v -E '^(bin)|(boot)|(dev)|(etc)|(lib)|(opt)|(sbin)|(usr)|(var)|(install)|(./$)' $temptarlist; then
      log_warning -p "${itempath}: ${pkgnam}: files are installed in unusual locations"
    fi
    for verboten in usr/local usr/share/man; do
      if grep -q '^'$verboten $temptarlist; then
        log_warning -p "${itempath}: ${pkgnam}: files are installed in $verboten"
      fi
    done
    #### TODO: check all manpages compressed
    if ! grep -q 'install/slack-desc' $temptarlist; then
      log_warning -p "${itempath}: ${pkgnam}: package does not contain slack-desc"
    fi
    #### TODO: check modes of package contents
    #### TODO: check whether a noarch package is really noarch
    rm -f $temptarlist

    # If this is the top level item, install it to see what happens :D
    if [ "$itempath" = "$ITEMPATH" ]; then
      log_verbose "Installing ${ITEMPATH}..."
      install_package $ITEMPATH || return 1
      uninstall_package $ITEMPATH
    # else it's a dep and it'll be installed soon anyway.
    fi

  done

  return 0
}
