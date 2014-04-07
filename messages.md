All messages from slackrepo are sent to a main log file.  Progress messages are
displayed on the screen.  Control arguments '--verbose' ('-v') and
'--quiet' ('-q') can be specified, to increase or decrease the details
that are displayed on the screen.

Detailed output from each build process is sent to an item-specific log
file, but is not displayed on the screen.

The log files are in a repository-specific directory.  A new main log file is created
for each run of slackrepo, with a name of the form 

  `/var/log/slackrepo/log_SBo/slackrepo_YYYY-MM-DD_hh:mm:ss.log`

Each item-specific log file is in a subdirectory if the SlackBuilds directory
has subdirectories.  For example, the log file for the SBo item 'graphics/shotwell'
is

  `/var/log/slackrepo/log_SBo/graphics/shotwell.log`
