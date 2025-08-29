#!/bin/sh

set -eu

SUDO=
while [ "$#" -gt 0 ]; do
  key="$1"
  case "$key" in
    SUDO)
      SUDO="sudo --preserve-env"
      ;;
    *)
      echo "Unknown argument: $key"
      exit 1
      ;;
  esac
  shift
done

# - Run command with fds 3 and 4 closed so that whatever test.sh does it
#   cannot interfere with these.
# - Both stdin and stderr of test.sh are written to stdout
# - Write exit status of test.sh to fd 3
# - Write stdout to shared/output.txt as well as to fd 4
# - Redirect fd 3 to stdout
# - Read fd 3 and let the group exit with that value
# - Redirect fd 4 to stdout
ret=0
{
  {
    {
      {
        ret=0
        (
          exec 3>&- 4>&-
          # shellcheck disable=SC2086
          env --chdir=./shared $SUDO sh -x ./test.sh 2>&1
        ) || ret=$?
        echo $ret >&3
      } | tee shared/output.txt >&4
    } 3>&1
  } | {
    read -r xs
    exit "$xs"
  }
} 4>&1 || ret=$?
if [ "$ret" -ne 0 ]; then
  echo "test.sh failed"
  exit 1
fi
