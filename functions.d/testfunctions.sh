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
# $1 = itemid
# Return status:
# 0 = all good or warnings only
# 1 = significant error
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"

  local PRGNAM VERSION HOMEPAGE
  local DOWNLOAD DOWNLOAD_${SR_ARCH} MD5SUM MD5SUM_${SR_ARCH}
  local REQUIRES MAINTAINER EMAIL

  local slackdesc hr linecount

  log_normal -a "Testing SlackBuild files ..."


  #-----------------------------#
  # (1) prgnam.SlackBuild
  #-----------------------------#

  [ -f "$SR_SBREPO"/"$itemdir"/"$itemfile" ] || \
    { log_error -a "${itemid}: $itemfile not found"; return 1; }


  #-----------------------------#
  # (2) slack-desc
  #-----------------------------#

  slackdesc="$SR_SBREPO"/"$itemdir"/slack-desc
  if [ -f "$slackdesc" ]; then
    hr='|-----handy-ruler------------------------------------------------------|'
    # check 11 line description
    linecount=$(grep "^${itemprgnam}:" "$slackdesc" | wc -l)
    [ "$linecount" != 11 ] && \
      log_warning -a "${itemid}: slack-desc: $linecount lines of description (expected 11)"
    # check handy ruler
    if ! grep -q "^ *$hr\$" "$slackdesc" ; then
      log_warning -a "${itemid}: slack-desc: handy-ruler is corrupt or missing"
    elif [ $(grep "^ *$hr\$" "$slackdesc" | sed "s/|.*|//" | wc -c) -ne $(( ${#itemprgnam} + 1 )) ]; then
      log_warning -a "${itemid}: slack-desc: handy-ruler is misaligned"
    fi
    # check line length <= 73
    [ $(grep "^${itemprgnam}:" "$slackdesc" | sed "s/^${itemprgnam}://" | wc -L) -gt 73 ] && \
      log_warning -a "${itemid}: slack-desc: description lines too long"
    # check appname (i.e. $itemprgnam)
    grep -q -v -e '^#' -e "^${itemprgnam}:" -e '^$' -e '^ *|-.*-|$' "$slackdesc" && \
      log_warning -a "${itemid}: slack-desc: unrecognised text (appname wrong?)"
  else
    log_warning -a "${itemid}: slack-desc not found"
  fi


  #-----------------------------#
  # (3) prgnam.info
  #-----------------------------#

  if [ -f "$SR_SBREPO"/"$itemdir"/"$itemprgnam".info ]; then
    unset PRGNAM VERSION HOMEPAGE DOWNLOAD MD5SUM REQUIRES MAINTAINER EMAIL
    . "$SR_SBREPO"/"$itemdir"/"$itemprgnam".info
    [ "$PRGNAM" = "$itemprgnam" ] || \
      log_warning -a "${itemid}: PRGNAM in $itemprgnam.info is '$PRGNAM' (expected $itemprgnam)"
    [ -n "$VERSION" ] || \
      log_warning -a "${itemid}: VERSION not set in $itemprgnam.info"
    [ -v HOMEPAGE ] || \
      log_warning -a "${itemid}: HOMEPAGE not set in $itemprgnam.info"
      # Don't bother testing the homepage URL - parked domains give false negatives
    [ -v DOWNLOAD ] || \
      log_warning -a "${itemid}: DOWNLOAD not set in $itemprgnam.info"
    [ -v MD5SUM ] || \
      log_warning -a "${itemid}: MD5SUM not set in $itemprgnam.info"
    [ -v REQUIRES ] || \
      log_warning -a "${itemid}: REQUIRES not set in $itemprgnam.info"
    [ -v MAINTAINER ] || \
      log_warning -a "${itemid}: MAINTAINER not set in $itemprgnam.info"
    [ -v EMAIL ] || \
      log_warning -a "${itemid}: EMAIL not set in $itemprgnam.info"
  fi


  #-----------------------------#
  # (4) README
  #-----------------------------#

  if [ -f "$SR_SBREPO"/"$itemdir"/README ]; then
    [ $(wc -L < "$SR_SBREPO"/"$itemdir"/README) -le 79 ] || \
      log_warning -a "${itemid}: long lines in README"
  else
    log_warning -a "${itemid}: README not found"
  fi


  return 0
}

#-------------------------------------------------------------------------------

function test_download
# Test whether download URLs are 404, by trying to pull the header
# $1 = itemid
# Return status: always 0
{
  local itemid="$1"
  local -a downlist
  local TMP_HEADER url curlstat

  downlist=( ${INFODOWNLIST[$itemid]} )
  if [ "${#downlist[@]}" != 0 ]; then
    log_normal -a "Testing download URLs ..."
    TMP_HEADER="$TMPDIR"/sr_header.$$.tmp
    for url in "${downlist[@]}"; do
      > "$TMP_HEADER"
      case "$url" in
      *.googlecode.com/*)
        # Let's hear it for googlecode.com, HTTP HEAD support missing since 2008
        # https://code.google.com/p/support/issues/detail?id=660
        # "Don't be evil, but totally lame is fine"
        curl -q -f -s -k --connect-timeout 60 --retry 5 -J -L -A SlackZilla -o /dev/null "$url" >> "$ITEMLOG" 2>&1
        curlstat=$?
        if [ "$curlstat" != 0 ]; then
          log_warning -a "${itemid}: Download test failed: $(print_curl_status $curlstat). $url"
        fi
        ;;
      *)
        curl -q -f -s -k --connect-timeout 60 --retry 5 -J -L -A SlackZilla -I -o "$TMP_HEADER" "$url" >> "$ITEMLOG" 2>&1
        curlstat=$?
        if [ "$curlstat" != 0 ]; then
          log_warning -a "${itemid}: Header test failed: $(print_curl_status $curlstat). $url"
          if [ -s "$TMP_HEADER" ]; then
            echo "The following headers may be informative:" >> "$ITEMLOG"
            cat "$TMP_HEADER" >> "$ITEMLOG"
          fi
        else
          remotelength=$(grep 'Content-Length: ' "$TMP_HEADER" | tail -n 1 | fromdos | sed 's/^.* //')
          # Proceed only if we seem to have extracted a valid content-length.
          if [ -n "$remotelength" ]; then
            # Filenames that have %nn encodings won't get checked.
            filename=$(grep 'Content-Disposition: ' "$TMP_HEADER" | sed -e 's/^.*filename="//' -e 's/".*//')
            # If no Content-Disposition, we'll have to guess:
            [ -z "$filename" ] && filename="$(basename "$url")"
            if [ -f "${SRCDIR[$itemid]}"/"$filename" ]; then
              cachedlength=$(stat -c '%s' "${SRCDIR[$itemid]}"/"$filename")
              if [ "$remotelength" != "$cachedlength" ]; then
                log_warning -a "${itemid}: $filename has been modified upstream"
              fi
            fi
          fi
        fi
        ;;
      esac
    done
    [ "$OPT_KEEPTMP" != 'y' ] && rm -f "$TMP_HEADER"
  fi

  return 0
}

#-------------------------------------------------------------------------------

function test_package
# Test a package (check its name, and check its contents)
# $1    = itemid
# $2... = paths of packages to be checked
# Return status:
# 0 = all good or warnings only
# 1 = significant error
{
  local itemid="$1"
  shift
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local -a baddirlist
  local pkgpath pkgnam filetype baddirlist baddir

  while [ $# != 0 ]; do
    pkgpath="$1"
    pkgnam=$(basename "$pkgpath")
    shift
    log_normal -a "Testing $pkgnam..."

    # check the package name
    parse_package_name $pkgnam
    [ "$PN_PRGNAM" != "$itemprgnam" ] && \
      log_warning -a "${itemid}: ${pkgnam}: PRGNAM is \"$PN_PRGNAM\" (expected \"$itemprgnam\")"
    [ "$PN_VERSION" != "${INFOVERSION[$itemid]}" -a \
      "$PN_VERSION" != "${INFOVERSION[$itemid]}_$(uname -r | tr - _)" ] && \
      log_warning -a "${itemid}: ${pkgnam}: VERSION is \"$PN_VERSION\" (expected \"${INFOVERSION[$itemid]}\")"
    [ "$PN_ARCH" != "$SR_ARCH" -a \
      "$PN_ARCH" != "noarch" -a \
      "$PN_ARCH" != "fw" ] && \
      log_warning -a "${itemid}: ${pkgnam}: ARCH is $PN_ARCH (expected $SR_ARCH)"
    [ "$PN_BUILD" != "$SR_BUILD" ] && \
      log_warning -a "${itemid}: ${pkgnam}: BUILD is $PN_BUILD (expected $SR_BUILD)"
    [ "$PN_TAG" != "$SR_TAG" ] && \
      log_warning -a "${itemid}: ${pkgnam}: TAG is \"$PN_TAG\" (expected \"$SR_TAG\")"
    [ "$PN_PKGTYPE" != "$SR_PKGTYPE" ] && \
      log_warning -a "${itemid}: ${pkgnam}: Package type is .$PN_PKGTYPE (expected .$SR_PKGTYPE)"

    # check that the compression type matches the suffix
    filetype=$(file -b "$pkgpath")
    case "$filetype" in
      'gzip compressed data'*)  [ "$PN_PKGTYPE" = 'tgz' ] || log_warning "${itemid}: ${pkgnam} has wrong suffix, should be .tgz" ;;
      'XZ compressed data'*)    [ "$PN_PKGTYPE" = 'txz' ] || log_warning "${itemid}: ${pkgnam} has wrong suffix, should be .txz" ;;
      'bzip2 compressed data'*) [ "$PN_PKGTYPE" = 'tbz' ] || log_warning "${itemid}: ${pkgnam} has wrong suffix, should be .tbz" ;;
      'LZMA compressed data'*)  [ "$PN_PKGTYPE" = 'tlz' ] || log_warning "${itemid}: ${pkgnam} has wrong suffix, should be .tlz" ;;
      *) log_error "${itemid}: ${pkgnam} is \"$filetype\", not a package" ; return 1 ;;
    esac

    # list what's in the package (and check if it's really a tarball)
    TMP_PKGCONTENTS="$TMPDIR"/sr_pkgcontents_"$pkgnam".$$.tmp
    tar tvf "$pkgpath" > "$TMP_PKGCONTENTS" || { log_error "${itemid}: ${pkgnam} is not a tar archive"; return 1; }

    # we'll reuse this file several times to analyse the contents:
    TMP_PKGJUNK="$TMPDIR"/sr_pkgjunk_"$pkgnam".$$.tmp

    # check where the files will be installed
    awk '$6!~/^(bin\/|boot\/|dev\/|etc\/|lib\/|lib64\/|opt\/|sbin\/|srv\/|usr\/|var\/|install\/|\.\/$)/' "$TMP_PKGCONTENTS" > "$TMP_PKGJUNK"
    if [ -s "$TMP_PKGJUNK" ]; then
      log_warning -a "${itemid}: ${pkgnam} installs to unusual locations"
      cat "$TMP_PKGJUNK" >> "$ITEMLOG"
    fi
    baddirlist=( 'usr/local/' 'usr/share/man/' )
    [ "$PN_ARCH"  = 'x86_64' ] && baddirlist+=( 'usr/lib/' ) # but not /lib (e.g. modules)
    [ "$PN_ARCH" != 'x86_64' ] && baddirlist+=( 'lib64/' 'usr/lib64/' )
    for baddir in "${baddirlist[@]}"; do
      awk '$6~/^'$(echo $baddir | sed s:/:'\\'/:g)'/' "$TMP_PKGCONTENTS" > "$TMP_PKGJUNK"
      if [ -s "$TMP_PKGJUNK" ]; then
        log_warning -a "${itemid}: $pkgnam uses $baddir"
      fi
    done

    # check if it contains a slack-desc
    if ! grep -q ' install/slack-desc$' "$TMP_PKGCONTENTS"; then
      log_warning -a "${itemid}: ${pkgnam} has no slack-desc"
    fi

    # check top level
    if ! head -n 1 "$TMP_PKGCONTENTS" | grep -q '^drwxr-xr-x root/root .* \./$' ; then
      log_warning "${itemid}: ${pkgnam} has wrong top level directory (not tar-1.13?)"
    fi

    # check for non root/root ownership (this may be a bit oversensitive)
    if awk '$6~/^(bin\/|lib\/|lib64\/|sbin\/|usr\/|\.\/$)/' "$TMP_PKGCONTENTS" | grep -q -v ' root/root ' ; then
      log_warning -a "${itemid}: ${pkgnam} has files or dirs with owner not root/root"
    fi

    #### TODO: check permissions

    # check for uncompressed man pages (usr/share/man warning is handled above)
    #### maybe check for misplaced pages
    if grep -E '^-.* usr/(share/)?man/' "$TMP_PKGCONTENTS" | grep -q -v '\.gz$'; then
      log_warning -a "${itemid}: ${pkgnam} has uncompressed man pages"
    fi

    [ "$OPT_KEEPTMP" != 'y' ] && rm -f "$TMP_PKGJUNK"
    # Note! Don't remove TMP_PKGCONTENTS yet, create_metadata will use it.

    # Install it to see what happens (but not if --dry-run)
    if [ "$OPT_DRYRUN" != 'y' ]; then
      install_packages "$itemid" || return 1
      uninstall_packages "$itemid"
    fi

  done

  return 0
}
