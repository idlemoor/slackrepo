Multiple repositories are supported.  The Repository ID, e.g. 'SBo',
selects a configuration file, e.g. /etc/slackrepo/slackrepo_SBo.conf, and
the configuration file sets the paths of the SlackBuild repository, the
source repository, the package repository, the hints directory, and the
log directory.  The Repository ID can be specified by the control argument
'--repo=ID', or by the REPO environment variable, or by setting `REPO=ID`
in the file ~/.slackreporc.  By default, the default default is 'SBo'.

Example showing repository trees for Repository ID 'SBo':
    
    [REPO=SBo] /etc/slackrepo/slackrepo_SBo.conf
                |
    [SBREPO]    |--/var/lib/slackrepo/git_SBo/category/item/item.SlackBuild (etc)
    [PKGREPO]   |--/var/lib/slackrepo/pkg_SBo/category/item/item-1.0-i486-1_SBo.tgz
    [SRCREPO]   |--/var/lib/slackrepo/src_SBo/category/item/item-1.0.tar.gz
                |
    [HINTS]     |--/etc/slackrepo/hints_SBo/category/item.options
                |
    [LOGDIR]    |--/var/log/slackrepo/log_SBo/category/item.log

Under each of git_SBo, src_SBo and pkg_SBo is a directory for each SBo
category, and under each category directory is a subdirectory for each
item.  Under hints_SBo and log_SBo there are directories for each category,
but the hints and logs are not in subdirectories.
