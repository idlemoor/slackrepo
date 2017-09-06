#!/bin/bash
# Copyright 2017 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# hookfunctions.sh - hook functions for slackrepo
#   run_hooks
#   gitfetch_hook
#   genrepos_hook
#-------------------------------------------------------------------------------

declare -a HOOK_START HOOK_FINISH

# For backward compatibility if the user's config file doesn't define those
# arrays, we'll set up some sane defaults here.

HOOK_START=( gitfetch_hook )
HOOK_FINISH=( genrepos_hook )

#-------------------------------------------------------------------------------

function run_hooks
# Run hooks listed in HOOK_START or HOOK_FINISH array
# $1 = keyword for one of the above hook arrays: 'start' or 'finish'
# Returns:
# 0 = all hooks succeeded
# 1 = one or more hooks failed
{
  hooklist="$1"
  hookarray="HOOK_${hooklist^^}[@]"
  retval=0
  for hook in ${!hookarray}; do
    hooktype=$(type -t "$hook")
    case "$hooktype" in
      'function')
        ${hook} || { log_warning "Failed to execute ${hooklist} hook \"${hook}\""; retval=1; }
        ;;
      'file'|'alias')
        ${SUDO}${hook} || { log_warning "Failed to execute ${hooklist} hook \"${hook}\", status $?"; retval=1; }
        ;;
      *)
        log_warning "Not a valid ${hooklist} hook: \"${hook}\""; retval=1;
        ;;
    esac
  done
  return "$retval"
}

#-------------------------------------------------------------------------------

function gitfetch_hook
# Fetch and merge upstream git
# No arguments, but uses various globals
# Returns 0, or calls exit_cleanup if there are git conflicts
{
  if [ "$GOTGIT" = 'y' ]; then
    if [ "$CMD" = 'build' ] || [ "$CMD" = 'rebuild' ] || [ "$CMD" = 'update' ]; then
      # Update git if git is clean, and the current branch is $SR_INIT_GITBRANCH
      log_normal "Checking whether git is clean ... "
      muck="$(git status -s .)"
      if [ -z "$muck" ]; then
        log_done "yes."
      else
        log_done "no."
      fi
      currbranch=$(git rev-parse --abbrev-ref HEAD)
      if [ -z "$muck" ] && [ "$currbranch" = "${SR_INIT_GITBRANCH:-master}" ]; then
        prevfetch=$(db_get_misc "git_fetch_${currbranch}")
        if [ $(( $(date +%s) - ${prevfetch:-0} )) -gt 86400 ]; then
          log_normal "Updating git ..."
          if [ "${OPT_REPO}" = 'ponce' ] && [ "$currbranch" = 'current' ]; then
            git fetch --all --prune
            db_set_misc "git_fetch_${currbranch}" "$(date +%s)"
            git checkout --quiet origin/"$currbranch"
            git branch --quiet -D "$currbranch"
            git checkout -b "$currbranch"
            gitstat=$?
          else
            git fetch
            db_set_misc "git_fetch_${currbranch}" "$(date +%s)"
            dounbuffer=""
            [ "$DOCOLOUR"  = 'y' ] && dounbuffer="${LIBEXECDIR}/unbuffer "
            $dounbuffer git merge --ff-only origin/"$currbranch"
            gitstat=$?
          fi
          if [ $gitstat = 0 ]; then
            log_normal "Finished updating git."
          else
            log_error "Failed to update git (status=$gitstat).\nPlease resolve any conflicts and merge manually."
            exit_cleanup 4
          fi
        fi
      fi
    fi
  fi
  return 0
}

#-------------------------------------------------------------------------------

function genrepos_hook
# Package repository maintenance: call gen_repos_files.sh
# No arguments, but uses lots of globals to make the Haskell weenies cry :D
# Return status:
#   0 = success, or gen_repos_files.sh is not enabled
#   nonzero = error status from gen_repos_files.sh
{
  genrepstat=0
  if [ "$OPT_DRY_RUN" != 'y' ] && [ -s "$CHANGELOG" ]; then
    if [ "$SR_USE_GENREPOS" = 1 ]; then
      if [ -z "$SR_RSS_UUID" ]; then
        log_error "Please set RSS_UUID in $repoconf"
        genrepstat=9
      else
        log_start "gen_repos_files.sh"
        # 'man sort' says an in-place sort is ok, so let's be lazy :-)
        sort -o "$CHANGELOG" "$CHANGELOG"
        REPOSROOT="$SR_REPOSROOT" REPOSOWNER="$SR_REPOSOWNER" REPOSOWNERGPG="$SR_REPOSOWNERGPG" DL_URL="$SR_DL_URL" \
        RSS_TITLE="$SR_RSS_TITLE" RSS_ICON="$SR_RSS_ICON" RSS_LINK="$SR_RSS_LINK" RSS_CLURL="$SR_RSS_CLURL" \
        RSS_DESCRIPTION="$SR_RSS_DESCRIPTION" RSS_FEEDMAX="$SR_RSS_FEEDMAX" RSS_UUID="$SR_RSS_UUID" \
        GPGBIN="$SR_GPGBIN" USE_GPGAGENT="$SR_USE_GPGAGENT" FOR_SLAPTGET="$SR_FOR_SLAPTGET" \
        FOLLOW_SYMLINKS="$SR_FOLLOW_SYMLINKS" REPO_SUBDIRS="$SR_REPO_SUBDIRS" \
        sh "${LIBEXECDIR}"/gen_repos_files.sh -l "$CHANGELOG"
        genrepstat=$?
        if [ "$genrepstat" != 0 ]; then
          log_error "gen_repos_files.sh failed, status $genrepstat -- changelog retained"
          changelogstat="$genrepstat"
        fi
        log_normal ""
        log_important "Finished gen_repos_files.sh at $(date +%T)"
      fi
    fi
  fi
  return "$genrepstat"
}
