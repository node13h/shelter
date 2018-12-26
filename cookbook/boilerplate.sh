#!/usr/bin/env bash

__DOC__='
An example boilerplate test suite

This script uses shelter.sh as the testing framework. Please see
https://github.com/node13h/shelter for more information'

set -euo pipefail

# shellcheck disable=SC1091
source shelter.sh


# Functions to test: add() and sub()
# You probably want to source the library you want to test here instead

add () {
    declare a="$1"
    declare b="$2"

    bc <<EOF
${a} + ${b}
EOF
}

sub () {
    declare a="$1"
    declare b="$2"

    bc <<EOF
${a} - ${b}
EOF
}


# Tests

test_add_success () {
    assert_stdout 'add 2 2' - <<EOF
4
EOF
}

test_sub_success () {
    assert_stdout 'sub 2 2' - <<EOF
0
EOF
}

test_add_not_enough_arguments () {
    assert_fail 'add 2 2>/dev/null'
}


# Suite

suite () {
    shelter_run_test_class math test_add_
    shelter_run_test_class math test_sub_
}

usage () {
    cat <<EOF
Usage: ${0} [--help]
${__DOC__}

ENVIRONMENT VARIABLES:
  ENABLE_CI_MODE    set to non-empty value to enable the Junit XML
                    output mode

EOF
}

main () {
    if [[ "${1:-}" = '--help' ]]; then
        usage
        return 0
    fi

    # Uncomment the following to make your suite exit immediately after the
    # first failing test
    #
    # SHELTER_FORMATTER_ERREXIT_ON='first-failing'

    supported_shelter_versions 0.7

    if [[ -n "${ENABLE_CI_MODE:-}" ]]; then
        mkdir -p junit
        shelter_run_test_suite suite | shelter_junit_formatter >junit/boilerplate.xml
    else
        shelter_run_test_suite suite | shelter_human_formatter
    fi
}


if [[ -n "${BASH_SOURCE[0]:-}" && "${0}" = "${BASH_SOURCE[0]}" ]]; then
    main "$@"
fi
