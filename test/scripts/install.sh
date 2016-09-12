#! /bin/sh
set -ex
$RUBY -e "load \"$PACKAGE_BASE_DIR/bin/autoproj_install\"" -- "$@"

# vim: tw=0
