#!/usr/bin/env bash

# MIT license
# Copyright 2018 Sergej Alikov <sergej.alikov@gmail.com>

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
    echo "How's life?"
    echo 'Hello?' >&2
}

sample_test_case_1_failing () {
    echo 'Hello'
    echo 'World' >&2

    false

    echo 'Should not see me'
    echo 'Me either' >&2
}

_predictable_test_case_output () {
    # 1. replace TIME value with static 0.01
    # 2. natural sort to split STDOUT and STDERR into separate blocks (sequence numbers will ensure the correct ordering within a block)
    # 3. remove sequence numbers, which may differ between runs due to the multithreaded processing of STDOUT and STDERR
    sed 's/^TIME [0-9]*\.[0-9]\+$/TIME 0.01/' | sort -V | sed 's/\(STDOUT\|STDERR\) [0-9]\+/\1/'
}

_exclude_env () {
    grep -v '^ENV '
}

test_shute_run_test_case_successful_env () {
    # shellcheck disable=SC2034
    declare shute_test_variable=hi

    shute_run_test_case sample_test_case_1_successful | grep '^ENV shute_test_variable declare\\ --\\ shute_test_variable=\\"hi\\"$' >/dev/null
}

test_shute_run_test_case_successful_env_missing () {
    unset shute_test_variable

    shute_run_test_case sample_test_case_1_successful | { ! grep '^ENV shute_test_variable declare\\ --\\ shute_test_variable=\\"hi\\"$' >/dev/null; }
}

test_shute_run_test_case_successful () {
    diff -du <(shute_run_test_case sample_test_case_1_successful | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD sample_test_case_1_successful
EXIT 0
STDERR World
STDERR Hello?
STDOUT Hello
STDOUT How's life?
TIME 0.01
EOF
}

test_shute_run_test_case_failing () {
    diff -du <(shute_run_test_case sample_test_case_1_failing | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD sample_test_case_1_failing
EXIT 1
STDERR World
STDOUT Hello
TIME 0.01
EOF
}

test_shute_run_test_case_eval () {
    diff -du <(shute_run_test_case 'echo "Hello World"' | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD echo "Hello World"
EXIT 0
STDOUT Hello World
TIME 0.01
EOF
}

test_shute_run_test_case_nounset () {
    # shellcheck disable=SC2016
    shute_run_test_case 'unset foo; echo "$foo"' | grep '^EXIT 1$' >/dev/null
}

test_shute_run_test_class_name () (

    # Mock
    shute_run_test_case () {
        printf 'CMD %s\n' "$1"
        cat <<"EOF"
ENV RANDOM declare\ -i\ RANDOM=\"31895\"
ENV SECONDS declare\ -i\ SECONDS=\"1\"
EXIT 0
STDOUT Hello World
TIME 0.01
EOF
    }

    diff -du <(shute_run_test_class testclass sample_test_case_1_) - <<"EOF"
CMD sample_test_case_1_failing
ENV RANDOM declare\ -i\ RANDOM=\"31895\"
ENV SECONDS declare\ -i\ SECONDS=\"1\"
EXIT 0
STDOUT Hello World
TIME 0.01
CLASS testclass
CMD sample_test_case_1_successful
ENV RANDOM declare\ -i\ RANDOM=\"31895\"
ENV SECONDS declare\ -i\ SECONDS=\"1\"
EXIT 0
STDOUT Hello World
TIME 0.01
CLASS testclass
EOF
)

test_shute_run_test_single () (

    # Mock
    shute_run_test_case () {
        printf 'CMD %s\n' "$1"
    }

    diff -du <(shute_run_test_class testclass sample_test_case_1_succ) - <<"EOF"
CMD sample_test_case_1_successful
CLASS testclass
EOF
)

test_shute_run_test_none () (

    # Mock
    shute_run_test_case () {
        printf 'CMD %s\n' "$1"
    }

    unset -f shute_non_existing_command

    diff -du <(shute_run_test_class testclass shute_non_existing_command) - <<"EOF"
EOF
)

test_shute_run_test_suite () (

    # Mock
    test_shute_run_test_suite_suite_mock_1 () {
        cat <<EOF
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_2
EXIT 1
TIME 1.5
EOF
    }

    diff -du <(shute_run_test_suite test_shute_run_test_suite_suite_mock_1) - <<"EOF"
SUITE-ERRORS 1
SUITE-FAILURES 0
SUITE-NAME test_shute_run_test_suite_suite_mock_1
SUITE-SKIPPED 0
SUITE-TESTS 2
SUITE-TIME 1.51
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_2
EXIT 1
TIME 1.5
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
