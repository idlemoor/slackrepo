The following files are created by slackrepo and gen_repos_files.sh in the package repository:

* `package.tgz` (or .txz, .tbz, .tlz) - the package itself
* `package.tgz.asc` (or .txz.asc, .tbz.asc, .tlz.asc) - a detached GPG signature that can be used to verify the package
* `package.tgz.md5` (or .txz.md5, .tbz.md5, .tlz.md5) - the package's md5sum
* `package.dep` - a plaintext list of all dependencies of the package (including indirect dependencies, but excluding any dependencies in Slackware itself)
* `package.lst` - a listing of the contents of the package
* `package.meta` - package management information, for generating PACKAGES.TXT
* `package.rev` - slackrepo's revision information about the package
* `package.txt` - text description of the package (based on the slack-desc)
