These configuration options are set in /etc/slackrepo/slackrepo_SBo.conf or ~/.slackreporc.

### Default repo ID

* `REPO=SBo` -- the default repo  ID.  This  determines  the  configuration  file  /etc/slackrepo/slackrepo_ID.conf from which other configuration variables will be read. This can be set only in ~/.slackreporc, but can be overridden by an environment variable or by the command line option '--repo=ID'.

### Repository filestore locations

* `SBREPO=/var/lib/slackrepo/git_SBo` -- location of SlackBuilds repository
* `PKGREPO=/var/lib/slackrepo/pkg_SBo` -- location of package repository
* `SRCREPO=/var/lib/slackrepo/src_SBo` -- location of downloaded source repository
* `HINTS=/etc/slackrepo/hints_SBo` -- location of 'hints' (see 'Hints' page)
* `LOGDIR=/var/log/slackrepo/log_SBo` -- location of log files
* `TMP=/tmp/SBo` - temporary directory

### Building packages

* `ARCH=''` -- arch for built packages (normally determined from the build host)
* `TAG=_SBo` -- tag for built packages (PLEASE CHANGE THIS if your packages will be publicly available)
* `PKGTYPE=tgz` -- package compression type. Valid values are: tgz, txz, tbz, tlz
* `NUMJOBS=''` -- number of make jobs to set in MAKEFLAGS (e.g., '-j2'). Leave blank to have this automatically determined as one more than the number of processors on the build host.


### Calling gen_repos_files.sh

* `USE_GENREPOS='0'` -- whether to use gen_repos_files.sh (to enable it, change 0 to 1)

If you enable gen_repos_files.sh, you *must* set correct values for its
configuration options in /etc/slackrepo/slackrepo_ID.conf.  However, if
you already use gen_repos_files.sh, it will still read your existing
~/.genreprc file.  For details, see the man page 'slackrepo.conf(5)'.
