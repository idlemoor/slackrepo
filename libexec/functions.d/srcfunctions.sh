#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# srcfunctions.sh - source functions for slackrepo
#   verify_src
#   download_src
#   print_curl_status
#   print_wget_status
#-------------------------------------------------------------------------------

function verify_src
# Verify item's source files in the source cache
# $1 = itemid
# $2 = (optional) logging level (default="log_important")
#      This allows us to log errors after retrying the download
#      and to log warnings when we're doing a lint :D
# Return status:
# 0 - all files passed, or md5/sha256sum check suppressed, or DOWNLIST is empty
# 1 - one or more files had a bad md5sum or sha256sum
# 2 - no. of files != no. of md5sums or sha256sums
# 3 - directory not found or empty => not in source cache, need to download
# 4 - version mismatch, need to download new version
# 5 - .info says item is unsupported/untested on this arch
# 6 - not in source cache and there is a nodownload hint
{
  local itemid="$1"
  local loglevel="${2:-log_important}"
  local -a srcfilelist

  VERSION="${INFOVERSION[$itemid]}"
  DOWNLIST="${INFODOWNLIST[$itemid]}"
  MD5LIST="${INFOMD5LIST[$itemid]}"
  SHA256LIST="${INFOSHA256LIST[$itemid]}"
  DOWNDIR="${SRCDIR[$itemid]}"

  # Quick checks:
  # if the item doesn't need source, return 0
  [ -z "$DOWNLIST" -o -z "$DOWNDIR" ] && return 0
  # if unsupported/untested, return 5
  [ "$DOWNLIST" = "UNSUPPORTED" -o "$DOWNLIST" = "UNTESTED" ] && return 5
  # if no directory, return 6 (nodownload hint) or 3 (source not found)
  [ ! -d "$DOWNDIR" -a -n "${HINT_NODOWNLOAD[$itemid]}" ] && return 6
  [ ! -d "$DOWNDIR" ] && return 3

  # More complex checks:

  # if wrong version, return 6 (nodownload hint) or 4 (version mismatch)
  if [ -f "$DOWNDIR"/.version ]; then
    if [ "$VERSION" != "$(cat "$DOWNDIR"/.version)" ]; then
      if [ "$CMD" != 'lint' ]; then
        log_normal -a "Removing old source files ... "
        find "$DOWNDIR" -maxdepth 1 -type f -exec rm -f {} \;
        log_done
      fi
      [ -n "${HINT_NODOWNLOAD[$itemid]}" ] && return 6
      return 4
    fi
  fi

  # check files in this dir only (arch-specific subdirectories may exist, ignore them)
  readarray -t srcfilelist < <(find "$DOWNDIR" -maxdepth 1 -type f \! -name .version -print 2>/dev/null)
  numgot=${#srcfilelist[@]}
  # no files, empty directory => return 3 (same as no directory) or 6
  [ $numgot = 0 -a -n "${HINT_NODOWNLOAD[$itemid]}" ] && return 6
  [ $numgot = 0 ] && return 3
  # or if we have not got the right number of sources, return 2 (or 6)
  numwant=$(echo "$DOWNLIST" | wc -w)
  if [ "$numgot" != "$numwant" ]; then
    ${loglevel} -a "${itemid}: Found ${numgot} source file(s), but ${numwant} required"
    [ -n "${HINT_NODOWNLOAD[$itemid]}" ] && return 6
    return 2
  fi

  # if we're ignoring the md5sums and sha256sums, we've finished! => return 0
  [ "${HINT_MD5IGNORE[$itemid]}" = 'y' -a "${HINT_SHA256IGNORE[$itemid]}" = 'y' ] && return 0

  # run the md5 and/or sha256 check on all the files (don't give up at the first error)
  log_normal -a "Verifying source files ... "
  allok='y'
  if [ "${HINT_MD5IGNORE[$itemid]}" != 'y' -a -n "$MD5LIST" ]; then
    for f in "${srcfilelist[@]}"; do
      mf=$(md5sum "$f"); mf="${mf/ */}"
      ok='n'
      # The next bit checks all files have a good md5sum, but not vice versa, so it's not perfect :-/
      for minfo in $MD5LIST; do if [ "$mf" = "$minfo" ]; then ok='y'; break; fi; done
      [ "$ok" = 'y' ] || { ${loglevel} -a "${itemid}: Failed md5sum: $(basename "$f")"; log_info -a "  actual md5sum is $mf"; allok='n'; }
    done
  fi
  if [ "${HINT_SHA256IGNORE[$itemid]}" != 'y' -a -n "$SHA256LIST" ]; then
    for f in "${srcfilelist[@]}"; do
      sf=$(sha256sum "$f"); sf="${sf/ */}"
      ok='n'
      # The next bit checks all files have a good sha256sum, but not vice versa, so it's not perfect :-/
      for sinfo in $SHA256LIST; do if [ "$sf" = "$sinfo" ]; then ok='y'; break; fi; done
      [ "$ok" = 'y' ] || { ${loglevel} -a "${itemid}: Failed sha256sum: $(basename "$f")"; log_info -a "  actual sha256sum is $sf"; allok='n'; }
    done
  fi
  if [ "$allok" = 'y' ]; then
    log_done
  else
    [ -n "${HINT_NODOWNLOAD[$itemid]}" ] && return 6
    return 1
  fi

  return 0
}

#-------------------------------------------------------------------------------

function download_src
# Download sources into the source cache
# No arguments -- uses $DOWNDIR, $DOWNLIST and $VERSION previously set by verify_src
# Return status:
# 1 - download failed
{
  if [ -n "$DOWNDIR" ]; then
    mkdir -p "$DOWNDIR"
    find -H "$DOWNDIR" -maxdepth 1 -type f -exec rm -f {} \;
  else
    return 0
  fi

  if [ -z "$DOWNLIST" ]; then
    # stamp the source cache directory with a .version file even though there are no sources
    echo "$VERSION" > "$DOWNDIR"/.version
    return 0
  fi

  wgetprogress='--quiet --progress=bar:force'
  [ "$OPT_VERBOSE" = 'y' ]  && wgetprogress='--progress=bar:force'
  [ "$SYS_CURRENT" = 'y' ] && wgetprogress="${wgetprogress}:noscroll --show-progress"

  log_normal -a "Downloading source files ..."
  cd "$DOWNDIR"
  for url in $DOWNLIST; do
    wgetstat=0
    set -o pipefail
    wget --timeout=30 --tries=4 $wgetprogress --no-check-certificate --content-disposition -U slackrepo "$url" 2>&41
    wgetstat=$?
    set +o pipefail
    if [ $wgetstat != 0 ]; then
      # Try SlackBuilds Direct :D quietly ;-)
      sbdurl="https://sourceforge.net/projects/slackbuildsdirectlinks/files/${ITEMPRGNAM[$itemid]}/${url##*/}"
      set -o pipefail
      wget --timeout=30 --tries=4 $wgetprogress --no-check-certificate --content-disposition -U slackrepo "$url" 2>&41
      sbdstat=$?
      set +o pipefail
      if [ $sbdstat != 0 ]; then
        # use the original url and status in the error message
        [ "$wgetstat" != 0 ] && failmsg="$(print_wget_status $wgetstat)"
        if [ "$CMD" = 'lint' ]; then
          log_warning -a "${itemid}: Download failed: ${failmsg}."
          log_info -a "$url"
        else
          log_error -a "Download failed: ${failmsg}.\n  $url"
        fi
        cd - >/dev/null
        return 1
      fi
      log_info -a "Downloaded from SlackBuilds Direct Links: ${url##*/}"
    fi
  done
  echo "$VERSION" > "$DOWNDIR"/.version
  cd - >/dev/null
  return 0
}

#-------------------------------------------------------------------------------

function print_curl_status
# Print a friendly error message for curl status code on standard output
# http://curl.haxx.se/docs/manpage.html#EXIT
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
  '')  echo "curl status is null" ;;
  *)   echo "curl status $1" ;;
  esac
  return 0
}

#-------------------------------------------------------------------------------

function print_wget_status
# Print a friendly error message for wget status code on standard output
# https://www.gnu.org/software/wget/manual/wget.html#Exit-Status
# $1 = wget status code
# Return status: always 0
{
  case $1 in
  1)   echo "Generic error code" ;;
  2)   echo "Parse error - for instance, when parsing command-line options or .wgetrc or .netrc" ;;
  3)   echo "File I/O error" ;;
  4)   echo "Network failure" ;;
  5)   echo "SSL verification failure" ;;
  6)   echo "Username/password authentication failure" ;;
  7)   echo "Protocol errors" ;;
  8)   echo "Server issued an error response" ;;
  '')  echo "wget status is null" ;;
  *)   echo "wget status $1" ;;
  esac
  return 0
}
