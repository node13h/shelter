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


# A very basic test runner tokeep it simple while
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
