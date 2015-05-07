#!/bin/bash
# Copyright 2015 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# infofunctions.sh - function implementing the 'info' command:
#   info_command
#-------------------------------------------------------------------------------

function info_command
# Print version, configuration and debugging information on standard output
{
  echo ""
  print_version
  echo ""

  # Show the system info
  echo "$(hostname)"
  echo "  OS: ${SYS_OSNAME}${SYS_OSVER}"
  echo "  kernel: ${SYS_KERNEL}"
  echo "  arch: ${SYS_ARCH}"
  [ "$SYS_MULTILIB" = 'y' ] && echo "  multilib: yes"
  echo "  nproc: ${SYS_NPROC}"
  echo "  total MHz: ${SYS_MHz}"
  [ "$SYS_OVERLAYFS" = 'y' ] && echo "  overlayfs: yes"
  [ "$EUID" != 0 ] && echo "  username: $USER"
  echo ""

  # Show which config files exist
  echo "Configuration files:"
  for configfile in ~/.slackreporc ~/.genreprc /etc/slackrepo/slackrepo_"${OPT_REPO}".conf; do
    if [ -f "$configfile" ]; then
      echo "  $configfile: yes"
    else
      echo "  $configfile: no"
    fi
  done
  echo ""

  # Show the options
  echo "Configuration options and variables:"
  echo "  --repo=$OPT_REPO"
  if [ "$OPT_VERY_VERBOSE" = 'y' ]; then
    echo "  --very-verbose"
  elif [ "$OPT_VERBOSE" = 'y' ]; then
    echo "  --verbose"
  fi
  [      "$OPT_DRY_RUN" = 'y' ] && echo "  --dry-run"
  [      "$OPT_INSTALL" = 'y' ] && echo "  --install"
  [         "$OPT_LINT" = 'y' ] && echo "  --lint"
  [     "$OPT_KEEP_TMP" = 'y' ] && echo "  --keep-tmp"
  [       "$OPT_CHROOT" = 'y' ] && echo "  --chroot"
  [    "$OPT_COLOR" != 'auto' ] && echo "  --color=$OPT_COLOR"
  [        "$OPT_NICE" != '5' ] && echo "  --nice=$OPT_NICE"

  # Show the variables
  for name in $varnames; do
    srvar="SR_$name"
    echo "  $name=\"${!srvar}\""
  done
  if [ "$SR_USE_GENREPOS" = 1 ]; then
    for name in $genrepnames; do
      srvar="SR_$name"
      [ -n "${!srvar}" ] && echo "  $name=\"${!srvar}\""
    done
  else
    echo "  USE_GENREPOS=\"$SR_USE_GENREPOS\""
  fi
  echo ""

  # Show the repository info
  if [ -d "$SR_SBREPO" ]; then
    cd "$SR_SBREPO"
    if [ -d ".git" ]; then
      [ -n "$(git status -s .)" ] && dirty=' (DIRTY)'
      echo "git repo:   $SR_SBREPO"
      echo "  branch:   $(git rev-parse --abbrev-ref HEAD)"
      echo "  date:     $(date --date=@$(git log -n 1 --format=%ct))"
      echo "  revision: $(git rev-parse HEAD)$dirty"
      echo "  title:    $(git log -n 1 --format=%s)"
    else
      echo "SlackBuild repo: $SR_SBREPO (not git)"
    fi
  else
    echo "Repository $SR_SBREPO does not exist."
  fi
  echo ""

  # Show significant environment variables. This is not a comprehensive list (see
  # https://www.gnu.org/software/make/manual/html_node/Implicit-Variables.html)
  # and upstream builds don't always use them properly.
  for name in AR AS CC CFLAGS CXX CXXFLAGS CPP CPPFLAGS LD LDFLAGS DISTCC_HOSTS; do
    [ -n "${!name}" ] && echo "  $name=\"${!name}\""
  done
  echo ""

  exit 0
}
