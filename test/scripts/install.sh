#! /bin/sh
set -ex
if test "$TEST_ENABLE_COVERAGE" = "1"; then
    $RUBY -I$PACKAGE_BASE_DIR/lib -e "require 'simplecov'; SimpleCov.start { command_name '$TEST_COMMAND_NAME'; root '$PACKAGE_BASE_DIR'; coverage_dir '$PACKAGE_BASE_DIR/coverage' }; load '$PACKAGE_BASE_DIR/bin/autoproj_install.in'" -- "$@"
else
    $RUBY -e "load \"$PACKAGE_BASE_DIR/bin/autoproj_install\"" -- "$@"
fi

# vim: tw=0
