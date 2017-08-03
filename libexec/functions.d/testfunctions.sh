#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# testfunctions.sh - functions for various quality assurance tests in slackrepo
#   test_slackbuild
#   test_download
#   test_package
#-------------------------------------------------------------------------------
#
# Life is too short to do lots of option checking wherever these functions are
# called, so each function should do its own check for OPT_LINT_xxxx and
# return 0 if it isn't enabled.
#
#-------------------------------------------------------------------------------

function test_slackbuild
# Test prgnam.SlackBuild, slack-desc, prgnam.info and README files
# $1 = itemid
# Return status:
# 0 = all good, or lint option not enabled
# 1 = the test found something
# 2 = significant error
{
  [ "$OPT_LINT_SB" != 'y' ] && return 0

  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local retstat=0

  local PRGNAM VERSION HOMEPAGE
  local DOWNLOAD DOWNLOAD_${SR_ARCH}
  local MD5SUM MD5SUM_${SR_ARCH} SHA256SUM SHA256SUM_${SR_ARCH}
  local REQUIRES MAINTAINER EMAIL

  local slackdesc linecount

  log_normal -a "Testing SlackBuild files ... "


  #-----------------------------#
  # (1) prgnam.SlackBuild
  #-----------------------------#

  # Not sure how this could happen, but...
  [ -f "$SR_SBREPO"/"$itemdir"/"$itemfile" ] || \
    { log_error -a "${itemid}: $itemfile not found"; return 2; }


  #-----------------------------#
  # (2) slack-desc
  #-----------------------------#

  slackdesc="$SR_SBREPO"/"$itemdir"/slack-desc
  if [ -f "$slackdesc" ]; then
    # check <=13 line description
    linecount=$(grep -c "^${itemprgnam}:" "$slackdesc")
    [ "$linecount" -gt 13 ] && \
      { log_warning -a "${itemid}: slack-desc: $linecount lines of description"; retstat=1; }
    # check line length <= 80
    [ "$(grep "^${itemprgnam}:" "$slackdesc" | sed "s/^${itemprgnam}://" | wc -L)" -gt 80 ] && \
      { log_warning -a "${itemid}: slack-desc: description lines too long"; retstat=1; }
    # check appname (i.e. $itemprgnam)
    grep -q -v -e '^#' -e "^${itemprgnam}:" -e '^[[:blank:]]*$' -e '^[[:blank:]]*|-.*-|$' -e 'THIS FILE' "$slackdesc"  && \
      { log_warning -a "${itemid}: slack-desc: unrecognised text (appname wrong?)"; retstat=1; }
  else
    { log_warning -a "${itemid}: slack-desc not found"; retstat=1; }
  fi


  #-----------------------------#
  # (3) prgnam.info
  #-----------------------------#

  if [ -f "$SR_SBREPO"/"$itemdir"/"$itemprgnam".info ]; then
    unset PRGNAM VERSION HOMEPAGE DOWNLOAD MD5SUM SHA256SUM REQUIRES MAINTAINER EMAIL
    . "$SR_SBREPO"/"$itemdir"/"$itemprgnam".info
    [ "$PRGNAM" = "$itemprgnam" ] || \
      { log_warning -a "${itemid}: PRGNAM in $itemprgnam.info is '$PRGNAM' (expected $itemprgnam)"; retstat=1; }
    [ -n "$VERSION" ] || \
      { log_warning -a "${itemid}: VERSION not set in $itemprgnam.info"; retstat=1; }
    case "$VERSION" in
      *-*) log_warning -a "${itemid}: VERSION \"$VERSION\" in $itemprgnam.info contains '-'"; retstat=1 ;;
    esac
    [ -v HOMEPAGE ] || \
      { log_warning -a "${itemid}: HOMEPAGE not set in $itemprgnam.info"; retstat=1; }
      # Don't bother testing the homepage URL - parked domains give false negatives
    [ -v DOWNLOAD ] || \
      { log_warning -a "${itemid}: DOWNLOAD not set in $itemprgnam.info"; retstat=1; }
    [ -v MD5SUM ] || \
      { log_warning -a "${itemid}: MD5SUM not set in $itemprgnam.info"; retstat=1; }
    #### check it's valid hex md5sum, same number of sums as downloads
    #### check DOWNLOAD_arch & MD5SUM_arch
    #### don't do checks on unofficial SHA256SUM at the moment
    [ -v REQUIRES ] || \
      { log_warning -a "${itemid}: REQUIRES not set in $itemprgnam.info"; retstat=1; }
    [ -v MAINTAINER ] || \
      { log_warning -a "${itemid}: MAINTAINER not set in $itemprgnam.info"; retstat=1; }
    [ -v EMAIL ] || \
      { log_warning -a "${itemid}: EMAIL not set in $itemprgnam.info"; retstat=1; }
  elif [ "$OPT_REPO" = 'SBo' ]; then
    { log_warning -a "${itemid}: $itemprgnam.info not found"; retstat=1; }
  fi


  #-----------------------------#
  # (4) README
  #-----------------------------#

  # if [ -f "$SR_SBREPO"/"$itemdir"/README ]; then
  #   [ "$(wc -L < "$SR_SBREPO"/"$itemdir"/README)" -le 79 ] || \
  #     log_warning -a "${itemid}: long lines in README"
  # fi

  if [ "$OPT_REPO" = 'SBo' ] && [ ! -f "$SR_SBREPO"/"$itemdir"/README ]; then
    { log_warning -a "${itemid}: README not found"; retstat=1; }
  fi

  [ "$retstat" = 0 ] && log_done
  return $retstat
}

#-------------------------------------------------------------------------------

function test_download
# Test whether download URLs are 404, by trying to pull the header
# $1 = itemid
# Return status:
# 0 = all good, or lint option not enabled
# 1 = not found, found but modified, or otherwise failed
# 2 = significant error
{
  [ "$OPT_LINT_DL" != 'y' ] && return 0

  local itemid="$1"
  local -a downlist
  local MY_HEADER url curlstat
  local retstat=0

  downlist=( ${INFODOWNLIST[$itemid]} )
  if [ "${#downlist[@]}" != 0 ]; then
    log_normal -a "Testing download URLs ... "
    MY_HEADER="$MYTMP"/curlheader
    for url in "${downlist[@]}"; do
      # Try to retrieve just the header.
      true > "$MY_HEADER"
      case "$url" in
      *.googlecode.com/*)
        # Let's hear it for googlecode.com, HTTP HEAD support missing since 2008
        # https://code.google.com/p/support/issues/detail?id=660
        # "Don't be evil, but totally lame is fine"
        curl -q --connect-timeout 10 --retry 2 -f -s -k --ciphers ALL --disable-epsv --ftp-method nocwd -J -L -A slackrepo -o /dev/null "$url" >> "$ITEMLOG" 2>&1
        curlstat=$?
        if [ "$curlstat" != 0 ]; then
          tryurl="http://slackware.uk/sbosrcarch/by-name/${itemid}/${url##*/}"
          curl -q --connect-timeout 10 --retry 2 -f -v -k --ciphers ALL -J -L -A slackrepo -I "$tryurl" >/dev/null 2>&1
          if [ $? = 0 ]; then
            log_warning -a "${itemid}: Download test failed. $(print_curl_status $curlstat). (Available at sbosrcarch)"
          else
            tryurl="https://sourceforge.net/projects/slackbuildsdirectlinks/files/${ITEMPRGNAM[$itemid]}/${url##*/}"
            curl -q --connect-timeout 10 --retry 2 -f -v -k --ciphers ALL -J -L -A slackrepo -I "$tryurl" >/dev/null 2>&1
            if [ $? = 0 ]; then
              log_warning -a "${itemid}: Download test failed. $(print_curl_status $curlstat). (Available at SBoDL)"
            else
              log_warning -a "${itemid}: Download test failed. $(print_curl_status $curlstat)."
            fi
          fi
          log_info -a "$url"
          retstat=1
        fi
        ;;
      *)
        curl -q --connect-timeout 10 --retry 2 -f -v -k --ciphers ALL --disable-epsv --ftp-method nocwd -J -L -A slackrepo -I -o "$MY_HEADER" "$url" >> "$ITEMLOG" 2>&1
        curlstat=$?
        if [ "$curlstat" = 0 ]; then
          remotelength=$(fromdos <"$MY_HEADER" | grep 'Content-[Ll]ength: ' | tail -n 1 | sed 's/^.* //')
          # Proceed only if we seem to have extracted a valid content-length.
          if [ -n "$remotelength" ] && [ "$remotelength" != 0 ]; then
            # Filenames that have %nn encodings won't get checked.
            filename=$(fromdos <"$MY_HEADER" | grep 'Content-[Dd]isposition:.*filename=' | sed -e 's/^.*filename=//' -e 's/^"//' -e 's/"$//' -e 's/\%20/ /g' -e 's/\%7E/~/g')
            # If no Content-Disposition, we'll have to guess:
            [ -z "$filename" ] && filename="$(basename "$url")"
            if [ -f "${SRCDIR[$itemid]}"/"$filename" ]; then
              cachedlength=$(stat -c '%s' "${SRCDIR[$itemid]}"/"$filename")
              if [ "$remotelength" != "$cachedlength" ]; then
                if [ "${HINT_MD5IGNORE[$itemid]}" = 'y' ] || [ "${HINT_SHA256IGNORE[$itemid]}" = 'y' ]; then
                  log_important -a "${itemid}: Source has been modified upstream."
                else
                  log_warning -a "${itemid}: Source has been modified upstream."
                fi
                log_info -a "$url"
                retstat=1
              fi
            fi
          fi
        else
          # Header failed, try a full download (amazonaws is "special"... possibly more...)
          TMP_DOWNLOAD="$BIGTMP"/curldownload
          curl -q --connect-timeout 10 --retry 2 -f -s -k --ciphers ALL -J -L -A slackrepo -o "$TMP_DOWNLOAD" "$url" >> "$ITEMLOG" 2>&1
          curlstat=$?
          if [ "$curlstat" = 0 ]; then
            remotemd5=$(md5sum <"$TMP_DOWNLOAD"); remotemd5="${remotemd5/ */}"
            found='n'
            for cachedmd5 in ${INFOMD5LIST[$itemid]}; do
              if [ "$remotemd5" = "$cachedmd5" ]; then
                found='y'; break
              fi
            done
            if [ "$found" = 'n' ]; then
              if [ "${HINT_MD5IGNORE[$itemid]}" = 'y' ] || [ "${HINT_SHA256IGNORE[$itemid]}" = 'y' ]; then
                log_important -a "${itemid}: Source has been modified upstream."
              else
                log_warning -a "${itemid}: Source has been modified upstream."
              fi
              log_info -a "$url"
              retstat=1
            fi
          else
            tryurl="http://slackware.uk/sbosrcarch/by-name/${itemid}/${url##*/}"
            curl -q --connect-timeout 10 --retry 2 -f -v -k --ciphers ALL -J -L -A slackrepo -I "$tryurl" >/dev/null 2>&1
            if [ $? = 0 ]; then
              log_warning -a "${itemid}: Download test failed. $(print_curl_status $curlstat). (Available at sbosrcarch)"
            else
              tryurl="https://sourceforge.net/projects/slackbuildsdirectlinks/files/${ITEMPRGNAM[$itemid]}/${url##*/}"
              curl -q --connect-timeout 10 --retry 2 -f -v -k --ciphers ALL -J -L -A slackrepo -I "$tryurl" >/dev/null 2>&1
              if [ $? = 0 ]; then
                log_warning -a "${itemid}: Download test failed. $(print_curl_status $curlstat). (Available at SBoDL)"
              else
                log_warning -a "${itemid}: Download test failed. $(print_curl_status $curlstat)."
              fi
            fi
            log_info -a "$url"
            retstat=1
            if [ -s "$MY_HEADER" ]; then
              echo "The following headers may be informative:" >> "$ITEMLOG"
              cat "$MY_HEADER" >> "$ITEMLOG"
            fi
          fi
          rm -f "$TMP_DOWNLOAD"
        fi
        ;;
      esac
    done
  fi

  [ "$retstat" = 0 ] && log_done
  return $retstat

}

#-------------------------------------------------------------------------------

function test_package
# Test a package (check its name, and check its contents)
# $1 (optionally) -n => do not try to install the packages
# $1    = itemid
# $2... = paths of packages to be checked
# Return status:
# 0 = all good, or lint option not enabled
# 1 = the test found something
# 2 = significant error
{
  [ "${OPT_LINT_PKG:-n}" != 'y' ] && return 0

  local tryinstall='y'
  if [ "${OPT_LINT_INST:-n}" != 'y' ]; then
    tryinstall='n'
  fi
  if [ "$1" = '-n' ] ; then
    tryinstall='n'
    shift
  fi

  local itemid="$1"
  shift
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local -a baddirlist
  local pkgpath pkgbasename filetype baddirlist baddir
  local retstat=0

  while [ $# != 0 ]; do
    pkgpath="$1"
    pkgbasename=$(basename "$pkgpath")
    shift
    log_normal -a "Testing package $pkgbasename ... "

    # check the prgnam
    parse_package_name "$pkgbasename"
    [ "$PN_PRGNAM" != "$itemprgnam" ] && \
      { log_warning -a "${itemid}: Package PRGNAM is \"$PN_PRGNAM\" (expected \"$itemprgnam\"). ${pkgbasename}"; retstat=1; }

    # check the version
    if [ "$CMD" = 'lint' ]; then
      # for the lint command, use the database (in case the package is out of date w.r.t. the .info file)
      checkversion=$(db_get_rev "$itemid" | cut -f2 -d" ")
    else
      # otherwise, it should be the same as INFOVERSION (or INFOVERSION_KERNEL)
      checkversion="${INFOVERSION[$itemid]}"
      [ "${HINT_KERNEL[$itemid]}" != 'n' ] && checkversion="${INFOVERSION[$itemid]}_$(echo ${SYS_KERNEL} | tr - _)"
    fi
    # also, we'll accept '_anything' (e.g. locale) as a suffix to checkversion
    [ "$PN_VERSION" != "${checkversion}" ] && [ "${PN_VERSION##${checkversion}_*}" != "" ] && \
      { log_warning -a "${itemid}: Package VERSION is \"$PN_VERSION\" (expected \"${checkversion}\"). ${pkgbasename}"; retstat=1; }

    # check the arch
    okarch='n'
    if [ "$PN_ARCH" = "$SR_ARCH" ]; then
      okarch='y'
    else
      case "$PN_ARCH" in
        i386 | i486 | i586 | i686 )
          case "$SR_ARCH" in
            i386 | i486 | i586 | i686 ) okarch='y' ;;
          esac
          ;;
        arm )
          [ "${SR_ARCH:0:3}" = 'arm' ] && okarch='y'
          ;;
        arm* )
          [ "$SR_ARCH" = 'arm' ] && okarch='y'
          ;;
        noarch | fw )
          okarch='y'
          ;;
      esac
    fi
    [ "$okarch" != 'y' ] && { log_warning -a "${itemid}: Package ARCH is $PN_ARCH (expected $SR_ARCH). ${pkgbasename}"; retstat=1; }

    # check the build
    [ -n "$SR_BUILD" ] && [ "$PN_BUILD" != "$SR_BUILD" ] && \
      { log_warning -a "${itemid}: Package BUILD is $PN_BUILD (expected $SR_BUILD). ${pkgbasename}"; retstat=1; }

    # check the tag
    [ "$PN_TAG" != "$SR_TAG" ] && \
      { log_warning -a "${itemid}: Package TAG is \"$PN_TAG\" (expected \"$SR_TAG\"). ${pkgbasename}"; retstat=1; }

    # check the pkgtype
    [ "$PN_PKGTYPE" != "$SR_PKGTYPE" ] && \
      { log_warning -a "${itemid}: Package type is .$PN_PKGTYPE (expected .$SR_PKGTYPE). ${pkgbasename}"; retstat=1; }

    # check that the actual compression type matches the suffix
    filetype=$(file -b "$pkgpath")
    case "$filetype" in
      'gzip compressed data'*)  [ "$PN_PKGTYPE" = 'tgz' ] || { log_warning -a "${itemid}: Wrong suffix (should be .tgz). ${pkgbasename}"; retstat=1; } ;;
      'XZ compressed data'*)    [ "$PN_PKGTYPE" = 'txz' ] || { log_warning -a "${itemid}: Wrong suffix (should be .txz). ${pkgbasename}"; retstat=1; } ;;
      'bzip2 compressed data'*) [ "$PN_PKGTYPE" = 'tbz' ] || { log_warning -a "${itemid}: Wrong suffix (should be .tbz). ${pkgbasename}"; retstat=1; } ;;
      'LZMA compressed data'*)  [ "$PN_PKGTYPE" = 'tlz' ] || { log_warning -a "${itemid}: Wrong suffix (should be .tlz). ${pkgbasename}"; retstat=1; } ;;
      *) log_error -a "${itemid}: Not a package (\"$filetype\"). ${pkgbasename}" ; return 2 ;;
    esac

    # list what's in the package (and check if it's really a tarball)
    # we'll reuse this file several times to analyse the contents
    MY_PKGCONTENTS="$MYTMP"/pkgcontents_"$pkgbasename"
    tar tvf "$pkgpath" > "$MY_PKGCONTENTS" || { log_error -a "${itemid}: Not a tar archive. ${pkgbasename}"; return 2; }

    # check directories
    wrongstuff=$(awk \
      '$6!~/^(bin\/|boot\/|dev\/|etc\/|lib\/|lib64\/|opt\/|sbin\/|srv\/|tmp\/|usr\/|var\/|install\/|\.\/$)/ {printf "%s\n",$0}' <"$MY_PKGCONTENTS")
    if [ -n "$wrongstuff" ]; then
      log_warning -a "${itemid}: Nonstandard directories. ${pkgbasename}"
      log_info -t -a "$wrongstuff"
      retstat=1
    fi
    for baddir in 'tmp/' 'usr/local/' 'usr/share/man/'; do
      wrongstuff=$(awk '$6~/^'"$(echo $baddir | sed s:/:'\\'/:g)"'/' <"$MY_PKGCONTENTS")
      if [ -n "$wrongstuff" ]; then
        log_warning -a "${itemid}: Bad directory $baddir. ${pkgbasename}"
        log_info -t -a "$wrongstuff"
        retstat=1
      fi
    done

    # check for arch-inappropriate files and locations
    case "$PN_ARCH" in
      i?86)
          for baddir in 'lib64/' 'usr/lib64/' ; do
            wrongstuff=$(awk '$6~/^'"$(echo $baddir | sed s:/:'\\'/:g)"'/' <"$MY_PKGCONTENTS")
            if [ -n "$wrongstuff" ]; then
              log_warning -a "${itemid}: Bad directory $baddir for arch $PN_ARCH. ${pkgbasename}"
              log_info -t -a "$wrongstuff"
              retstat=1
            fi
          done
          ;;
      x86_64)
          libstuff=$(awk '$6~/^'"$(echo usr/lib/ | sed s:/:'\\'/:g)"'/' <"$MY_PKGCONTENTS")
          if [ -n "$libstuff" ]; then
            # if we're testing a package we just built, destdir might still exist
            if [ -d "$BIGTMP/build_$itemprgnam/package-$itemprgnam" ]; then
              pkgtree="$BIGTMP/build_$itemprgnam/package-$itemprgnam"
            else
              # we're going to have to extract it :(
              pkgtree="$BIGTMP"/pkgtree
              mkdir -p "$pkgtree"
              tar xf "$pkgpath" -C "$pkgtree" usr/lib/
            fi
            # yes, 'x86-64' has a '-' not a '_'
            wrongstuff=$(cd "$pkgtree"; find usr/lib -print0 | xargs -0 file 2>/dev/null | \
              grep -e "executable" -e "shared object" | grep 'ELF' | grep 'x86-64' | cut -f1 -d:)
            if [ -n "$wrongstuff" ]; then
              log_warning -a "${itemid}: x86-64 files in /usr/lib. ${pkgbasename}"
              log_info -t -a "$wrongstuff"
              retstat=1
            fi
          fi
          ;;
      noarch | fw)
          if [ -d "$BIGTMP/build_$itemprgnam/package-$itemprgnam" ]; then
            pkgtree="$BIGTMP/build_$itemprgnam/package-$itemprgnam"
          else
            pkgtree="$BIGTMP"/pkgtree
            mkdir -p "$pkgtree"
            tar xf "$pkgpath" -C "$pkgtree"
          fi
          wrongstuff=$(cd "$pkgtree"; find * -print0 | xargs -0 file 2>/dev/null | \
            grep -e "executable" -e "shared object" | grep 'ELF' | cut -f1 -d:)
          if [ -n "$wrongstuff" ]; then
            log_warning -a "${itemid}: executables and/or libraries in noarch package. ${pkgbasename}"
            log_info -t -a "$wrongstuff"
            retstat=1
          fi
          ;;
      x86) :
          ;;
      *)   :
          ;;
    esac
    rm -rf "$BIGTMP"/pkgtree

    # check if it contains a slack-desc
    if ! grep -q ' install/slack-desc$' "$MY_PKGCONTENTS"; then
      log_warning -a "${itemid}: No slack-desc. ${pkgbasename}"
      retstat=1
    fi

    # check top level directory
    topdir=$(head -n 1 "$MY_PKGCONTENTS")
    if ! echo "$topdir" | grep -q '^drwxr-xr-x root/root .* \./$' ; then
      log_warning -a "${itemid}: Bad root directory. ${pkgbasename}"
      log_info -a "$topdir"
      retstat=1
    fi

    # check groups and/or users
    okgroups='root'
    if [ -n "${VALID_GROUPS[$itemid]}" ]; then
      okgroups="(${okgroups}|${VALID_GROUPS[$itemid]})"
    fi
    okusers='root'
    if [ -n "${VALID_USERS[$itemid]}" ]; then
      okusers="(${okusers}|${VALID_USERS[$itemid]})"
    fi
    wrongstuff=$(awk \
      "\$2~/^$okusers\/$okgroups\$/ {next};
       \$2~/^[[:alpha:]]+\/[[:alpha:]]+\$/ {next};
       {printf \"%s\\n\",\$0}" <"$MY_PKGCONTENTS")
    if [ -n "$wrongstuff" ]; then
      log_warning -a "${itemid}: Unexpected owner/group. ${pkgbasename}"
      log_info -t -a "$wrongstuff"
      retstat=1
    fi

    # check for uncompressed man pages (usr/share/man warning is handled above)
    wrongstuff=$(grep -E '^-.* usr/(share/)?man/' "$MY_PKGCONTENTS" | grep -v '\.gz$')
    if [ -n "$wrongstuff" ]; then
      log_warning -a "${itemid}: Uncompressed man pages. ${pkgbasename}"
      log_info -t -a "$wrongstuff"
      retstat=1
    fi

    [ "$retstat" = 0 ] && log_done

    # Note! Don't remove MY_PKGCONTENTS yet, create_metadata will use it.

    # Install it to see what happens (but not if --dry-run)
    if [ "$OPT_DRY_RUN" != 'y' ] && [ "$tryinstall" != 'n' ]; then
      log_normal -a "Test installing $pkgbasename ..."
      # if install_packages returns nonzero, we can assume the package doesn't need to be uninstalled
      install_packages "$pkgpath" || return 1
    fi

  done

  uninstall_packages "$itemid"
  return $retstat
}
