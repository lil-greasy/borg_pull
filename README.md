# borg_pull
A script for using Borg in pull mode

Configuration is all at the top of the script.

This can back up multiple locations from a remote machine to Borg repositories on
a local machine. You just need SSH access to the remote machine.

You need to initialize the repositories on your local machine manually, but once
you’ve done that, you should be able to schedule the script and forget it.
