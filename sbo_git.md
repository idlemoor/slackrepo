If no SlackBuild Repository exists when slackrepo starts, it will clone the
SlackBuilds.org git repository, and a local branch '14.1' will be created
that tracks 'origin/14.1' (i.e., the stable branch at SlackBuilds.org).

As a special case, if the local branch is named '14.1' (as above) and is
clean, then when slackrepo starts it will automatically update the local
branch by fast forward (if possible) from its origin, but only if more than
one day has elapsed since the last automatic update.
