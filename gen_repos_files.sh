#!/bin/bash
# Copyright (c) 2006-2014  Eric Hameleers, Eindhoven, The Netherlands
# All rights reserved.
#
#   Permission to use, copy, modify, and distribute this software for
#   any purpose with or without fee is hereby granted, provided that
#   the above copyright notice and this permission notice appear in all
#   copies.
#
#   THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESSED OR IMPLIED
#   WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#   MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#   IN NO EVENT SHALL THE AUTHORS AND COPYRIGHT HOLDERS AND THEIR
#   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
#   USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
#   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
#   OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#   SUCH DAMAGE.
# ---------------------------------------------------------------------------
#
# Generate the PACKAGES.TXT FILELIST.TXT and CHECKSUMS.md5 files,
#   needed by 3rd-party Slackware package management tools.
#
# Eric Hameleers <alien@slackware.com>
# ---------------------------------------------------------------------------
cat <<"EOT"
# -------------------------------------------------------------------#
# $Id: gen_repos_files.sh,v 1.92 2014/07/31 20:27:53 root Exp root $ #
# -------------------------------------------------------------------#
EOT

# The script's basename will be displayed in the RSS feed:
BASENAME=$( basename $0 )

# The script'""s revision number will be displayed in the RSS feed:
REV=$( echo "$Revision: 1.92 $" | cut -d' '  -f2 )

# The repository owner's defaults file;
# you can override any of the default values in this file:
USERDEFS=${USERDEFS:-~/.genreprc}

# ---------------------------------------------------------------------------
# Sane defaults:

# The directory of the Slackware package repository:
REPOSROOT=${REPOSROOT:-"/home/www/sox/slackware/slackbuilds/"}

# Repository maintainer
REPOSOWNER=${REPOSOWNER:-"Eric Hameleers <alien@slackware.com>"}

# The GPG key for the repository owner can contain a different string than
# the value of $REPOSOWNER . If you leave $REPOSOWNERGPG empty, the script will
# use the value you've set for $REPOSOWNER instead to search the GPG keyfile.
REPOSOWNERGPG=${REPOSOWNERGPG:-""}

# Under what URL is the repository accessible:
DL_URL=${DL_URL:-""}

# The title of the generated RSS feed:
RSS_TITLE=${RSS_TITLE:-"Alien's Slackware packages"}

# The logo picture used for the RSS feed:
RSS_ICON=${RSS_ICON:-"http://www.slackware.com/~alien/graphics/blueorb.png"}

# The URL linked to when clicking on the logo:
RSS_LINK=${RSS_LINK:-"http://www.slackware.com/~alien/"}

# URL to the full changelog.txt:
RSS_CLURL=${RSS_CLURL:-"http://www.slackware.com/~alien/slackbuilds/ChangeLog.txt"}

# The descriptive text for the RSS feed:
RSS_DESCRIPTION=${RSS_DESCRIPTION:-"Eric Hameleers (alien's) Slackware package repository. The package directories include the SlackBuild script and sources."}

# Maximum number of RSS feed entries to display:
RSS_FEEDMAX=${RSS_FEEDMAX:-15}

# The RSS generator must use a unique feed identifier.
# Generate one for your feed by using the string returned by "uuidgen -t":
RSS_UUID=${RSS_UUID:-""}

# Either use gpg or gpg2:
GPGBIN=${GPGBIN:-"/usr/bin/gpg"}

# Optionally use gpg-agent to cache the gpg passphrase instead of letting the
# script keep it in the environment (note that if you define USE_GPGAGENT=1
# but gpg-agent is not running, you will get prompted for a passphrase every
# single time gpg runs):
USE_GPGAGENT=${USE_GPGAGENT:-0}

# Generate slack-requires, slack-suggests, and slack-conflicts lines in the
# metadata files by setting FOR_SLAPTGET to "1" -- these are used by slapt-get 
FOR_SLAPTGET=${FOR_SLAPTGET:-0}

# Follow symlinks in case the repository has symlinks like 14.0 -> 13.37
# indicating that one package works for those two Slackware releases.
# If the script does _not_ follow symlinks, then the symlinks will appear in
# the repository listing instead of the packages they point to.
FOLLOW_SYMLINKS=${FOLLOW_SYMLINKS:-1}

# If the repository has separate package subdirectories (for separate
# Slackware releases or architectures) then define them here.
# Separate FILELIST.TXT, MANIFEST etc.. files will be created for all of them:
REPO_SUBDIRS=${REPO_SUBDIRS:-""}

# If you want to exclude certain directories or files from being included
# in the repository metadata, define them here (space-separated).
# Example: REPO_EXCLUDES="RCS logs .genreprc"
REPO_EXCLUDES=${REPO_EXCLUDES:-""}

# ---------------------------------------------------------------------------

# By default, no debug messages
DEBUG=0

# Timestamp to be used all around the script:
UPDATEDATE="$(LC_ALL=C date -u)"

# A value of "yes" means that .meta .md5 and/or .asc files are
# always (re)generated.
# while "no" means: only generate these files if they are missing.
FORCEMD5="no"    # .md5 files
FORCEPKG="no"    # .meta files
FORCEASC="no"    # .asc files
TOUCHUP="no"     # rsync has issues with files whose content has changed, but
                 # both size and timestamp remain unchanged (needs expensive
                 # '--checksum' to detect these file changes)
# We may have a need to only update the ChangeLog files:
RSSONLY="no"     # ChangeLog .rss and .txt
# For a sub-repository we do not have a ChangeLog:
CHANGELOG="yes"

# Variable used to limit the search for packages which lack .md5/.asc file,
# to those packages changed less than NOTOLDER days ago.
NOTOLDER=""

# Variable used to import the content of a text file as the new ChangeLog.txt
# entry. If empty, you will be asked to type a new entry yourself.
LOGINPUT=""

#
# --- no need to change anything below this line ----------------------------
#

# Import the repository owner's defaults
if [ -f $USERDEFS ]; then
  echo "Importing user defaults."
  . $USERDEFS
fi

# We prevent the mirror from running more than one instance:
PIDFILE=/var/tmp/$(basename $0 .sh).pid

# Make sure the PID file is removed when we kill the process
trap 'rm -f $PIDFILE; exit 1' TERM INT

# Determine the prune parameters for the 'find' commands:
PRUNES=""
if [ -n "$REPO_EXCLUDES" ]; then
  echo "--- Excluding: $REPO_EXCLUDES"
  for substr in $REPO_EXCLUDES ; do
    PRUNES="${PRUNES} -o -name ${substr} -prune "
  done
fi

# Command line parameter processing:
while getopts ":ahl:mn:prstv" Option
do
  case $Option in
    h ) echo "Parameters are:"
        echo "  -h        : This help text"
        echo "  -a        : Force generation of .asc gpg signature files"
        echo "  -l <log>  : Use file <log> as input for ChangeLog.txt"
        echo "  -m        : Force generation of .md5 files"
        echo "  -n <days> : Only look for packages not older than <days> days"
        echo "  -p        : Force generation of package .meta files"
        echo "  -r        : Update ChangeLog TXT and RSS files only"
        echo "  -s        : Sub-repository: does not have ChangeLog TXT or RSS"
        echo "  -t        : Timestamp of metafiles equal to package timestamp"
        echo "  -v        : Verbose messages about packages found"
        exit
        ;;
    a ) FORCEASC="yes"
        ;;
    l ) LOGINPUT="${OPTARG}"
        ;;
    m ) FORCEMD5="yes"
        ;;
    n ) NOTOLDER=${OPTARG}
        ;;
    p ) FORCEPKG="yes"
        ;;
    r ) RSSONLY="yes"
        ;;
    s ) CHANGELOG="no"
        ;;
    t ) TOUCHUP="yes"
        ;;
    v ) DEBUG=1
        ;;
    * ) echo "You passed an illegal switch to the program!"
        echo "Run '$0 -h' for more help."
        exit
        ;;   # DEFAULT
  esac
done

# End of option parsing.
shift $(($OPTIND - 1))
#  $1 now references the first non option item supplied on the command line
#  if one exists.
# ---------------------------------------------------------------------------

#
# --- HELPER FUNCTIONS ------------------------------------------------------
#

#
# pkgcomp
#
function pkgcomp {
  # Return the compression utility used for this package,
  # based on the package's extension.
  # Determine extension:
  PEXT="$( echo $1 | rev | cut -f 1 -d . | rev)"
  # Determine compression used:
  case $PEXT in
  'tgz' )
    COMP=gzip
    ;;
  'tbz' )
    COMP=bzip2
    ;;
  'tlz' )
    COMP=lzma
    ;;
  'txz' )
    COMP=xz
    ;;
  esac
  echo ${COMP:-"gzip"}
}

#
# addpkg
#
function addpkg {
  # -----------------------------------------------
  # Functionality used from the slapt-get FAQ#17 at
  # http://software.jaos.org/BUILD/slapt-get/FAQ :
  # -----------------------------------------------
  # Generate a package's metafile if missing, and add the content of
  # this metafile to the PACKAGES.TXT
  # Argument #1 : full path to a package
  # Argument #2 : full path to PACKAGES.TXT file/

  if [ ! -f "$1" -o ! -f "$2" ]; then
    echo "Required arguments '$1' and/or '$2' are invalid files!"
    exit 1
  fi
  PKG=$1
  PACKAGESFILE=$2

  if [ "$(echo $PKG|grep -E '(.*{1,})\-(.*[\.\-].*[\.\-].*).t[blxg]z[ ]{0,}$')" == "" ];
  then
    return;
  fi

  NAME=$(echo $PKG|sed -re "s/(.*\/)(.*.t[blxg]z)$/\2/")
  LOCATION=$(echo $PKG|sed -re "s/(.*)\/(.*.t[blxg]z)$/\1/")
  METAFILE=${NAME%t[blxg]z}meta
  TXTFILE=${NAME%t[blxg]z}txt

  if [ "$FORCEPKG" == "yes" -o ! -f $LOCATION/$TXTFILE ]; then
    # This is a courtesy service:
    echo "--> Generating .txt file for $NAME"
    $COMPEXE -cd $PKG | tar xOf - install/slack-desc | sed -n '/^#/d;/:/p' > $LOCATION/$TXTFILE
    [ "$TOUCHUP" == "yes"  ] && touch -r $PKG $LOCATION/$TXTFILE || touch -d "$UPDATEDATE" $LOCATION/$TXTFILE
  fi

  if [ "$FORCEPKG" == "yes" -o ! -f $LOCATION/$METAFILE ]; then
    echo "--> Generating .meta file for $NAME"

    # Determine the compression tool used for this package:
    COMPEXE=$( pkgcomp $PKG )

    SIZE=$(du -s $PKG | cut -f 1)

    if [ "$COMPEXE" = "xz" ]; then
      # xz does not support the "-l" switch yet:
      cat $PKG | $COMPEXE -dc | dd 1> /dev/null 2> $HOME/.temp.uncomp.$$
      USIZE="$(expr $(cat $HOME/.temp.uncomp.$$ | head -n 1 | cut -f1 -d+) / 2)"
      rm -f $HOME/.temp.uncomp.$$
    else
      USIZE=$( expr $(gunzip -l $PKG |tail -1|awk '{print $2}') / 1024 )
    fi

    if [ $FOR_SLAPTGET -eq 1 ]; then
      REQUIRED=$($COMPEXE -cd $PKG | tar xOf - install/slack-required 2>/dev/null|tr -d ' '|xargs -r -iZ echo -n "Z,"|sed -e "s/,$//")
      CONFLICTS=$($COMPEXE -cd $PKG | tar xOf - install/slack-conflicts 2>/dev/null|tr -d ' '|xargs -r -iZ echo -n "Z,"|sed -e "s/,$//")
      SUGGESTS=$($COMPEXE -cd $PKG | tar xOf - install/slack-suggests 2>/dev/null|xargs -r )
    fi

    echo "PACKAGE NAME:  $NAME" > $LOCATION/$METAFILE
    if [ -n "$DL_URL" ]; then
      echo "PACKAGE MIRROR:  $DL_URL" >> $LOCATION/$METAFILE
    fi
    echo "PACKAGE LOCATION:  $LOCATION" >> $LOCATION/$METAFILE
    echo "PACKAGE SIZE (compressed):  $SIZE K" >> $LOCATION/$METAFILE
    echo "PACKAGE SIZE (uncompressed):  $USIZE K" >> $LOCATION/$METAFILE
    if [ $FOR_SLAPTGET -eq 1 ]; then
      echo "PACKAGE REQUIRED:  $REQUIRED" >> $LOCATION/$METAFILE
      echo "PACKAGE CONFLICTS:  $CONFLICTS" >> $LOCATION/$METAFILE
      echo "PACKAGE SUGGESTS:  $SUGGESTS" >> $LOCATION/$METAFILE
    fi
    echo "PACKAGE DESCRIPTION:" >> $LOCATION/$METAFILE
    if [ -f $LOCATION/$TXTFILE ]; then
      cat $LOCATION/$TXTFILE >> $LOCATION/$METAFILE
    else
      $COMPEXE -cd $PKG | tar xOf - install/slack-desc | sed -n '/^#/d;/:/p' >> $LOCATION/$METAFILE
    fi
    echo "" >> $LOCATION/$METAFILE
  [ "$TOUCHUP" == "yes"  ] && touch -r $PKG $LOCATION/$METAFILE || touch -d "$UPDATEDATE" $LOCATION/$METAFILE
  fi

  # Package location may have changed:
  sed -e "/^PACKAGE LOCATION: /s,^.*$,PACKAGE LOCATION:  $LOCATION," $LOCATION/$METAFILE >> $PACKAGESFILE

} # end of function 'addpkg'

#
# addman
#
function addman {
  # Add a package's content to the MANIFEST file
  # Argument #1 : full path to a package
  # Argument #2 : full path to MANIFEST file

  if [ ! -f "$1" -o ! -f "$2" ]; then
    echo "Required arguments '$1' and/or '$2' are invalid files!"
    exit 1
  fi
  PKG=$1
  MANIFESTFILE=$2

  if [ "$(echo $PKG|grep -E '(.*{1,})\-(.*[\.\-].*[\.\-].*).t[blxg]z[ ]{0,}$')" == "" ];
  then
    return;
  fi

  NAME=$(echo $PKG|sed -re "s/(.*\/)(.*.t[blxg]z)$/\2/")
  LOCATION=$(echo $PKG|sed -re "s/(.*)\/(.*.t[blxg]z)$/\1/")
  LSTFILE=${NAME%t[blxg]z}lst

  if [ "$FORCEPKG" == "yes" -o ! -f $LOCATION/$LSTFILE ]; then
    echo "--> Generating .lst file for $NAME"

    # Determine the compression tool used for this package:
    COMPEXE=$( pkgcomp $PKG )

    cat << EOF > $LOCATION/$LSTFILE
++========================================
||
||   Package:  $PKG
||
++========================================
EOF

    $COMPEXE -cd $PKG | tar -tvvf - >> $LOCATION/$LSTFILE
    echo "" >> $LOCATION/$LSTFILE
    echo "" >> $LOCATION/$LSTFILE
    [ "$TOUCHUP" == "yes"  ] && touch -r $PKG $LOCATION/$LSTFILE || touch -d "$UPDATEDATE" $LOCATION/$LSTFILE
  fi

  # Compensate for partial pathnames in .lst files found in sub-repos:
  cat $LOCATION/$LSTFILE \
    | sed -e "s%^||   Package:  .*$%||   Package:  $PKG%" \
    >> $MANIFESTFILE
} # end of function 'addman'


#
# genmd5
#
function genmd5 {
  # Generate a package's MD5SUM (*.md5 file) if missing,
  # Argument #1 : full path to a package

  if [ ! -f "$1" ]; then
    echo "Required argument '$1' is an invalid file!"
    exit 1
  fi
  PKG=$1

  NAME=$(echo $PKG|sed -re "s/(.*\/)(.*.t[blxg]z)$/\2/")
  LOCATION=$(echo $PKG|sed -re "s/(.*)\/(.*.t[blxg]z)$/\1/")
  BASE=${NAME%.t[blxg]z}
  MD5FILE=${NAME}.md5

  if [ "$FORCEMD5" == "yes" -o ! -f $LOCATION/$MD5FILE ]; then
    echo "--> Generating .md5 file for $NAME"
    (cd $LOCATION
     md5sum $NAME > $MD5FILE
    )
    [ "$TOUCHUP" == "yes"  ] && touch -r $PKG $LOCATION/$MD5FILE || touch -d "$UPDATEDATE" $LOCATION/$MD5FILE
  fi

} # end of function 'genmd5'


#
# genasc
#
function genasc {
  # Generate a package's GPG signature (*.asc file) if missing,
  # Argument #1 : full path to a package

  if [ ! -f "$1" ]; then
    echo "Required argument '$1' is invalid filename!"
    exit 1
  fi
  PKG=$1

  NAME=$(echo $PKG|sed -re "s/(.*\/)(.*.t[blxg]z)$/\2/")
  LOCATION=$(echo $PKG|sed -re "s/(.*)\/(.*.t[blxg]z)$/\1/")
  ASCFILE=${NAME}.asc

  if [ "$FORCEASC" == "yes" -o ! -f $LOCATION/$ASCFILE ]; then
    echo "--> Generating .asc file for $NAME"
    (cd $LOCATION
     rm -f $ASCFILE
     gpg_sign $NAME
    )
    [ "$TOUCHUP" == "yes"  ] && touch -r $PKG $LOCATION/$ASCFILE || touch -d "$UPDATEDATE" $LOCATION/$ASCFILE
  fi

} # end of function 'genasc'


#
# gen_filelist
#
function gen_filelist {
  # Argument #1 : full path to a directory
  # Argument #2 : output filename (defaults to FILELIST.TXT) will be
  #               created in directory $1 (overwriting existing file).

  if [ ! -d "$1" ]; then
    echo "Required argument '$1' must be a directory!"
    exit 1
  fi
  DIR=$1
  LISTFILE=${2:-FILELIST.TXT}

  ( cd ${DIR}
    cat <<EOT > ${LISTFILE}
$UPDATEDATE

Here is the file list for ${DL_URL:-this directory} ,
maintained by ${REPOSOWNER} .
If you are using a mirror site and find missing or extra files
in the subdirectories, please have the archive administrator
refresh the mirror.

EOT
    if [ $FOLLOW_SYMLINKS -eq 1 ]; then
      find -L . -print $PRUNES | sort | xargs ls -nld --time-style=long-iso >> ${LISTFILE}
    else
      find . -print $PRUNES | sort | xargs ls -nld --time-style=long-iso >> ${LISTFILE}
    fi
  )
} # end of function 'gen_filelist'

#
# upd_changelog
#
function upd_changelog {
  # Update the ChangeLog.txt with a new entry
  # - written at the beginning of the file.
  # Argument #1 : full path to a directory
  # Argument #2 : a filename (defaults to 'ChangeLog.txt')

  if [ ! -d "$1" ]; then
    echo "Required argument '$1' must be an existing directory!"
    exit 1
  fi
  local DIR=$1
  local CHANGELOG=${2:-ChangeLog.txt}
  if [ -e  $DIR/$CHANGELOG -a ! -w $DIR/$CHANGELOG ]; then
    echo "Can not write to file ${DIR}/${CHANGELOG}!"
    exit 1
  fi

  local MAXLINE=78  # Lines will be wrapped at MAXLINE characters.
  local LOGTEXT=""
  local i=0

  if [ "$LOGINPUT" == "" ]; then
    # Ask for a new ChangeLog entry
    read -er -p "Enter ChangeLog.txt description: "
  else
    REPLY=$(cat "$LOGINPUT" 2>/dev/null)
  fi

  if [ "$REPLY" == "" ]; then
    echo "No input, so I won't update your $CHANGELOG"
    return
  fi

  LOGTXT=""
  for WORD in $REPLY ; do
    # The word 'NEWLINE' forces a... newline in the output.
    # The word 'LINEFEED' also signals the start of a new line, but indented.
    if [ "${WORD}" == "NEWLINE" ]; then
      LOGLINE[$i]="$LOGTXT"
      LOGTXT=""
      i=$(( $i+1 ))
    elif [ "${WORD}" == "LINEFEED" ]; then
      LOGLINE[$i]="$LOGTXT"
      LOGTXT="  "
      i=$(( $i+1 ))
    elif [ $(( ${#LOGTXT}+1+${#WORD} )) -gt $MAXLINE ]; then
      LOGLINE[$i]="$LOGTXT"
      LOGTXT="  ${WORD}"   # indent the text two spaces.
      i=$(( $i+1 ))
    else
      [ "$LOGTXT" != "" ] && LOGTXT="${LOGTXT} ${WORD}" || LOGTXT="${WORD}"
    fi
  done
  LOGLINE[$i]="$LOGTXT"

  cat <<-EOT > ${DIR}/.${CHANGELOG}
	+--------------------------+
	$UPDATEDATE
	EOT

  for IND in $(seq 0 $i); do
    echo "${LOGLINE[$IND]}" >> ${DIR}/.${CHANGELOG}
  done
  echo "" >> ${DIR}/.${CHANGELOG}
  if [ -f "${DIR}/${CHANGELOG}" ]; then
    cat ${DIR}/${CHANGELOG} >> ${DIR}/.${CHANGELOG}
  fi
  mv -f  ${DIR}/.${CHANGELOG} ${DIR}/${CHANGELOG}
}

#
# gpg_sign
#
function gpg_sign {
  # Create a gpg signature for a file. Use either gpg or gpg2 and optionally
  # let gpg-agent provide the passphrase.
  if [ $USE_GPGAGENT -eq 1 ]; then
    $GPGBIN --use-agent -bas -u "$REPOSOWNERGPG" --batch --quiet $1
  else
    echo $TRASK | $GPGBIN -bas -u "$REPOSOWNERGPG" --passphrase-fd 0 --batch --quiet $1
  fi
  return $?
}

#
# rss_changelog
#
function rss_changelog {
  # Create a RSS feed out of the ChangeLog.txt
  # Argument #1 : full path to a directory
  # Argument #2 : a filename (defaults to 'ChangeLog.txt')
  # Argument #2 : a filename (defaults to 'ChangeLog.rss')

  if [ ! -d "$1" ]; then
    echo "Required argument '$1' must be an existing directory!"
    exit 1
  fi
  DIR=$1
  INFILE=${DIR}/${2:-ChangeLog.txt}
  RSSFILE=${DIR}/${3:-ChangeLog.rss}
  if [ -e  $RSSFILE -a ! -w $RSSFILE ]; then
    echo "Can not write to RSS file ${RSSFILE}!"
    exit 1
  fi

  # These values are all set in the beginning (can be user-overridden):
  TITLE="$RSS_TITLE"
  LINK="$RSS_LINK"
  ICON="$RSS_ICON"
  CLURL="$RSS_CLURL"
  DESCRIPTION="$RSS_DESCRIPTION"
  FEEDMAX=$RSS_FEEDMAX
  UUID="$RSS_UUID"

  PUBDATE=""
  LASTBUILDDATE=$(LC_ALL=C TZ=GMT date +"%a, %e %b %Y %H:%M:%S GMT")
                 # The 'date -R' RFC-2822 compliant string
                 # does not work for Thunderbird!
  counter=0

  # Parse the input file
  cat ${INFILE} | while IFS= read cline ; do
    if [ "$PUBDATE" == "" ]; then
      # PUBDATE is empty, means we're reading the first line of input.
      # The first line contains the most recent pubdate.
      # For backward compatibility, if the file starts with
      # "+--------------------------+" then we just skip that.
      [ "$cline" == "+--------------------------+" ] && read cline
      PUBDATE=$(LC_ALL=C TZ=GMT date +"%a, %e %b %Y %H:%M:%S GMT" -d "$cline")
      cat <<-_EOT_ > ${RSSFILE}
	<?xml version="1.0" encoding="iso-8859-1"?>
	<rss version="2.0">
	   <channel>
	      <title>${TITLE}</title>
	      <link>${LINK}</link>
	      <image>
	        <title>${TITLE}</title>
	        <url>${ICON}</url>
	        <link>${LINK}</link>
	      </image>
	      <description>${DESCRIPTION}</description>
	      <language>en-us</language>
	      <id xmlns="http://www.w3.org/2005/Atom">urn:uuid:${UUID}</id>
	      <pubDate>${PUBDATE}</pubDate>
	      <lastBuildDate>${LASTBUILDDATE}</lastBuildDate>
	      <generator>${BASENAME} v ${REV}</generator>
	      <item>
	         <title>${PUBDATE}</title>
	         <link>${CLURL}</link>
	         <pubDate>${PUBDATE}</pubDate>
	         <guid isPermaLink="false">$(LC_ALL=C date -d "${PUBDATE}" +%Y%m%d%H%M%S)</guid>
	         <description>
	           <![CDATA[<pre>
	_EOT_
    elif [ "$cline" == "+--------------------------+" ]; then
      # This line masrks the start of a new entry.
      # Only dump a certain amount of recent entries.
      [ $counter -gt $FEEDMAX ] && break

      # Close the previous entry:
      cat <<-_EOT_ >> ${RSSFILE}
	           </pre>]]>
	         </description>
	      </item>
	_EOT_

      # Next line is the pubdate for the next entry:
      read PUBDATE
      PUBDATE=$(LC_ALL=C TZ=GMT date +"%a, %e %b %Y %H:%M:%S GMT" -d "$PUBDATE")

      # Write the header for the next entry:
      cat <<-_EOT_ >> ${RSSFILE}
	      <item>
	         <title>${PUBDATE}</title>
	         <link>${CLURL}</link>
	         <pubDate>${PUBDATE}</pubDate>
	         <guid isPermaLink="false">$(LC_ALL=C date -d "${PUBDATE}" +%Y%m%d%H%M%S)</guid>
	         <description>
	           <![CDATA[<pre>
	_EOT_

      counter=$(( ${counter}+1 ))
    else
      # Add a line of description
      [ "${cline}" != "" ] && echo "${cline}" >> ${RSSFILE}
    fi
  done

  # Close the last entry:
  cat <<-_EOT_ >> ${RSSFILE}
	           </pre>]]>
	         </description>
	      </item>
	_EOT_

  # Close the XML output:
  cat <<-_EOT_ >> ${RSSFILE}
	   </channel>
	</rss>
	_EOT_
}

#
# run_repo
#
run_repo() {
  # Run through a repository tree, generating the repo meta files.

  # Change directory to the root of the repository, so all generated
  # information is relative to here:
  local RDIR=$1

  cd $RDIR

  # Create temporary MANIFEST and PACKAGES.TXT files:
  cat /dev/null > .MANIFEST
  cat /dev/null > .PACKAGES.TXT

  # This tries to look for filenames with the Slackware package name format:
  if [ $FOLLOW_SYMLINKS -eq 1 ]; then
    PKGS=$( find -L . -type f -name '*-*-*-*.t[blxg]z' -print $PRUNES | sort )
  else
    PKGS=$( find . -type f -name '*-*-*-*.t[blxg]z' -print $PRUNES | sort )
  fi
  for pkg in $PKGS; do
    # Found a filename with matching format, is it really a slackpack?
    COMPEXE=$( pkgcomp $pkg )
    if $COMPEXE -cd $pkg | tar tOf - install/slack-desc 1>/dev/null 2>&1 ; then
      [ $DEBUG -eq 1 ] && echo "+++ Found package $pkg"
      # We need to run addpkg for every package, to populate PACKAGES.TXT:
      addpkg $pkg ${RDIR}/.PACKAGES.TXT

      # We need to run addman for every package, to populate MANIFEST
      addman $pkg ${RDIR}/.MANIFEST

      if [ "x$NOTOLDER" != "x" ]; then
        # When to generate md5sum/gpg signature if we have a $NOTOLDER value:
        # 'date +%s' gives the current time in seconds since the Epoch;
        # 'stat -c %Z $pkg' gives the ctime of $pkg file in seconds since Epoch;
        # The difference of these two divided by 3600 is the file age in hours.
        # '24 * $NOTOLDER' gives the maximum allowed age of the file in hours.
        # If the package is too old, we do not try to create md5sum/gpg sig.
        if [ $(( ( $(LC_ALL=C date +%s) - $(stat -c %Z $pkg) ) / 3600 )) -lt $(( 24 * $NOTOLDER )) ]; then
          [ "$USEGPG" == "yes" ] && genasc $pkg
          genmd5 $pkg
        else
          [ $DEBUG -eq 1 ] && echo "  - Skipping md5/gpg calculation for $(basename $pkg)"
        fi
      else
        [ "$USEGPG" == "yes" ] && genasc $pkg
        genmd5 $pkg
      fi
    else
      echo "*** Warning: $pkg does not contain a slack-desc file. ***"
    fi
  done

  # Make the changes visible:
  echo "PACKAGES.TXT;  $UPDATEDATE" > PACKAGES.TXT
  echo "" >> PACKAGES.TXT
  if [ -n "$DL_URL" ]; then
    cat .PACKAGES.TXT >> PACKAGES.TXT
  else
    cat .PACKAGES.TXT | grep -v "PACKAGE MIRROR: " >> PACKAGES.TXT
  fi
  rm -f .PACKAGES.TXT
  cat .MANIFEST > MANIFEST
  rm -f .MANIFEST
  
  bzip2 -9f MANIFEST
  gzip -9cf PACKAGES.TXT > PACKAGES.TXT.gz
  if [ "${CHANGELOG}" == "yes" -a -f ChangeLog.txt ]; then
    gzip -9cf ChangeLog.txt > ChangeLog.txt.gz
  fi

} # End run_repo()


#
# gen_checksums
#
gen_checksums() {
  # Run through a repository tree, generating the checksum files.

  # Change directory to the root of the repository, so all generated
  # information is relative to here:
  local RDIR=$1

  cd $RDIR

  # Create temporary CHECKSUMS.md5 file:
  cat /dev/null > .CHECKSUMS.md5

  # Generate the overall CHECKSUMS.md5 for this (sub-)repo:
  cat << EOF > .CHECKSUMS.md5
These are the MD5 message digests for the files in this directory.
If you want to test your files, use 'md5sum' and compare the values to
the ones listed here.

To test all these files, use this command:

tail +13 CHECKSUMS.md5 | md5sum --check | less

'md5sum' can be found in the GNU coreutils package on ftp.gnu.org in
/pub/gnu, or at any GNU mirror site.

MD5 message digest                Filename
EOF
  if [ $FOLLOW_SYMLINKS -eq 1 ]; then
    find -L . -type f -print $PRUNES | grep -v CHECKSUMS | sort | xargs md5sum $1 2>/dev/null >> .CHECKSUMS.md5
  else
    find . -type f -print $PRUNES | grep -v CHECKSUMS | sort | xargs md5sum $1 2>/dev/null >> .CHECKSUMS.md5
  fi
  cat .CHECKSUMS.md5 > CHECKSUMS.md5
  gzip -9cf CHECKSUMS.md5 > CHECKSUMS.md5.gz

  rm -f .CHECKSUMS.md5 CHECKSUMS.md5.asc CHECKSUMS.md5.gz.asc

  if [ "$USEGPG" == "yes" ]; then
    # The CHECKSUMS.md5* files need a gpg signature:
    gpg_sign CHECKSUMS.md5
    gpg_sign CHECKSUMS.md5.gz
  fi

} # End gen_checksums()


#
# --- MAIN ------------------------------------------------------------------
#

# Abort if we need to create the RSS file and RSS_UUID is empty:
if [ -z "${RSS_UUID}" -a "${CHANGELOG}" = "yes" ]; then
  echo "**"
  echo "** Please supply a value for the Universally Unique IDentifier (UUID) !"
  echo "** Look for the RSS_UUID variable inside the script or in '$USERDEFS',"
  echo "** and (for instance) use the return value from command 'uuidgen -t'."
  echo "**"
  exit 1
fi

echo "--- Generating repository metadata for $REPOSROOT ---"
echo "--- Repository owner is $REPOSOWNER ---"
echo ""

# If the GPG key contains a different identification string than the name
#  you want to use for the repository owner, set the REPOSOWNERGPG variable.
# If $REPOSOWNERGPG has an empty value we will use the value of $REPOSOWNER
#  to search the GPG keyring.
if [ "x${REPOSOWNERGPG}" == "x" ]; then
  REPOSOWNERGPG="${REPOSOWNER}"
fi

# We will test correctness of the GPG passphrase against a temp file:
TESTTMP=$(mktemp)

if [ "${CHANGELOG}" == "yes" ]; then
  # Update ChangeLog.txt with a new entry
  upd_changelog $REPOSROOT
  # Write a RSS file for the ChangeLog.txt
  rss_changelog $REPOSROOT
fi

# If we only want to update the ChangeLog files, then we skip a lot:
if [ "$RSSONLY" = "yes" ]; then
  echo "--- Exiting after re-generation of ChangeLog files (requested). ---"
  echo ""
else
  # Only generate GPG signatures if we have a GPG key
  if ! $GPGBIN --list-secret-keys "$REPOSOWNERGPG" >/dev/null 2>&1 ; then
    USEGPG="no"
    echo "The GPG private key for \"$REPOSOWNERGPG\" wasn't found!"
    echo "*** packages will not be signed! ***"
    read -er -p "Continue? [y|N] " 
    [ "${REPLY:0:1}" = "y" -o "${REPLY:0:1}" = "Y" ] || exit 1
  else
    USEGPG="yes"
    if [ $USE_GPGAGENT -eq 0 ]; then
      read -ers -p "Enter your GPG passphrase: "
      TRASK=$REPLY
      echo "."
      if [ "$REPLY" == "" ]; then
        echo "Empty GPG passphrase - disabling generation of signatures."
        USEGPG="no"
      fi
    fi
  fi

  if [ "$USEGPG" == "yes" ]; then
    gpg_sign $TESTTMP 2>/dev/null
    if [ $? -ne 0 ]; then
      echo "GPG test failed, incorrect GPG passphrase? Aborting the script."
      rm -f $TESTTMP
      exit 1
    else
      if [ ! -r ${REPOSROOT}/GPG-KEY ]; then
        echo "Generating a "GPG-KEY" file in '$REPOSROOT',"
        echo "  containing the public key information for '$REPOSOWNERGPG'..."
        $GPGBIN --list-keys "$REPOSOWNERGPG" > ${REPOSROOT}/GPG-KEY
        $GPGBIN -a --export "$REPOSOWNERGPG" >> ${REPOSROOT}/GPG-KEY
        chmod 444 ${REPOSROOT}/GPG-KEY
      fi
      if [ -n "$REPO_SUBDIRS" ]; then
        for SUBDIR in $REPO_SUBDIRS ; do
          if [ ! -r ${REPOSROOT}/${SUBDIR}/GPG-KEY ]; then
            echo "Generating a "GPG-KEY" file in '$REPOSROOT/$SUBDIR',"
            echo "  containing the public key information for '$REPOSOWNERGPG'."
            $GPGBIN --list-keys "$REPOSOWNERGPG" > $REPOSROOT/$SUBDIR/GPG-KEY
            $GPGBIN -a --export "$REPOSOWNERGPG" >> $REPOSROOT/$SUBDIR/GPG-KEY
            chmod 444 ${REPOSROOT}/${SUBDIR}/GPG-KEY
          fi
        done
      fi
    fi
  fi

  # Run through the repository, generating the MANIFEST etc:
  if [ -n "$REPO_SUBDIRS" ]; then
    echo "--- Populating repo subdirectories '${REPO_SUBDIRS}' ---"
    for SUBDIR in $REPO_SUBDIRS ; do
      run_repo $REPOSROOT/$SUBDIR
      gen_filelist ${REPOSROOT}/$SUBDIR
      gen_checksums ${REPOSROOT}/$SUBDIR
    done
  fi
  run_repo $REPOSROOT

fi # end !RSSONLY

# Finally, generate the FILELIST.TXT and CHECKSUMS.md5* for the whole repo:
gen_filelist ${REPOSROOT}
gen_checksums ${REPOSROOT}

# Clean up:
TRASK=""
rm -f ${TESTTMP}*

# Done.
