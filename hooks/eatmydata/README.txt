Adding this directory with --hook-directory will result in mmdebstrap using
dpkg inside an eatmydata wrapper script. This will result in spead-ups on
systems where sync() takes some time. Using --dpkgopt=force-unsafe-io will have
a lesser effect compared to eatmydata. See:
https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=613428
