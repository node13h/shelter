#!/usr/bin/env bash

set -euo pipefail

declare -g PROG_DIR
PROG_DIR=$(dirname "${BASH_SOURCE[@]}")

# shellcheck source=shute.sh
source "${PROG_DIR%/}/shute.sh"


test_assert_stdout_success () {
    assert_stdout 'printf "%s\\n" This is a multiline test' <(
        cat <<EOF
This
is
a
multiline
test
EOF
    )
}

test_assert_stdout_success_stdout_silent () {
    [[ -z "$(assert_stdout 'echo TEST' <(echo TEST) 2>/dev/null)" ]]
}

test_assert_stdout_success_stderr_silent () {
    [[ -z "$(assert_stdout 'echo TEST' <(echo TEST) 2>&1 >/dev/null)" ]]
}

test_assert_stdout_fail () {
    ! assert_stdout 'printf "%s\\n" This is a multiline test' <(
        cat <<EOF
This
is
a
multiline
fail
EOF
    ) 2>/dev/null
}

test_assert_stdout_fail_stdout_silent () {
    [[ -z "$(! assert_stdout 'echo TEST' <(echo FAIL) 2>/dev/null)" ]]
}

test_assert_stdout_fail_stderr_diff () {
    [[ -n "$(! assert_stdout 'echo TEST' <(echo FAIL) 2>&1 >/dev/null)" ]]
}

test_assert_stdout_stdin_success () {
    assert_stdout 'echo This is a test' <<< 'This is a test'
}

sample_test_case_1_successful () {
    echo 'Hello'
    echo 'World' >&2
}

sample_test_case_1_failing () {
    echo 'Hello'
    echo 'World' >&2

    false

    echo 'Should not see me'
    echo 'Me either' >&2
}

test__shute_do_successful_env () {
    #shellcheck disable=SC2034
    declare shute_test_variable=hi
    _shute_do sample_test_case_1_successful | grep '^ENV shute_test_variable declare\\ --\\ shute_test_variable=\\"hi\\"$' >/dev/null
}

test__shute_do_successful_stdout () {
    _shute_do sample_test_case_1_successful | grep -q '^STDOUT Hello$'
}

test__shute_do_successful_stderr () {
    _shute_do sample_test_case_1_successful | grep -q '^STDERR World$'
}

test__shute_do_successful_time () {
    _shute_do sample_test_case_1_successful | grep -Eq '^TIME [0-9]*\.[0-9]+$'
}

test__shute_do_successful_exit () {
    _shute_do sample_test_case_1_successful | grep -q '^EXIT 0$'
}

test__shute_do_failing_env () {
    #shellcheck disable=SC2034
    declare shute_test_variable=hi
    _shute_do sample_test_case_1_failing | grep '^ENV shute_test_variable declare\\ --\\ shute_test_variable=\\"hi\\"$' >/dev/null
}

test__shute_do_failing_stdout () {
    _shute_do sample_test_case_1_failing | grep -q '^STDOUT Hello$'
}

test__shute_do_failing_stderr () {
    _shute_do sample_test_case_1_failing | grep -q '^STDERR World$'
}

test__shute_do_failing_time () {
    _shute_do sample_test_case_1_failing | grep -Eq '^TIME [0-9]*\.[0-9]+$'
}

test__shute_do_failing_exit () {
    _shute_do sample_test_case_1_failing | grep -q '^EXIT 1$'
}

test__shute_do_failing_errexit () {
    _shute_do sample_test_case_1_failing | grep -Ev '(STDOUT Should not see me|STDERR Me either)' >/dev/null
}

test__shute_do_eval () {
    _shute_do 'echo Hello World' | grep -q '^STDOUT Hello World$'
}

test__shute_do_nounset () {
    # shellcheck disable=SC2016
    _shute_do 'unset foo; echo "$foo"' | grep -q '^EXIT 1$'
}

test_shute_run_test_case_partial () (

    _shute_do () {
        cat <<"EOF"
ENV A declare\ --\ A=\"Two\ \ Spaces\"
ENV B declare\ -a\ B=\(\[0\]=\"one\"\ \[1\]=\"two\"\)
STDOUT Hello \
STDERR "World"
TIME 0.15
EXIT 0
EOF
    }

    diff -du <(shute_run_test_case testclass testfunction) - <<"EOF"
"testfunction": {"output": [{"STDOUT": "Hello \\"}, {"STDERR": "\"World\""}], "env": {"A": "declare -- A=\"Two  Spaces\"", "B": "declare -a B=([0]=\"one\" [1]=\"two\")"}, "time": "0.15", "class": "testclass", "exit": 0}
EOF
)

test_shute_run_test_case_full () (

    _shute_do () {
        cat <<"EOF"
ENV A declare\ --\ A=\"Two\ \ Spaces\"
ENV B declare\ -a\ B=\(\[0\]=\"one\"\ \[1\]=\"two\"\)
STDOUT Hello \
STDERR "World"
TIME 0.15
EXIT 0
EOF
    }

    diff -du <(shute_run_test_case testclass testfunction TRUE) - <<"EOF"
{"testfunction": {"output": [{"STDOUT": "Hello \\"}, {"STDERR": "\"World\""}], "env": {"A": "declare -- A=\"Two  Spaces\"", "B": "declare -a B=([0]=\"one\" [1]=\"two\")"}, "time": "0.15", "class": "testclass", "exit": 0}}
EOF
)

# A very basic test runner to keep it simple while
# testing the testing framework :)

declare fn rc status colour

# shellcheck disable=SC2034
while read -r fn; do
    set +e

    (
        set -e
        "$fn"
    )

    rc="$?"
    set -e

    if [[ "$rc" = 0 ]]; then
        status='success'
        colour=92
    else
        status='fail'
        colour=91
    fi

    printf '\e[1;%sm%s %s\e[m\n' "$colour" "$fn" "$status"

done < <(compgen -A function 'test_')
