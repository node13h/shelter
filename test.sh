#!/usr/bin/env bash

# MIT license
# Copyright 2018 Sergej Alikov <sergej.alikov@gmail.com>

set -euo pipefail

declare -g PROG_DIR
PROG_DIR=$(dirname "${BASH_SOURCE[@]}")

# shellcheck source=shelter.sh
source "${PROG_DIR%/}/shelter.sh"


_tricky_fail () {
    false
    true
}

test__tricky_fail () {
    declare -i rc

    set +e
    (
        set -e
        _tricky_fail
    )

    # shellcheck disable=SC2181
    ! [[ "$?" -eq 0 ]]
}

_negate_status () {
    declare -i rc

    set +e
    (
        set -e
        "$@"
    )
    rc="$?"
    set -e

    if [[ "$rc" -eq 0 ]]; then
        return 1
    else
        return 0
    fi
}

test__negate_status_success () {
    _negate_status false
}

test__negate_status_success_tricky_fail () {
    _negate_status _tricky_fail
}

test__negate_status_failure () {
    # Use of ! is OK here as we are executing a single
    # non-compound command
    ! _negate_status true
}


test_assert_fd () {
    # shellcheck disable=SC2031
    [[ -n "${SHELTER_ASSERT_FD:-}" ]]
}

_mute_assert_fd () {
    # shellcheck disable=SC2034
    "$@" {SHELTER_ASSERT_FD}>/dev/null
}

test__mute_assert_fd_success () {
    _mute_assert_fd true
}

test__mute_assert_fd_failure () {
    _negate_status _mute_assert_fd false
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
    _negate_status _mute_assert_fd assert_stdout 'printf "%s\\n" This is a multiline test' <(
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
    _negate_status _mute_assert_fd assert_success 'false && true'
}

test_assert_success_failure_tricky_fail () {
    _negate_status _mute_assert_fd assert_success _tricky_fail
}

test_assert_success_assert_fd_message () {
    diff -du <(assert_success false 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) - <<"EOF"
assert_success Assert failed!
EOF
}

test_assert_fail_sucess () {
    assert_fail 'false && true'
}

test_assert_fail_sucess_tricky_fail () {
    assert_fail _tricky_fail
}

test_assert_fail_sucess_specific () {
    assert_fail '( exit 5 )' 5
}

test_assert_fail_failure () {
    _negate_status _mute_assert_fd assert_fail 'false || true'
}

test_assert_fail_failure_specific () {
    _negate_status _mute_assert_fd assert_fail '( exit 5 )' 1
}

test_assert_fail_invalid_arg () {
    diff -du <(assert_fail true 0 '' 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) <(printf '')
}

test_assert_fail_assert_fd_message () {
    diff -du <(assert_fail true '' 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) - <<"EOF"
assert_fail Assert failed!
EOF
}

test_assert_stdout_contains_success () {
    assert_stdout_contains 'echo This is a test' '^This'
}

test_assert_stdout_contains_failure () {
    _negate_status _mute_assert_fd assert_stdout_contains 'echo This is a test' '^test'
}

test_assert_stdout_contains_assert_fd_message () {
    diff -du <(assert_stdout_contains 'echo TEST' 'FAIL' 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) - <<"EOF"
assert_stdout_contains Assert failed!
EOF
}

test_assert_stdout_not_contains_success () {
    assert_stdout_not_contains 'echo This is a test' 'foo'
}

test_assert_stdout_not_contains_failure () {
    _negate_status _mute_assert_fd assert_stdout_not_contains 'echo This is a test' '^This'
}

test_assert_stdout_not_contains_assert_fd_message () {
    diff -du <(assert_stdout_not_contains 'echo TEST' 'TEST' 'Assert failed!' {SHELTER_ASSERT_FD}>&1 &>/dev/null) - <<"EOF"
assert_stdout_not_contains Assert failed!
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

    shelter_run_test_case sample_test_case_1_successful | { _negate_status grep '^ENV shelter_test_variable declare\\ --\\ shelter_test_variable=\\"hi\\"$' >/dev/null; }
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

test_shelter_junit_formatter_suites () (
    test_shelter_junit_formatter_suites_mock () {
        cat <<"EOF"
SUITES_NAME all
SUITES_TIME 2.03
SUITES_TESTS 6
SUITES_FAILURES 1
SUITES_ERRORS 1
SUITE_NAME test_shelter_run_test_suites_suite_mock_1
SUITE_TIME 1.52
SUITE_TESTS 3
SUITE_FAILURES 1
SUITE_ERRORS 1
SUITE_SKIPPED 0
CMD cmd_1
CLASS testclass
TIME 0.01
EXIT 0
CMD cmd_2
CLASS testclass
TIME 1.5
EXIT 1
ENV VAR1 declare\ -i\ VAR1=\"31895\"
ENV VAR2 declare\ VAR2=\"A\ String\"
CMD cmd_3
ASSERT some_assert_fn Assertion error!
TIME 0.01
EXIT 1
STDERR 1 Boom!
STDERR 2 Something went wrong :<
SUITE_NAME test_shelter_run_test_suites_suite_mock_2
SUITE_TIME 0.51
SUITE_TESTS 3
SUITE_FAILURES 0
SUITE_ERRORS 0
SUITE_SKIPPED 1
CMD cmd_1
TIME 0.01
EXIT 0
CMD cmd_4
TIME 0.5
EXIT 0
STDOUT 1 Standard output
STDERR 2 interleaved;
STDOUT 3 with some "standard error" output
SKIPPED cmd_5
EOF
    }
    diff -du <(test_shelter_junit_formatter_suites_mock | shelter_junit_formatter) - <<"EOF"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites errors="1" failures="1" name="all" tests="6" time="2.03">
<testsuite errors="1" failures="1" name="test_shelter_run_test_suites_suite_mock_1" skipped="0" tests="3" time="1.52">
<testcase classname="testclass" name="cmd_1" status="0" time="0.01">
</testcase>
<testcase classname="testclass" name="cmd_2" status="1" time="1.5">
<error></error>
</testcase>
<testcase name="cmd_3" status="1" time="0.01">
<failure message="Assertion error!" type="some_assert_fn"></failure>
<system-err>
1 Boom!
2 Something went wrong :&lt;
</system-err>
</testcase>
</testsuite>
<testsuite errors="0" failures="0" name="test_shelter_run_test_suites_suite_mock_2" skipped="1" tests="3" time="0.51">
<testcase name="cmd_1" status="0" time="0.01">
</testcase>
<testcase name="cmd_4" status="0" time="0.5">
<system-out>
1 Standard output
3 with some &quot;standard error&quot; output
</system-out>
<system-err>
2 interleaved;
</system-err>
</testcase>
<testcase name="cmd_5">
<skipped></skipped>
</testcase>
</testsuite>
</testsuites>
EOF
)

test_shelter_junit_formatter_suite () (
    test_shelter_junit_formatter_suites_mock () {
        cat <<"EOF"
SUITE_NAME test_shelter_run_test_suites_suite_mock_1
SUITE_TIME 1.52
SUITE_TESTS 3
SUITE_FAILURES 1
SUITE_ERRORS 1
SUITE_SKIPPED 0
CMD cmd_1
CLASS testclass
TIME 0.01
EXIT 0
CMD cmd_2
CLASS testclass
TIME 1.5
EXIT 1
ENV VAR1 declare\ -i\ VAR1=\"31895\"
ENV VAR2 declare\ VAR2=\"A\ String\"
CMD cmd_3
ASSERT some_assert_fn Assertion error!
TIME 0.01
EXIT 1
STDERR 1 Boom!
STDERR 2 Something went wrong :<
EOF
    }
    diff -du <(test_shelter_junit_formatter_suites_mock | shelter_junit_formatter) - <<"EOF"
<?xml version="1.0" encoding="UTF-8"?>
<testsuite errors="1" failures="1" name="test_shelter_run_test_suites_suite_mock_1" skipped="0" tests="3" time="1.52">
<testcase classname="testclass" name="cmd_1" status="0" time="0.01">
</testcase>
<testcase classname="testclass" name="cmd_2" status="1" time="1.5">
<error></error>
</testcase>
<testcase name="cmd_3" status="1" time="0.01">
<failure message="Assertion error!" type="some_assert_fn"></failure>
<system-err>
1 Boom!
2 Something went wrong :&lt;
</system-err>
</testcase>
</testsuite>
EOF
)

test_shelter_junit_formatter_testcase () (
    test_shelter_junit_formatter_suites_mock () {
        cat <<"EOF"
CMD cmd_3
ENV VAR1 declare\ -i\ VAR1=\"31895\"
ENV VAR2 declare\ VAR2=\"A\ String\"
ASSERT some_assert_fn Assertion error!
TIME 0.01
EXIT 1
STDERR 1 Boom!
STDERR 2 Something went wrong :<
EOF
    }
    diff -du <(test_shelter_junit_formatter_suites_mock | shelter_junit_formatter) - <<"EOF"
<?xml version="1.0" encoding="UTF-8"?>
<testcase name="cmd_3" status="1" time="0.01">
<failure message="Assertion error!" type="some_assert_fn"></failure>
<system-err>
1 Boom!
2 Something went wrong :&lt;
</system-err>
</testcase>
EOF
)

test_shelter_human_formatter_suites () (
    test_shelter_human_formatter_suites_mock () {
        cat <<"EOF"
SUITES_NAME all
SUITES_TIME 2.03
SUITES_TESTS 6
SUITES_FAILURES 1
SUITES_ERRORS 1
SUITE_NAME test_shelter_run_test_suites_suite_mock_1
SUITE_TIME 1.52
SUITE_TESTS 3
SUITE_FAILURES 1
SUITE_ERRORS 1
SUITE_SKIPPED 0
CMD cmd_1
CLASS testclass
TIME 0.01
EXIT 0
CMD cmd_2
CLASS testclass
TIME 1.5
EXIT 1
ENV VAR1 declare\ -i\ VAR1=\"31895\"
ENV VAR2 declare\ VAR2=\"A\ String\"
CMD cmd_3
ASSERT some_assert_fn Assertion error!
TIME 0.01
EXIT 1
STDERR 1 Boom!
STDERR 2 Something went wrong :<
SUITE_NAME test_shelter_run_test_suites_suite_mock_2
SUITE_TIME 0.51
SUITE_TESTS 3
SUITE_FAILURES 0
SUITE_ERRORS 0
SUITE_SKIPPED 1
CMD cmd_1
TIME 0.01
EXIT 0
CMD cmd_4
TIME 0.5
EXIT 0
STDOUT 1 Standard output
STDERR 2 interleaved;
STDOUT 3 with some "standard error" output
SKIPPED cmd_5
EOF
    }
    diff -du <(test_shelter_human_formatter_suites_mock | shelter_human_formatter) - <<"EOF"
Suites: all

 Suite: test_shelter_run_test_suites_suite_mock_1 (1.52s)

  [[1;92m+[m] [1;97mtestclass/cmd_1[m (0.01s)
  [[1;31mE[m] [1;97mtestclass/cmd_2[m (exit [1;31m1[m) (1.5s)
  [[1;91mF[m] [1;97mcmd_3[m (exit [1;31m1[m) (0.01s)
      [1;91mAssertion error![m (some_assert_fn)

      captured output:
      ---------------
      [0;33mBoom![m
      [0;33mSomething went wrong :<[m


 Suite: test_shelter_run_test_suites_suite_mock_2 (0.51s)

  [[1;92m+[m] [1;97mcmd_1[m (0.01s)
  [[1;92m+[m] [1;97mcmd_4[m (0.5s)
      captured output:
      ---------------
      [0;90mStandard output[m
      [0;33minterleaved;[m
      [0;90mwith some "standard error" output[m

  [[1;90m-[m] [1;97mcmd_5[m

Test results: 3 passed, 1 failed, 1 errors, 1 skipped
EOF
)

test_shelter_human_formatter_suite () (
    test_shelter_human_formatter_suites_mock () {
        cat <<"EOF"
SUITE_NAME test_shelter_run_test_suites_suite_mock_1
SUITE_TIME 1.52
SUITE_TESTS 3
SUITE_FAILURES 1
SUITE_ERRORS 1
SUITE_SKIPPED 0
CMD cmd_1
CLASS testclass
TIME 0.01
EXIT 0
CMD cmd_2
CLASS testclass
TIME 1.5
EXIT 1
ENV VAR1 declare\ -i\ VAR1=\"31895\"
ENV VAR2 declare\ VAR2=\"A\ String\"
CMD cmd_3
ASSERT some_assert_fn Assertion error!
TIME 0.01
EXIT 1
STDERR 1 Boom!
STDERR 2 Something went wrong :<
EOF
    }
    diff -du <(test_shelter_human_formatter_suites_mock | shelter_human_formatter) - <<"EOF"
Suite: test_shelter_run_test_suites_suite_mock_1 (1.52s)

 [[1;92m+[m] [1;97mtestclass/cmd_1[m (0.01s)
 [[1;31mE[m] [1;97mtestclass/cmd_2[m (exit [1;31m1[m) (1.5s)
 [[1;91mF[m] [1;97mcmd_3[m (exit [1;31m1[m) (0.01s)
     [1;91mAssertion error![m (some_assert_fn)

     captured output:
     ---------------
     [0;33mBoom![m
     [0;33mSomething went wrong :<[m


Test results: 1 passed, 1 failed, 1 errors, 0 skipped
EOF
)

test_shelter_human_formatter_testcase () (
    test_shelter_human_formatter_suites_mock () {
        cat <<"EOF"
CMD cmd_3
ENV VAR1 declare\ -i\ VAR1=\"31895\"
ENV VAR2 declare\ VAR2=\"A\ String\"
ASSERT some_assert_fn Assertion error!
TIME 0.01
EXIT 1
STDERR 1 Boom!
STDERR 2 Something went wrong :<
EOF
    }
    diff -du <(test_shelter_human_formatter_suites_mock | shelter_human_formatter) - <<"EOF"
[[1;91mF[m] [1;97mcmd_3[m (exit [1;31m1[m) (0.01s)
    [1;91mAssertion error![m (some_assert_fn)

    captured output:
    ---------------
    [0;33mBoom![m
    [0;33mSomething went wrong :<[m


Test results: 0 passed, 1 failed, 0 errors, 0 skipped
EOF
)

test_patch_command_function_strategy () {
    patch_command function true 'echo "Hello"'

    [[ -n "${SHELTER_PATCHED_COMMANDS[true]:-}" ]]

    diff -du <(true) - <<"EOF"
Hello
EOF

    unset -f true
    unset SHELTER_PATCHED_COMMANDS['true']

    diff -du <(true) <(:)
}

test_patch_command_function_strategy_fail_pathched_already () {
    patch_command function true 'echo "Hello"'
    _negate_status patch_command function true 'echo "Hello"' &>/dev/null

    unset -f true
    unset SHELTER_PATCHED_COMMANDS['true']
}

test_patch_command_mount_strategy () {

    if ! [[ "$(id -u)" -eq 0 ]]; then
        >&2 printf 'Need root privileges to run %s. Skipping\n' "${FUNCNAME[0]}"
        return 0
    fi

    patch_command mount '/usr/bin/true' 'echo "Hello"'

    mountpoint -q "/usr/bin/true"
    [[ -n "${SHELTER_PATCHED_COMMANDS['/usr/bin/true']:-}" ]]

    diff -du <(/usr/bin/true) - <<"EOF"
Hello
EOF

    umount /usr/bin/true
    rm -f -- "${SHELTER_PATCHED_COMMANDS['/usr/bin/true']}"
    unset SHELTER_PATCHED_COMMANDS['/usr/bin/true']

    diff -du <(true) <(:)
}

test_patch_command_mount_strategy_fail_pathched_already () {

    if ! [[ "$(id -u)" -eq 0 ]]; then
        >&2 printf 'Need root privileges to run %s. Skipping\n' "${FUNCNAME[0]}"
        return 0
    fi

    patch_command mount /usr/bin/true 'echo "Hello"'
    _negate_status patch_command mount /usr/bin/true 'echo "Hello"' &>/dev/null

    umount /usr/bin/true
    rm -f -- "${SHELTER_PATCHED_COMMANDS['/usr/bin/true']}"
    unset SHELTER_PATCHED_COMMANDS['/usr/bin/true']
}

test_shelter_run_test_case_cleans_up_patch_command_mount () {

    if ! [[ "$(id -u)" -eq 0 ]]; then
        >&2 printf 'Need root privileges to run %s. Skipping\n' "${FUNCNAME[0]}"
        return 0
    fi

    diff -du <(shelter_run_test_case 'patch_command mount /usr/bin/true "echo Hello"' | _exclude_env | _predictable_test_case_output) - <<"EOF"
CMD patch_command mount /usr/bin/true "echo Hello"
EXIT 0
STDERR Removing /usr/bin/true patch_command mount
TIME 0.01
EOF

    _negate_status mountpoint -q /usr/bin/true
}

test_patch_command_path_strategy () {
    patch_command path true 'echo "Hello"'

    [[ -n "${SHELTER_PATCHED_COMMANDS[true]:-}" ]]

    diff -du <(env true) - <<"EOF"
Hello
EOF

    rm -f -- "${SHELTER_PATCHED_COMMANDS['true']}"
    unset SHELTER_PATCHED_COMMANDS['true']

    diff -du <(env true) <(:)
}

test_patch_command_path_strategy_fail_pathched_already () {
    patch_command path true 'echo "Hello"'
    _negate_status patch_command path true 'echo "Hello"' &>/dev/null

    rm -f -- "${SHELTER_PATCHED_COMMANDS['true']}"
    unset SHELTER_PATCHED_COMMANDS['true']
}

test_shelter_run_test_case_cleans_up_patch_command_path_override () {
    diff -du <(shelter_run_test_case 'patch_command path true "echo Hello"' | _exclude_env | _predictable_test_case_output) - <<EOF
CMD patch_command path true "echo Hello"
EXIT 0
STDERR Removing ${SHELTER_TEMP_DIR}/bin/true patch_command path override
TIME 0.01
EOF

    _negate_status test -f "${SHELTER_TEMP_DIR}/bin/true"
}

test_unpatch_command_not_patched () {
    _negate_status unpatch_command this_command_is_not_patched &>/dev/null
}

test_unpatch_command_function_strategy () (

    _test_command () {
        true
    }

    SHELTER_PATCHED_COMMANDS['_test_command']='true'
    SHELTER_PATCHED_COMMAND_STRATEGIES['_test_command']='function'

    unpatch_command '_test_command'

    _negate_status declare -f '_test_command' &>/dev/null
    [[ -z "${SHELTER_PATCHED_COMMANDS['_test_command']:-}" ]]
    [[ -z "${SHELTER_PATCHED_COMMAND_STRATEGIES['_test_command']:-}" ]]
)

test_unpatch_command_mount_strategy () {
    declare cmd script

    if ! [[ "$(id -u)" -eq 0 ]]; then
        >&2 printf 'Need root privileges to run %s. Skipping\n' "${FUNCNAME[0]}"
        return 0
    fi

    cmd="${SHELTER_TEMP_DIR}/test_command"
    script="${SHELTER_TEMP_DIR}/test_command_script"

    touch "$cmd"
    touch "$script"

    mount --bind "$script" "$cmd"

    SHELTER_PATCHED_COMMANDS["$cmd"]="$script"
    SHELTER_PATCHED_COMMAND_STRATEGIES["$cmd"]='mount'

    unpatch_command "$cmd"

    _negate_status mountpoint -q "$cmd"
    _negate_status test -f "$script"
    [[ -z "${SHELTER_PATCHED_COMMANDS["$cmd"]:-}" ]]
    [[ -z "${SHELTER_PATCHED_COMMAND_STRATEGIES["$cmd"]:-}" ]]

    rm -f -- "$cmd"
}

test_unpatch_command_path_strategy () {
    cmd='test_command'
    script="${SHELTER_TEMP_DIR}/bin/test_command"

    touch "$script"

    SHELTER_PATCHED_COMMANDS["$cmd"]="$script"
    SHELTER_PATCHED_COMMAND_STRATEGIES["$cmd"]='path'

    unpatch_command "$cmd"

    _negate_status test -f "$script"
    [[ -z "${SHELTER_PATCHED_COMMANDS["$cmd"]:-}" ]]
    [[ -z "${SHELTER_PATCHED_COMMAND_STRATEGIES["$cmd"]:-}" ]]
}


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
