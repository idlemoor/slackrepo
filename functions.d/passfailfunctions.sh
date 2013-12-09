#!/bin/bash
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# passfailfunctions.sh - pass and fail functions for sboggit:
#   itpassed
#   itfailed
#-------------------------------------------------------------------------------

function itpassed
{
  local p="${1:-$prg}"
  c=$(cd $SB_REPO/*/$p/..; basename $(pwd))
  # this won't delete everything, but it's good enough:
  rm -rf $TMP/${p}* $TMP/package-${p}
  find $SB_REPO/$c/$p/ -type l -exec rm {} \;
  # If the SlackBuild directory was clean, stamp the output with the git revision
  gitrev=$(git log -n 1 --format=format:%h $SB_REPO/$category/$prg)
  if [ -z "$(cd $SB_REPO/$c/$p; git status -s .)" ]; then
    git log -n 1 $SB_REPO/$category/$prg > $OUTPUT/gitrev-$gitrev
  elif [ -f "$SB_HINTS/$p.tar.gz" ]; then
    tarmd5=$(md5sum $SB_HINTS/$p.tar.gz | sed 's/ .*//')
    echo "gitrev $gitrev $SB_HINTS/$p.tar.gz $tarmd5" > $OUTPUT/gitrev-$gitrev-targz-$tarmd5
    git reset --hard
  else
    echo "$(cd $SB_REPO/$c/$p; git status .)" > $OUTPUT/gitrev-$gitrev+dirty
    git reset --hard
  fi
  echo_green ":-) PASS (-: $c/$p $gitrev"
  echo "$c/$p" >> $SB_LOGDIR/PASSLIST
  mv $SB_LOGDIR/$p.log $SB_LOGDIR/PASS/
}

#-------------------------------------------------------------------------------

function itfailed
{
  local p="${1:-$prg}"
  c=$(cd $SB_REPO/*/$p/..; basename $(pwd))
  echo_red ":-( FAIL )-: $c/$p"
  grep -q "^$c/$p\$" $SB_LOGDIR/FAILLIST || echo $c/$p >> $SB_LOGDIR/FAILLIST
  # leave the wreckage in $TMP for investigation
  if [ -f $SB_LOGDIR/$p.log ]; then
    mv $SB_LOGDIR/$p.log $SB_LOGDIR/FAIL/$p.log
    echo_red "See $SB_LOGDIR/FAIL/$p.log"
  fi
  find $SB_REPO/$c/$p/ -type l -exec rm {} \;
}
