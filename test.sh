#!/usr/bin/env bash

# MIT license
# Copyright 2018 Sergej Alikov <sergej.alikov@gmail.com>

set -euo pipefail

declare -g PROG_DIR
PROG_DIR=$(dirname "${BASH_SOURCE[@]}")

# shellcheck source=shelter.sh
source "${PROG_DIR%/}/shelter.sh"

test_assert_fd () {
    # shellcheck disable=SC2031
    [[ -n "${SHELTER_ASSERT_FD:-}" ]]
}

_mute_assert_fd () {
    # shellcheck disable=SC2034
    "$@" {SHELTER_ASSERT_FD}>/dev/null
}

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
    ! _mute_assert_fd assert_stdout 'printf "%s\\n" This is a multiline test' <(
        cat <<EOF
This
is
a
multiline
fail
EOF
    ) >/dev/null
}

test_assert_stdout_assert_fd_message () {
    diff -du <(assert_stdout <(echo TEST) <(echo FAIL) 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) - <<"EOF"
assert_stdout Assert failed!
EOF
}

test_assert_stdout_fail_stdout_diff () {
    [[ -n "$(_mute_assert_fd assert_stdout 'echo TEST' <(echo FAIL) 2>/dev/null)" ]]
}

test_assert_stdout_fail_stderr_silent () {
    [[ -z "$(_mute_assert_fd assert_stdout 'echo TEST' <(echo FAIL) 2>&1 >/dev/null)" ]]
}

test_assert_stdout_stdin_success () {
    assert_stdout 'echo This is a test' <<< 'This is a test'
}

test_assert_success_sucess () {
    assert_success 'false || true'
}

test_assert_success_failure () {
    ! _mute_assert_fd assert_success 'false && true'
}

test_assert_success_assert_fd_message () {
    diff -du <(assert_success false 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) - <<"EOF"
assert_success Assert failed!
EOF
}

test_assert_fail_sucess () {
    assert_fail 'false && true'
}

test_assert_fail_sucess_specific () {
    assert_fail '( exit 5 )' 5
}

test_assert_fail_failure () {
    ! _mute_assert_fd assert_fail 'false || true'
}

test_assert_fail_failure_specific () {
    ! _mute_assert_fd assert_fail '( exit 5 )' 1
}

test_assert_fail_invalid_arg () {
    diff -du <(assert_fail true 0 '' 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) <(printf '')
}

test_assert_fail_assert_fd_message () {
    diff -du <(assert_fail true '' 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) - <<"EOF"
assert_fail Assert failed!
EOF
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

test_shelter_run_test_case_successful_env () {
    # shellcheck disable=SC2034
    declare shelter_test_variable=hi

    shelter_run_test_case sample_test_case_1_successful | grep '^ENV shelter_test_variable declare\\ --\\ shelter_test_variable=\\"hi\\"$' >/dev/null
}

test_shelter_run_test_case_successful_env_missing () {
    unset shelter_test_variable

    shelter_run_test_case sample_test_case_1_successful | { ! grep '^ENV shelter_test_variable declare\\ --\\ shelter_test_variable=\\"hi\\"$' >/dev/null; }
}

test_shelter_run_test_case_successful () {
    diff -du <(shelter_run_test_case sample_test_case_1_successful | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD sample_test_case_1_successful
EXIT 0
STDERR World
STDERR Hello?
STDOUT Hello
STDOUT How's life?
TIME 0.01
EOF
}

test_shelter_run_test_case_successful_no_output () {
    diff -du <(shelter_run_test_case true | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD true
EXIT 0
TIME 0.01
EOF
}

test_shelter_run_test_case_failing () {
    diff -du <(shelter_run_test_case sample_test_case_1_failing | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD sample_test_case_1_failing
EXIT 1
STDERR World
STDOUT Hello
TIME 0.01
EOF
}

test_shelter_run_test_case_eval () {
    diff -du <(shelter_run_test_case 'echo "Hello World"' | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD echo "Hello World"
EXIT 0
STDOUT Hello World
TIME 0.01
EOF
}

test_shelter_run_test_case_nounset () {
    # shellcheck disable=SC2016
    shelter_run_test_case 'unset foo; echo "$foo"' | grep '^EXIT 1$' >/dev/null
}

test_shelter_run_test_case_skipped () {
    SHELTER_SKIP_TEST_CASES=('sample_test_case_1_successful')
    diff -du <(shelter_run_test_case sample_test_case_1_successful) - <<"EOF"
SKIPPED sample_test_case_1_successful
EOF
}

test_shelter_run_test_case_assert_fd_prefixed () {
    # shellcheck disable=SC2016
    shelter_run_test_case 'echo TEST >&"${SHELTER_ASSERT_FD}"' | grep '^ASSERT TEST$' >/dev/null
}

test_shelter_run_test_class_name () (

    # Mock
    shelter_run_test_case () {
        printf 'CMD %s\n' "$1"
        cat <<"EOF"
ENV RANDOM declare\ -i\ RANDOM=\"31895\"
ENV SECONDS declare\ -i\ SECONDS=\"1\"
EXIT 0
STDOUT Hello World
TIME 0.01
EOF
    }

    diff -du <(shelter_run_test_class testclass sample_test_case_1_) - <<"EOF"
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

test_shelter_run_test_class_single () (

    # Mock
    shelter_run_test_case () {
        printf 'CMD %s\n' "$1"
    }

    diff -du <(shelter_run_test_class testclass sample_test_case_1_succ) - <<"EOF"
CMD sample_test_case_1_successful
CLASS testclass
EOF
)

test_shelter_run_test_class_none () (

    # Mock
    shelter_run_test_case () {
        printf 'CMD %s\n' "$1"
    }

    unset -f shelter_non_existing_command

    diff -du <(shelter_run_test_class testclass shelter_non_existing_command) - <<"EOF"
EOF
)

test_shelter_run_test_suite () (

    # Mock
    test_shelter_run_test_suite_suite_mock_1 () {
        cat <<EOF
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_2
EXIT 1
TIME 1.5
CMD cmd_3
ASSERT some_assert_fn Assertion error!
EXIT 1
TIME 0.01
EOF
    }

    diff -du <(shelter_run_test_suite test_shelter_run_test_suite_suite_mock_1) - <<"EOF"
SUITE_ERRORS 1
SUITE_FAILURES 1
SUITE_NAME test_shelter_run_test_suite_suite_mock_1
SUITE_SKIPPED 0
SUITE_TESTS 3
SUITE_TIME 1.52
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_2
EXIT 1
TIME 1.5
CMD cmd_3
ASSERT some_assert_fn Assertion error!
EXIT 1
TIME 0.01
EOF
)

test_shelter_run_test_suites () (

    # Mock
    test_shelter_run_test_suites_suite_mock_1 () {
        cat <<EOF
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_2
EXIT 1
TIME 1.5
CMD cmd_3
ASSERT some_assert_fn Assertion error!
EXIT 1
TIME 0.01
EOF
    }

    test_shelter_run_test_suites_suite_mock_2 () {
        cat <<EOF
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_3
EXIT 0
TIME 0.5
SKIPPED cmd_4
EOF
    }

    diff -du <(shelter_run_test_suites all test_shelter_run_test_suites_suite_mock_) - <<"EOF"
SUITES_ERRORS 1
SUITES_FAILURES 1
SUITES_NAME all
SUITES_SKIPPED 1
SUITES_TESTS 6
SUITES_TIME 2.03
SUITE_ERRORS 1
SUITE_FAILURES 1
SUITE_NAME test_shelter_run_test_suites_suite_mock_1
SUITE_SKIPPED 0
SUITE_TESTS 3
SUITE_TIME 1.52
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_2
EXIT 1
TIME 1.5
CMD cmd_3
ASSERT some_assert_fn Assertion error!
EXIT 1
TIME 0.01
SUITE_ERRORS 0
SUITE_FAILURES 0
SUITE_NAME test_shelter_run_test_suites_suite_mock_2
SUITE_SKIPPED 1
SUITE_TESTS 3
SUITE_TIME 0.51
CMD cmd_1
EXIT 0
TIME 0.01
CMD cmd_3
EXIT 0
TIME 0.5
SKIPPED cmd_4
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
