Optionally, Eric Hameleers' gen_repos_files.sh (which is included) can
be used to maintain additional package metadata in the package repository,
such as signing and a changelog.  Thanks, Eric!  To use it, you will
need to set a few configuration values in the repository's configuration
file /etc/slackrepo/slackrepo_SBo.conf (but, if you use gen_repos_files.sh
already, your existing ~/.genreprc config file will be read).

The repositories created by slackrepo are suitable for use with slackpkg+
(http://slakfinder.org/slackpkg+.html), which is a plugin for slackpkg
that allows you to use slackpkg to manage packages from third party
repositories.  Thanks, Matteo!

To make your slackrepo+ package repositories accessible, you will need to
export them as a shared directory (e.g. NFS or a Virtualbox shared folder),
or perhaps serve them via a local webserver on the build host (e.g. by
setting `PKGREPO=/var/www/htdocs/pkg_SBo` in /etc/slackrepo/slackrepo_SBo.conf).

For example, on a client system, to configure slackpkg+ to use a shared
directory, /etc/slackpkg/slackpkgplus.conf would have something like this:

    REPOPLUS=( SBo slackpkgplus restricted alienbob )
    MIRRORPLUS['SBo']=dir://repositories/pkg_SBo/

Or to configure slackpkg+ to use a web-served repository on the build
host, you would have something like this:

    REPOPLUS=( SBo slackpkgplus restricted alienbob )
    MIRRORPLUS['SBo']=http://buildhost/pkg_SBo/

If you choose not to sign your packages with gen_repos_files.sh, you will
need to tell slackpkg+ not to check GPG signatures.  There are two ways
of doing this: (1) set `CHECKGPG=off` in /etc/slackpkg/slackpkg.conf, or
(2) use the slackpkg control argument '-checkgpg=off'.

Note that slackpkg+ will not install newly added packages from your own
package repository when you run 'slackpkg install-new'.  This command
searches for new packages ONLY in the official Slackware repository.  To
install specific packages in your own repository you can use

  `slackpkg install <packagename>`

or to install and upgrade everything in your own repository, you can use

  `slackpkg add <reponame>`
