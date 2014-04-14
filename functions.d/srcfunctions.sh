#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# srcfunctions.sh - source functions for slackrepo
#   verify_src
#   download_src
#-------------------------------------------------------------------------------

function verify_src
# Verify item's source files in the source cache
# $1 = itempath
# Also uses variables $VERSION and $NEWVERSION set by build_package
# Return status:
# 0 - all files passed, or md5sum check suppressed, or DOWNLIST is empty
# 1 - one or more files had a bad md5sum
# 2 - no. of files != no. of md5sums
# 3 - directory not found or empty => not cached, need to download
# 4 - version mismatch, need to download new version
# 5 - .info says item is unsupported/untested on this arch
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  DOWNLIST="${INFODOWNLIST[$itempath]}"
  MD5LIST="${INFOMD5LIST[$itempath]}"
  DOWNDIR="${SRCDIR[$itempath]}"

  # Quick checks:
  # if the item doesn't need source, return 0
  [ -z "$DOWNLIST" -o -z "$DOWNDIR" ] && return 0
  # if unsupported/untested, return 5
  [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ] && \
    { log_warning -n "$itempath is $DOWNLIST on $SR_ARCH"; return 5; }
  # if no directory, return 3
  [ ! -d "$DOWNDIR" ] && return 3

  # More complex checks:
  ( cd "$DOWNDIR"
    # if wrong version, return 4
    if [ "$VERSION" != "$(cat .version 2>/dev/null)" ]; then
      log_verbose -a "Removing old source files"
      find . -maxdepth 1 -type f -exec rm -f {} \;
      return 4
    fi
    log_normal -a "Verifying source files ..."
    numgot=$(find . -maxdepth 1 -type f -print 2>/dev/null| grep -v '^\./\.version$' | wc -l)
    numwant=$(echo $MD5LIST | wc -w)
    # no files, empty directory => return 3 (same as no directory)
    [ $numgot = 0 ] && return 3
    # or if we have not got the right number of sources, return 2
    [ $numgot != $numwant ] && { log_verbose -a "Note: need $numwant source files, but have $numgot"; return 2; }
    # if we're ignoring the md5sums, we've finished => return 0
    [ "${HINT_md5ignore[$itempath]}" = 'y' ] && return 0
    # also ignore md5sum if we upversioned => return 0
    [ -n "$NEWVERSION" ] && { log_verbose -a "Note: not checking md5sums due to version hint"; return 0; }
    # run the md5 check on all the files (don't give up at the first error)
    allok='y'
    for f in *; do
      # check files only (arch-specific subdirectories may exist, ignore them)
      if [ -f "$f" ]; then
        mf=$(md5sum "$f" | sed 's/ .*//')
        ok='n'
        # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
        for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
        [ "$ok" = 'y' ] || { log_verbose -a "Note: failed md5sum: $f"; allok='n'; }
      fi
    done
    [ "$allok" = 'y' ] || { return 1; }
  )
  return $?  # status comes directly from subshell
}

#-------------------------------------------------------------------------------

function download_src
# Download the sources for itempath into the cache
# $1 = itempath
# Also uses variables $DOWNDIR and $DOWNLIST previously set by verify_src,
# and $VERSION set by build_package
# Return status:
# 1 - curl failed
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ -n "$DOWNDIR" ]; then
    mkdir -p "$DOWNDIR"
    find "$DOWNDIR" -maxdepth 1 -type f -exec rm {} \;
  else
    return 0
  fi

  if [ -z "$DOWNLIST" ]; then
    # stamp the cache with a .version file even though there are no sources
    echo "$VERSION" > "$DOWNDIR"/.version
    return 0
  fi

  log_normal -a "Downloading source files ..."
  ( cd "$DOWNDIR"
    if [ -n "$DOWNLIST" ]; then
      downargs=""
      for url in $DOWNLIST; do downargs="$downargs -O $url"; done
      curl -q -f '-#' -k --connect-timeout 120 --retry 2 -J -L -A SlackZilla $downargs >> $ITEMLOG 2>&1
      curlstat=$?
      case $curlstat in
        0)   echo "$VERSION" > "$DOWNDIR"/.version
             # curl content-disposition can't undo %-encoding.
             # %20 -> space seems to be the most common problem:
             for spacetrouble in $(ls *%20* 2>/dev/null); do
               mv "$spacetrouble" "$(echo "$spacetrouble" | sed 's/\%20/ /g')"
             done
             return 0
             ;;
             # it's a pity curl doesn't do the next bit itself...
        1)   curlmsg="Unsupported protocol" ;;
        2)   curlmsg="Failed to initialize" ;;
        3)   curlmsg="URL malformed" ;;
        4)   curlmsg="A feature or option that was needed to perform the desired request was not enabled or was explicitly disabled at build-time" ;;
        5)   curlmsg="Couldn't resolve proxy" ;;
        6)   curlmsg="Couldn't resolve host" ;;
        7)   curlmsg="Failed to connect to host" ;;
        8)   curlmsg="FTP weird server reply" ;;
        9)   curlmsg="FTP access denied" ;;
        11)  curlmsg="FTP weird PASS reply" ;;
        13)  curlmsg="FTP weird PASV reply, Curl couldn't parse the reply sent to the PASV request" ;;
        14)  curlmsg="FTP weird 227 format" ;;
        15)  curlmsg="FTP can't get host" ;;
        17)  curlmsg="FTP couldn't set binary" ;;
        18)  curlmsg="Partial file" ;;
        19)  curlmsg="FTP couldn't download/access the given file, the RETR (or similar) command failed" ;;
        21)  curlmsg="FTP quote error" ;;
        22)  curlmsg="HTTP page not retrieved" ;;
        23)  curlmsg="Write error" ;;
        25)  curlmsg="FTP couldn't STOR file" ;;
        26)  curlmsg="Read error" ;;
        27)  curlmsg="Out of memory" ;;
        28)  curlmsg="Operation timeout" ;;
        30)  curlmsg="FTP PORT failed" ;;
        31)  curlmsg="FTP couldn't use REST" ;;
        33)  curlmsg="HTTP range error" ;;
        34)  curlmsg="HTTP post error" ;;
        35)  curlmsg="SSL connect error" ;;
        36)  curlmsg="FTP bad download resume" ;;
        37)  curlmsg="FILE couldn't read file" ;;
        38)  curlmsg="LDAP cannot bind" ;;
        39)  curlmsg="LDAP search failed" ;;
        41)  curlmsg="Function not found" ;;
        42)  curlmsg="Aborted by callback" ;;
        43)  curlmsg="Internal error" ;;
        45)  curlmsg="Interface error" ;;
        47)  curlmsg="Too many redirects" ;;
        48)  curlmsg="Unknown option specified to libcurl" ;;
        49)  curlmsg="Malformed telnet option" ;;
        51)  curlmsg="The peer's SSL certificate or SSH MD5 fingerprint was not OK" ;;
        52)  curlmsg="The server didn't reply anything, which here is considered an error" ;;
        53)  curlmsg="SSL crypto engine not found" ;;
        54)  curlmsg="Cannot set SSL crypto engine as default" ;;
        55)  curlmsg="Failed sending network data" ;;
        56)  curlmsg="Failure in receiving network data" ;;
        58)  curlmsg="Problem with the local certificate" ;;
        59)  curlmsg="Couldn't use specified SSL cipher" ;;
        60)  curlmsg="Peer certificate cannot be authenticated with known CA certificates" ;;
        61)  curlmsg="Unrecognized transfer encoding" ;;
        62)  curlmsg="Invalid LDAP URL" ;;
        63)  curlmsg="Maximum file size exceeded" ;;
        64)  curlmsg="Requested FTP SSL level failed" ;;
        65)  curlmsg="Sending the data requires a rewind that failed" ;;
        66)  curlmsg="Failed to initialise SSL Engine" ;;
        67)  curlmsg="The user name, password, or similar was not accepted and curl failed to log in" ;;
        68)  curlmsg="File not found on TFTP server" ;;
        69)  curlmsg="Permission problem on TFTP server" ;;
        70)  curlmsg="Out of disk space on TFTP server" ;;
        71)  curlmsg="Illegal TFTP operation" ;;
        72)  curlmsg="Unknown TFTP transfer ID" ;;
        73)  curlmsg="File already exists (TFTP)" ;;
        74)  curlmsg="No such user (TFTP)" ;;
        75)  curlmsg="Character conversion failed" ;;
        76)  curlmsg="Character conversion functions required" ;;
        77)  curlmsg="Problem with reading the SSL CA cert (path? access rights?)" ;;
        78)  curlmsg="The resource referenced in the URL does not exist" ;;
        79)  curlmsg="An unspecified error occurred during the SSH session" ;;
        80)  curlmsg="Failed to shut down the SSL connection" ;;
        82)  curlmsg="Could not load CRL file, missing or wrong format (added in 7" ;;
        83)  curlmsg="Issuer check failed (added in 7" ;;
        84)  curlmsg="The FTP PRET command failed" ;;
        85)  curlmsg="RTSP: mismatch of CSeq numbers" ;;
        86)  curlmsg="RTSP: mismatch of Session Identifiers" ;;
        87)  curlmsg="unable to parse FTP file list" ;;
        88)  curlmsg="FTP chunk callback reported error" ;;
        89)  curlmsg="No connection available, the session will be queued " ;;
        *)   log_error -a "Download failed with curl status $curlstat"; return 1 ;;
      esac
      log_error -a "Download failed with curl status $curlstat ($curlmsg)"
      return 1
    fi
  )
}
