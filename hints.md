You are encouraged to take full control of the building process by
reviewing, customising and creating 'hints'.  These are small
configuration files that determine the processing of each item,
including options and optional dependencies.

A sample set of hints for SlackBuilds.org are supplied in the directory
/etc/slackrepo/hints_SBo, but you are encouraged to review and modify them.

In particular, *please* review the README files of the packages you are
building, and then *please* modify the supplied option and dependency hints
for your own requirements!

The types of hints are as follows --

* prgnam.options      -- options to supply to the SlackBuild
* prgnam.optdeps      -- optional dependencies, including deps for options
* prgnam.readmedeps   -- dependencies to substitute for %README% in REQUIRES="..."
* prgnam.uidgid       -- groupadd and useradd commands needed for prgnam
* prgnam.md5ignore    -- don't check source md5sum
* prgnam.makej1       -- set MAKEFLAGS='-j1' during build
* prgnam.skipme       -- don't build prgnam
* prgnam.answers      -- answers for prompts printed when the SlackBuild is run
* prgnam.version      -- attempt to patch prgnam.info and prgnam.SlackBuild for a new version
* prgnam.cleanup      -- script to run after prgnam is uninstalled
* prgnam.no_uninstall -- do not uninstall (and do not cleanup)

### prgnam.options

This hint file should contain options described in the SlackBuild's README file, for example,

`GUI=yes`

### prgnam.optdeps and prgnam.readmedeps

These hint files should contain a list of dependencies separated by spaces and/or newlines, for example

`a52dec faac libdv libmpeg2 mjpegtools libquicktime x264 xvidcore`

The 'prgnam.optdeps' hint files can be used for optional dependencies listed in the SlackBuild's README file.  The 'prgnam.readmedeps' hint files should be used where the REQUIRES="..." list in the prgnam.info contains %README%; the contents will be substituted for %README%, but if you don't need any dependencies to be substituted for %README%, you should create an empty prgnam.readmedeps file.  (A warning will be printed if %README% is found without a prgnam.readmedeps file.)

### prgnam.uidgid

This hint file contains instructions for creating groups and usernames.  In many cases you will want a username and group with the same number and name, in which case the file can contain a set of variable assignments like this example:

    UIDGIDNUMBER=216
    UIDGIDNAME=pulse
    UIDGIDCOMMENT=
    UIDGIDDIR=/var/lib/pulse
    UIDGIDSHELL=

but if necessary the file can contain a small shell script for more complicated setup, like this:

    if ! getent group etherpad | grep -q ^etherpad: 2>/dev/null ; then
      groupadd -g 264 etherpad
    fi
    
    if ! getent passwd etherpad | grep -q ^etherpad: 2>/dev/null ; then
      useradd -u 264 -g etherpad -c "Etherpad lite" -m etherpad
    fi

### prgnam.md5ignore

This hint file can be created if the source archive is known to change sometimes without the version number being changed, so that the source archive's md5sum will not be checked. Just create an empty file; its contents are not read.

### prgnam.makej1

This hint file can be created if the build process fails when multiple 'make' jobs are used, so that the build will be executed with MAKEFLAGS='-j1'. Just create an empty file; its contents are not read.

### prgnam.skipme

This hint file can be created if you want to skip the package when it would otherwise be added, rebuilt, tested or updated.  If the hint file isn't empty, its contents will be displayed when the build is skipped, so you can put some helpful reminder text into it.

### prgnam.answers

This hint file can be created if the build process wants to read answers to its questions during the build process, for example licence agreements. The hint file is piped into the SlackBuild's standard input, so it should contain whatever will make the build process happy.

### prgnam.version

This hint file can be created to attempt an automatic patch of the version number in both the SlackBuild and info files.  The hint file should contain just the new version number, for example

`2.8.2`

The automatic patch is done by a simple text substitution. It often won't work (particularly if the old version number is something like '1', or if the download URL cannot be guessed correctly) but sometimes it's worth a try.  The md5sum of the source archive will not be checked. The patched SlackBuild and info files are not kept.

### prgnam.cleanup

This hint file can be created if the package needs extra cleanup when it is uninstalled, for example packages that replace standard Slackware packages, or install kernel modules. The hint file should contain appropriate shell commands. For example, to reinstall Slackware packages:

`echo y | slackpkg -dialog=off -only_new_dotnew=on reinstall tetex tetex-doc`

or to clean up after a kernel module is uninstalled:

`depmod -a`

### prgnam.no_uninstall

After slackrepo builds or tests a package, it uninstalls the package and all its dependencies, and it 
aggressively removes files from /etc that Slackware's own tools would normally leave in place.  **This will cause serious damage if you attempt to rebuild a package that is already installed and in active use** (for example, if you use slackrepo to test slackrepo, or if you rebuild nvidia-driver on a system that uses nvidia-driver).  You can avoid this by creating a prgnam.no_uninstall hint file, and then the package will not be uninstalled.  Just create an empty file; its contents are not read.
