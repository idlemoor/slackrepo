#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# srcfunctions.sh - source functions for slackrepo
#   verify_src
#   download_src
#   print_curl_status
#-------------------------------------------------------------------------------

function verify_src
# Verify item's source files in the source cache
# $1 = itemid
# Return status:
# 0 - all files passed, or md5sum check suppressed, or DOWNLIST is empty
# 1 - one or more files had a bad md5sum
# 2 - no. of files != no. of md5sums
# 3 - directory not found or empty => not in source cache, need to download
# 4 - version mismatch, need to download new version
# 5 - .info says item is unsupported/untested on this arch
{
  local itemid="$1"
  local -a srcfilelist

  VERSION="${INFOVERSION[$itemid]}"
  DOWNLIST="${INFODOWNLIST[$itemid]}"
  MD5LIST="${INFOMD5LIST[$itemid]}"
  DOWNDIR="${SRCDIR[$itemid]}"

  # Quick checks:
  # if the item doesn't need source, return 0
  [ -z "$DOWNLIST" -o -z "$DOWNDIR" ] && return 0
  # if unsupported/untested, return 5
  [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ] && \
    { log_warning -n "$itemid is $DOWNLIST on $SR_ARCH"; return 5; }
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
    # check files in this dir only (arch-specific subdirectories may exist, ignore them)
    IFS=$'\n'; srcfilelist=( $(find . -maxdepth 1 -type f -print 2>/dev/null| grep -v '^\./\.version$' | sed 's:^\./::') ); unset IFS
    numgot=${#srcfilelist[@]}
    numwant=$(echo $DOWNLIST | wc -w)
    # no files, empty directory => return 3 (same as no directory)
    [ $numgot = 0 ] && return 3
    # or if we have not got the right number of sources, return 2
    [ $numgot != $numwant ] && { log_verbose -a "Note: need $numwant source files, but have $numgot"; return 2; }
    # if we're ignoring the md5sums, we've finished => return 0
    [ "${HINT_md5ignore[$itemid]}" = 'y' ] && return 0
    # run the md5 check on all the files (don't give up at the first error)
    allok='y'
    for f in "${srcfilelist[@]}"; do
      mf=$(md5sum "$f" | sed 's/ .*//')
      ok='n'
      # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
      for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
      [ "$ok" = 'y' ] || { log_verbose -a "Note: failed md5sum: $f"; allok='n'; }
    done
    [ "$allok" = 'y' ] || { return 1; }
  )
  return $?  # status comes directly from subshell
}

#-------------------------------------------------------------------------------

function download_src
# Download sources into the source cache
# No arguments -- uses $DOWNDIR, $DOWNLIST and $VERSION previously set by verify_src
# Return status:
# 1 - curl failed
{

  if [ -n "$DOWNDIR" ]; then
    mkdir -p "$DOWNDIR"
    find "$DOWNDIR" -maxdepth 1 -type f -exec rm {} \;
  else
    return 0
  fi

  if [ -z "$DOWNLIST" ]; then
    # stamp the source cache directory with a .version file even though there are no sources
    echo "$VERSION" > "$DOWNDIR"/.version
    return 0
  fi

  log_normal -a "Downloading source files ..."
  ( cd "$DOWNDIR"
    for url in $DOWNLIST; do
      curl -q -f '-#' -k --connect-timeout 60 --retry 5 -J -L -A SlackZilla -O $url >> "$ITEMLOG" 2>&1
      curlstat=$?
      if [ $curlstat != 0 ]; then
        log_error -a "Download failed: $(print_curl_status $curlstat). $url"
        return 1
      fi
    done
    echo "$VERSION" > "$DOWNDIR"/.version
    # curl content-disposition can't undo %-encoding.
    # %20 -> space seems to be the most common problem:
    for spacetrouble in $(ls *%20* 2>/dev/null); do
      mv "$spacetrouble" "$(echo "$spacetrouble" | sed 's/\%20/ /g')"
    done
  )
  return 0
}

#-------------------------------------------------------------------------------

function print_curl_status
# Print a friendly error message for curl status code on standard output
# $1 = curl status code
# Return status: always 0
{
  case $1 in
  1)   echo "Unsupported protocol" ;;
  2)   echo "Failed to initialize" ;;
  3)   echo "URL malformed" ;;
  4)   echo "A feature or option that was needed to perform the desired request was not enabled or was explicitly disabled at build-time" ;;
  5)   echo "Couldn't resolve proxy" ;;
  6)   echo "Couldn't resolve host" ;;
  7)   echo "Failed to connect to host" ;;
  8)   echo "FTP weird server reply" ;;
  9)   echo "FTP access denied" ;;
  11)  echo "FTP weird PASS reply" ;;
  13)  echo "FTP weird PASV reply, Curl couldn't parse the reply sent to the PASV request" ;;
  14)  echo "FTP weird 227 format" ;;
  15)  echo "FTP can't get host" ;;
  17)  echo "FTP couldn't set binary" ;;
  18)  echo "Partial file" ;;
  19)  echo "FTP couldn't download/access the given file, the RETR (or similar) command failed" ;;
  21)  echo "FTP quote error" ;;
  22)  echo "HTTP page not retrieved" ;;
  23)  echo "Write error" ;;
  25)  echo "FTP couldn't STOR file" ;;
  26)  echo "Read error" ;;
  27)  echo "Out of memory" ;;
  28)  echo "Operation timeout" ;;
  30)  echo "FTP PORT failed" ;;
  31)  echo "FTP couldn't use REST" ;;
  33)  echo "HTTP range error" ;;
  34)  echo "HTTP post error" ;;
  35)  echo "SSL connect error" ;;
  36)  echo "FTP bad download resume" ;;
  37)  echo "FILE couldn't read file" ;;
  38)  echo "LDAP cannot bind" ;;
  39)  echo "LDAP search failed" ;;
  41)  echo "Function not found" ;;
  42)  echo "Aborted by callback" ;;
  43)  echo "Internal error" ;;
  45)  echo "Interface error" ;;
  47)  echo "Too many redirects" ;;
  48)  echo "Unknown option specified to libcurl" ;;
  49)  echo "Malformed telnet option" ;;
  51)  echo "The peer's SSL certificate or SSH MD5 fingerprint was not OK" ;;
  52)  echo "The server didn't reply anything, which here is considered an error" ;;
  53)  echo "SSL crypto engine not found" ;;
  54)  echo "Cannot set SSL crypto engine as default" ;;
  55)  echo "Failed sending network data" ;;
  56)  echo "Failure in receiving network data" ;;
  58)  echo "Problem with the local certificate" ;;
  59)  echo "Couldn't use specified SSL cipher" ;;
  60)  echo "Peer certificate cannot be authenticated with known CA certificates" ;;
  61)  echo "Unrecognized transfer encoding" ;;
  62)  echo "Invalid LDAP URL" ;;
  63)  echo "Maximum file size exceeded" ;;
  64)  echo "Requested FTP SSL level failed" ;;
  65)  echo "Sending the data requires a rewind that failed" ;;
  66)  echo "Failed to initialise SSL Engine" ;;
  67)  echo "The user name, password, or similar was not accepted and curl failed to log in" ;;
  68)  echo "File not found on TFTP server" ;;
  69)  echo "Permission problem on TFTP server" ;;
  70)  echo "Out of disk space on TFTP server" ;;
  71)  echo "Illegal TFTP operation" ;;
  72)  echo "Unknown TFTP transfer ID" ;;
  73)  echo "File already exists (TFTP)" ;;
  74)  echo "No such user (TFTP)" ;;
  75)  echo "Character conversion failed" ;;
  76)  echo "Character conversion functions required" ;;
  77)  echo "Problem with reading the SSL CA cert (path? access rights?)" ;;
  78)  echo "The resource referenced in the URL does not exist" ;;
  79)  echo "An unspecified error occurred during the SSH session" ;;
  80)  echo "Failed to shut down the SSL connection" ;;
  82)  echo "Could not load CRL file, missing or wrong format (added in 7" ;;
  83)  echo "Issuer check failed (added in 7" ;;
  84)  echo "The FTP PRET command failed" ;;
  85)  echo "RTSP: mismatch of CSeq numbers" ;;
  86)  echo "RTSP: mismatch of Session Identifiers" ;;
  87)  echo "unable to parse FTP file list" ;;
  88)  echo "FTP chunk callback reported error" ;;
  89)  echo "No connection available, the session will be queued " ;;
  *)   echo "curl status $curlstat" ;;
  esac
  return 0
}
