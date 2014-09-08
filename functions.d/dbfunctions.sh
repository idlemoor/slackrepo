#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# dbfunctions.sh - database functions for slackrepo
#   db_init
#   db_set_buildsecs
#   db_get_buildsecs
#   db_del_buildsecs
#-------------------------------------------------------------------------------

function db_init
# Initialise the sqlite database
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  echo "create table if not exists \
        buildsecs ( itemid text primary key, secs text );" \
  | sqlite3 "$SR_DATABASE"
  return $?
}

#-------------------------------------------------------------------------------

function db_set_buildsecs
# Record a build time
# $1 = itemid
# $2 = elapsed seconds
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  echo "insert or replace into \
        buildsecs ( itemid, secs ) \
        values ( '$1', '$2' );" \
  | sqlite3 "$SR_DATABASE"
  return $?
}

#-------------------------------------------------------------------------------

function db_get_buildsecs
# Retrieve a build time (if no database, do not print anything)
# $1 = itemid
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  echo "select secs from buildsecs where itemid='$itemid';" \
  | sqlite3 "$SR_DATABASE"
  return $?
}

#-------------------------------------------------------------------------------

function db_del_buildsecs
# Delete a build time
# $1 = itemid
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  echo "delete from buildsecs where itemid='$1';" \
  | sqlite3 "$SR_DATABASE"
  return $?
}
