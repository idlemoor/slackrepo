Optionally, Eric Hameleers' gen_repos_files.sh (which is included) can
be used to maintain additional package metadata in the package repository,
such as signing and a changelog.  Thanks, Eric!  To use it, you will
need to set a few configuration values in the repository's configuration
file /etc/slackrepo/slackrepo_SBo.conf (but, if you use gen_repos_files.sh
already, your existing ~/.genreprc config file will be read).
