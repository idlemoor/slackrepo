You can clone the git repository, and then run the embedded
SlackBuild to create a package that you can install:

    git clone git@github.com:idlemoor/slackrepo.git
    cd slackrepo
    git archive --format=tar --prefix=slackrepo-0.0.1/ HEAD | gzip > SlackBuild/slackrepo-0.0.1.tar.gz
    cd SlackBuild
    VERSION=0.0.1 TAG=_github OUTPUT=$(pwd) sh ./slackrepo.SlackBuild
    installpkg ./slackrepo-0.0.1-noarch-1_github.tgz
