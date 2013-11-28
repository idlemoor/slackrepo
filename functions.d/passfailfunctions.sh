#!/bin/bash
#-------------------------------------------------------------------------------
# passfailfunctions.sh - pass and fail functions for SBoggit:
#   itpassed
#   itfailed
#
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#-------------------------------------------------------------------------------

function itpassed
{
  local p="${1:-$prg}"
  c=$(cd $SBOREPO/*/$p/..; basename $(pwd))
  # this won't delete everything, but it's good enough:
  rm -rf $TMP/${p}* $TMP/package-${p}
  find $SBOREPO/$c/$p/ -type l -exec rm {} \;
  # If the SlackBuild directory was clean, stamp the output with the git revision
  gitrev=$(git log -n 1 --format=format:%h $SBOREPO/$category/$prg)
  if [ -z "$(cd $SBOREPO/$c/$p; git status -s .)" ]; then
    git log -n 1 $SBOREPO/$category/$prg > $OUTPUT/gitrev-$gitrev
  elif [ -f "$HINTS/$p.tar.gz" ]; then
    tarmd5=$(md5sum $HINTS/$p.tar.gz | sed 's/ .*//')
    echo "gitrev $gitrev $HINTS/$p.tar.gz $tarmd5" > $OUTPUT/gitrev-$gitrev-targz-$tarmd5
    git reset --hard
  else
    echo "$(cd $SBOREPO/$c/$p; git status .)" > $OUTPUT/gitrev-$gitrev+dirty
    git reset --hard
  fi
  echogreen ":-) PASS (-: $c/$p $prgrev"
  echo "$c/$p" >> $LOGDIR/PASSLIST
  mv $LOGDIR/$p.log $LOGDIR/PASS/
}

#-------------------------------------------------------------------------------

function itfailed
{
  local p="${1:-$prg}"
  c=$(cd $SBOREPO/*/$p/..; basename $(pwd))
  echored ":-( FAIL )-: $c/$p"
  grep -q "^$c/$p\$" $LOGDIR/FAILLIST || echo $c/$p >> $LOGDIR/FAILLIST
  # leave the wreckage in $TMP for investigation
  if [ -f $LOGDIR/$p.log ]; then
    mv $LOGDIR/$p.log $LOGDIR/FAIL/$p.log
    echored "See $LOGDIR/FAIL/$p.log"
  fi
  find $SBOREPO/$c/$p/ -type l -exec rm {} \;
}
