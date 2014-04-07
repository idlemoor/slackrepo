Build the whole SBo repository: (You will need about four days and 61Gb of disk space.)

`slackrepo build`

Build graphics/shotwell, with all its dependencies:

`slackrepo build graphics/shotwell` or just `slackrepo build shotwell`

Update all the academic/ packages in your package repository for SBo's latest changes:

`slackrepo update academic`

Do a "dry run" update of all your SBo packages:

`slackrepo update --dry-run`

Remove the package academic/grass (note, its dependencies and dependers will not be removed):

`slackpkg remove academic/grass` or just `slackpkg remove grass`

Test-build myprog in the newstuff repo, without storing the built package:

`slackrepo build -v --repo=newstuff --test --dry-run myprog`
