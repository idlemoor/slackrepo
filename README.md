SBoggit
=======

Automated clean package building from SlackBuilds.org git

Usage: SBoggit category|item ...

Optional environment variables --
  SBOGGIT - base directory, default /SBoggit
  TAG - default _SBoggit
  SBOREPO - local SBo git repo base, default $SBOGGIT/slackbuilds
  GITBRANCH  - git branch to build in, default '14.1'

Possible hints in $SBOGGIT/hints/ --
  prg.skipme - don't build prg (.skipme file contains optional comment for display/log)
  prg.readmedeps - dependencies to substitute for %README% in REQUIRES="..."
  prg.options - options to supply to the SlackBuild
  prg.moredeps - more dependencies, eg. to support options
  prg.uidgid - groupadd and useradd commands needed for prg [UNIMPLEMENTED]
  prg.makej1 - set MAKEFLAGS='j1' during build
  prg.tar.gz - SBo submission-style tarball to replace prg/* before build
  prg.cleanup - script to run after prg is uninstalled [UNIMPLEMENTED]

This script is intended to be run on a clean, full installation of Slackware.
  Start with a full installation of Slackware.
  Do not install any other packages.
  Do not use the system for anything else.
  Do a complete reinstall of Slackware after you have finished.

Builds are not 100% clean and not 100% repeatable.  Each build is done as a
flat list of deps.  Each dep not already in $OUTREPO is built in the context
of the list, so it is possible for a package to pick up an unintended
dependency.  If one dep in the list is out of date, the remainder of the
list is rebuilt.  Git revision hashes are recorded in $OUTPUT, and rebuilds
are triggered when the hash in SBOREPO differs.

The local git branch will be brutally cleaned on startup.  You have been
warned!  If no git repo is present, it will be cloned from SlackBuilds.org.
If the branch is '14.1' or 'master', it will be updated by fast forward
(if possible) from origin/master (which is probably SBo, but could be a
local mirror) if it is more than one day since the last update.
