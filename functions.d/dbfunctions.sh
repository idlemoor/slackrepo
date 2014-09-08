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

  sqlite3 "$SR_DATABASE" << ++++
create table if not exists buildsecs ( itemid text primary key, secs text );
create table if not exists packages ( pkgnam text primary key, itemid text );
++++
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

  sqlite3 "$SR_DATABASE" \
    "insert or replace into buildsecs ( itemid, secs ) values ( '$1', '$2' );"
  return $?
}

#-------------------------------------------------------------------------------

function db_get_buildsecs
# Retrieve a build time (if no database, do not print anything)
# $1 = itemid
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  sqlite3 "$SR_DATABASE" \
    "select secs from buildsecs where itemid='$1';"
  return $?
}

#-------------------------------------------------------------------------------

function db_del_buildsecs
# Delete a build time
# $1 = itemid
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  sqlite3 "$SR_DATABASE" \
    "delete from buildsecs where itemid='$1';"
  return $?
}

#-------------------------------------------------------------------------------

function db_set_pkgnam_itemid
# Record a package name and its corresponding itemid
# $1 = pkgnam
# $2 = itemid
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  sqlite3 "$SR_DATABASE" \
    "insert or replace into packages ( pkgnam, itemid ) values ( '$1', '$2' );"
  return $?
}

#-------------------------------------------------------------------------------

function db_get_pkgnam_itemid
# Get the itemid for a given pkgnam
# $1 = pkgnam
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  sqlite3 "$SR_DATABASE" \
    "select itemid from packages where pkgnam='$1';"
  return $?
}

#-------------------------------------------------------------------------------

function db_del_pkgnam_itemid
# Delete a package name and its corresponding itemid
# $1 = pkgnam
{
  [ "$OPT_TRACE" = 'y' ] && echo -e ">>>> ${FUNCNAME[@]}\n     $*" >&2
  [ -n "$SR_DATABASE" ] || return 0

  sqlite3 "$SR_DATABASE" \
    "delete from packages where pkgnam='$1';"
  return $?
}
