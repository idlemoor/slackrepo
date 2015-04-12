#!/bin/sh

REPO="${1:-SBo}"
DATABASE="${2:-/var/lib/slackrepo/${REPO}/database_${REPO}.sqlite3}"
MARCH="${3:-$(uname -m)}"
DUMPFILE="${4:-share/$REPO/buildsecs_${MARCH}.sql}"
Query="select 'insert or ignore into buildsecs(itemid,secs,mhzsum,guessflag) values (''',itemid,''',''',secs,''',''',mhzsum,''',''~'');' from buildsecs where guessflag='=' order by itemid asc;"

echo "begin transaction;" > "${DUMPFILE}"
echo -e ".separator ''\n${Query}" | sqlite3 "${DATABASE}" >> "${DUMPFILE}"
echo "commit;" >> "${DUMPFILE}"

exit 0
