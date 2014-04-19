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

  log_normal -a "Testing SlackBuild files ..."


  #-----------------------------#
  # (1) prgnam.SlackBuild
  #-----------------------------#

  [ -f $SR_SBREPO/$itempath/$prgnam.SlackBuild ] || \
    { log_error -a "${itempath}: $prgnam.SlackBuild not found"; return 1; }


  #-----------------------------#
  # (2) slack-desc
  #-----------------------------#

  SLACKDESC="$SR_SBREPO/$itempath/slack-desc"
  [ -f $SLACKDESC ] || \
    { log_error -a "${itempath}: slack-desc file not found"; return 1; }
  HR='|-----handy-ruler------------------------------------------------------|'
  # 11 line description pls
  lc=$(grep "^${prgnam}:" $SLACKDESC | wc -l)
  [ "$lc" != 11 ] && \
    log_warning -a "${itempath}: slack-desc: $lc lines of description, should be 11"
  # don't mess with my handy ruler
  if ! grep -q "^ *$HR\$" $SLACKDESC ; then
    log_warning -a "${itempath}: slack-desc: handy-ruler is corrupt or missing"
  elif [ $(grep "^ *$HR\$" $SLACKDESC | sed "s/|.*|//" | wc -c) -ne $(( ${#prgnam} + 1 )) ]; then
    log_warning -a "${itempath}: slack-desc: handy-ruler is misaligned"
  fi
  # check line length
  [ $(grep "^${prgnam}:" $SLACKDESC | sed "s/^${prgnam}://" | wc -L) -gt 73 ] && \
    log_warning -a "${itempath}: slack-desc: description lines too long"
  # did u get teh wrong appname dude
  grep -q -v -e '^#' -e "^${prgnam}:" -e '^$' -e '^ *|-.*-|$' $SLACKDESC && \
    log_warning -a "${itempath}: slack-desc: unrecognised text (appname wrong?)"
  # This one turns out to be far too picky:
  # [ "$(grep "^${prgnam}:" $SLACKDESC | head -n 1 | sed "s/^${prgnam}: ${prgnam} (.*)$//")" != '' ] && \
  #   log_warning -a "${itempath}: slack-desc: first line of description is unconventional"
  # and this one: no trailing spaces kthxbye
  # grep -q "^${prgnam}:.* $"  $SLACKDESC && \
  #   log_warning -a "${itempath}: slack-desc: description has trailing spaces"


  #-----------------------------#
  # (3) prgnam.info
  #-----------------------------#

  if [ -f $SR_SBREPO/$itempath/$prgnam.info ]; then
    unset PRGNAM VERSION HOMEPAGE DOWNLOAD MD5SUM REQUIRES MAINTAINER EMAIL
    . $SR_SBREPO/$itempath/$prgnam.info
    [ "$PRGNAM" = "$prgnam" ] || \
      log_warning -a "${itempath}: PRGNAM in $prgnam.info is '$PRGNAM', not $prgnam"
    [ -n "$VERSION" ] || \
      log_warning -a "${itempath}: VERSION not set in $prgnam.info"
    [ -v HOMEPAGE ] || \
      log_warning -a "${itempath}: HOMEPAGE not set in $prgnam.info"
      # Don't bother testing the homepage URL - parked domains give false negatives
    [ -v DOWNLOAD ] || \
      log_warning -a "${itempath}: DOWNLOAD not set in $prgnam.info"
    [ -v MD5SUM ] || \
      log_warning -a "${itempath}: MD5SUM not set in $prgnam.info"
    [ -v REQUIRES ] || \
      log_warning -a "${itempath}: REQUIRES not set in $prgnam.info"
    [ -v MAINTAINER ] || \
      log_warning -a "${itempath}: MAINTAINER not set in $prgnam.info"
    [ -v EMAIL ] || \
      log_warning -a "${itempath}: EMAIL not set in $prgnam.info"
  fi


  #-----------------------------#
  # (4) README
  #-----------------------------#

  if [ -f $SR_SBREPO/$itempath/README ]; then
    [ "$(wc -L < $SR_SBREPO/$itempath/README)" -le 79 ] || \
      log_warning -a "${itempath}: long lines in README"
  else
    [ -f $SR_SBREPO/$itempath/$prgnam.info ] &&
      { log_error -a "${itempath}: README not found"; return 1; }
  fi


  return 0
}

#-------------------------------------------------------------------------------

function test_download
# Test whether download URLs are 404, by trying to pull the header
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  DOWNLIST="${INFODOWNLIST[$itempath]}"
  if [ -n "$DOWNLIST" ]; then
    log_normal -a "Testing download URLs ..."
    TMP_HEADER=$TMPDIR/sr_header.$$.tmp
    for url in $DOWNLIST; do
      >$TMP_HEADER
      case $url in
      *.googlecode.com/*)
        # Let's hear it for googlecode.com, HTTP HEAD support missing since 2008
        # https://code.google.com/p/support/issues/detail?id=660
        # "Don't be evil, but totally lame is fine"
        curl -q -f -s -k --connect-timeout 60 --retry 5 -J -L -A SlackZilla -o /dev/null $url >> $ITEMLOG 2>&1
        curlstat=$?
        if [ $curlstat != 0 ]; then
          log_warning -a "${itempath}: curl $url failed (status $curlstat), but googlecode.com is rubbish anyway"
        fi
        ;;
      *)
        curl -q -f -s -k --connect-timeout 60 --retry 5 -J -L -A SlackZilla -I -o $TMP_HEADER $url >> $ITEMLOG 2>&1
        curlstat=$?
        if [ $curlstat != 0 ]; then
          log_warning -a "${itempath}: curl $url failed (status $curlstat)"
          if [ -s $TMP_HEADER ]; then
            echo "The following headers may be informative:" >> $ITEMLOG
            cat $TMP_HEADER >> $ITEMLOG
          fi
        else
          : #### check 'Content-Length:' against cached files. You can't be too careful ;-)
        fi
        ;;
      esac
    done
    [ "$OPT_KEEPTMP" != 'y' ] && rm -f $TMP_HEADER
  fi

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
    log_normal -a "Testing $pkgnam..."

    # check the package name
    parse_package_name $pkgnam
    [ "$PN_PRGNAM" != "$prgnam" ] && \
      log_warning -a "${itempath}: ${pkgnam}: PRGNAM is \"$PN_PRGNAM\" not \"$prgnam\""
    [ "$PN_VERSION" != "${INFOVERSION[$itempath]}" -a \
      "$PN_VERSION" != "${INFOVERSION[$itempath]}_$(uname -r | tr - _)" ] && \
      log_warning -a "${itempath}: ${pkgnam}: VERSION is \"$PN_VERSION\" not \"${INFOVERSION[$itempath]}\""
    [ "$PN_ARCH" != "$SR_ARCH" -a \
      "$PN_ARCH" != "noarch" -a \
      "$PN_ARCH" != "fw" ] && \
      log_warning -a "${itempath}: ${pkgnam}: ARCH is $PN_ARCH not $SR_ARCH"
    [ "$PN_BUILD" != "$SR_BUILD" ] && \
      log_warning -a "${itempath}: ${pkgnam}: BUILD is $PN_BUILD not $SR_BUILD"
    [ "$PN_TAG" != "$SR_TAG" ] && \
      log_warning -a "${itempath}: ${pkgnam}: TAG is \"$PN_TAG\" not \"$SR_TAG\""
    [ "$PN_PKGTYPE" != "$SR_PKGTYPE" ] && \
      log_warning -a "${itempath}: ${pkgnam}: Package type is .$PN_PKGTYPE not .$SR_PKGTYPE"

    # check that the compression type matches the suffix
    filetype=$(file -b $pkgpath)
    case "$filetype" in
      'gzip compressed data'*)  [ "$PN_PKGTYPE" = 'tgz' ] || log_warning "${itempath}: ${pkgnam} has wrong suffix, should be .tgz" ;;
      'XZ compressed data'*)    [ "$PN_PKGTYPE" = 'txz' ] || log_warning "${itempath}: ${pkgnam} has wrong suffix, should be .txz" ;;
      'bzip2 compressed data'*) [ "$PN_PKGTYPE" = 'tbz' ] || log_warning "${itempath}: ${pkgnam} has wrong suffix, should be .tbz" ;;
      'LZMA compressed data'*)  [ "$PN_PKGTYPE" = 'tlz' ] || log_warning "${itempath}: ${pkgnam} has wrong suffix, should be .tlz" ;;
      *) log_error "${itempath}: ${pkgnam} is \"$filetype\", not a package" ; return 1 ;;
    esac

    # list what's in the package (and check if it's really a tarball)
    TMP_TARLIST=$TMPDIR/sr_tarlist_${pkgnam}.$$.tmp
    tar tvf $pkgpath > $TMP_TARLIST || { log_error "${itempath}: ${pkgnam} does not contain a tar archive"; return 1; }

    # we'll reuse this file several times to analyse the contents:
    TMP_PKGJUNK=$TMPDIR/sr_pkgjunk_${pkgnam}.$$.tmp

    # check where the files will be installed
    awk '$6!~/^(bin\/|boot\/|dev\/|etc\/|lib\/|lib64\/|opt\/|sbin\/|srv\/|usr\/|var\/|install\/|\.\/$)/' $TMP_TARLIST > $TMP_PKGJUNK
    if [ -s $TMP_PKGJUNK ]; then
      log_warning -a "${itempath}: ${pkgnam} installs to unusual locations"
      cat $TMP_PKGJUNK >> $ITEMLOG
    fi
    baddirlist='usr/local/ usr/share/man/'
    [ "$PN_ARCH"  = 'x86_64' ] && baddirlist+=' usr/lib/' # but not /lib (e.g. modules)
    [ "$PN_ARCH" != 'x86_64' ] && baddirlist+=' lib64/ usr/lib64/'
    for baddir in $baddirlist; do
      awk '$6~/^'$(echo $baddir | sed s:/:'\\'/:g)'/' $TMP_TARLIST > $TMP_PKGJUNK
      if [ -s $TMP_PKGJUNK ]; then
        log_warning -a "${itempath}: ${pkgnam} uses $baddir"
      fi
    done

    # check if it contains a slack-desc
    if ! grep -q ' install/slack-desc$' $TMP_TARLIST; then
      log_warning -a "${itempath}: ${pkgnam} has no slack-desc"
    fi

    # check top level
    if ! head -n 1 $TMP_TARLIST | grep -q '^drwxr-xr-x root/root .* \./$' ; then
      log_warning "${itempath}: ${pkgnam} has wrong top level directory (not tar-1.13?)"
    fi

    # check for non root/root ownership
    if awk '$6~/^(bin\/|lib\/|lib64\/|sbin\/|usr\/|\.\/$)/' $TMP_TARLIST | grep -q -v ' root/root ' ; then
      log_warning -a "${itempath}: ${pkgnam} has files or dirs with owner not root/root"
    fi

    #### TODO: check permissions

    # check for uncompressed man pages (usr/share/man warning is handled above)
    if grep -E '^-.* usr/(share/)?man/' $TMP_TARLIST | grep -q -v '\.gz$'; then
      log_warning -a "${itempath}: ${pkgnam} has uncompressed man pages"
    fi

    [ "$OPT_KEEPTMP" != 'y' ] && rm -f $TMP_PKGJUNK
    # Note! Don't remove TMP_TARLIST yet, create_metadata will use it.

    # If this is the top level item, install it to see what happens :D
    if [ "$itempath" = "$ITEMPATH" ]; then
      install_packages $ITEMPATH || return 1
      uninstall_packages $ITEMPATH
    fi

  done

  return 0
}
