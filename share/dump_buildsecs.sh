#!/bin/sh
# Copyright 2017 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# dump_buildsecs.sh
#   Retrieve actual build times from a slackrepo database and format them as sql
#   for initial loading into another database.
#
# $1  repo name (default = SBo)
# $2  arch (default = host's arch)
# $3  path to existing database file (default = "the obvious place")
# $4  path of sql file to create (default = /tmp/${REPO}_buildsecs_${MARCH}.sql)
#
# Note: these things are *not* found via the usual slackrepo config files and
#       environment variables.
#-------------------------------------------------------------------------------

REPO="${1:-SBo}"
MARCH="${2:-$(uname -m)}"
DATABASE="${3:-/var/lib/slackrepo/${REPO}/database_${REPO}_${MARCH}.sqlite3}"
DUMPFILE="${4:-/tmp/${REPO}_buildsecs_${MARCH}.sql}"
Query="select 'insert or ignore into buildsecs(itemid,secs,mhzsum,guessflag) values (''',itemid,''',''',secs,''',''',mhzsum,''',''~'');' from buildsecs where guessflag='=' order by itemid asc;"

if [ ! -f "${DATABASE}" ]; then
  echo "Database not found: ${DATABASE}" >&2
  exit 1
fi

echo "begin transaction;" > "${DUMPFILE}"
echo -e ".separator ''\n${Query}" | sqlite3 "${DATABASE}" | \
  while read sqlrow; do
    itemid=$(echo "$sqlrow" | sed -e "s/.* values ('//" -e "s/'.*//")
    if [ -d "$(dirname "$DATABASE")/slackbuilds/$itemid" ]; then
      echo "$sqlrow" >> "${DUMPFILE}"
    else
      echo "Omitting removed item: $itemid"
    fi
  done
echo "commit;" >> "${DUMPFILE}"

echo "$(grep -c ' values ' "${DUMPFILE}") rows written to ${DUMPFILE}"

exit 0
