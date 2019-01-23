#!/usr/bin/env bash

# MIT license
# Copyright 2018 Sergej Alikov <sergej.alikov@gmail.com>

## @file
## @author Sergej Alikov <sergej.alikov@gmail.com>
## @copyright MIT License
## @brief Shell-based testing framework

set -euo pipefail

declare -g SHELTER_SED_CMD
# We only support GNU sed
case "$(uname -s)" in
    FreeBSD|OpenBSD|Darwin)
        SHELTER_SED_CMD='gsed'
        ;;
    *)
        SHELTER_SED_CMD='sed'
        ;;
esac

if ! command -v "$SHELTER_SED_CMD" &>/dev/null; then
    printf 'Please install %s\n' "$SHELTER_SED_CMD"
fi

declare -g SHELTER_PROG_DIR
SHELTER_PROG_DIR=$(dirname "${BASH_SOURCE[0]:-}")

# shellcheck source=shelter-config.sh
source "${SHELTER_PROG_DIR%/}/shelter-config.sh"

declare -ri SHELTER_BLOCK_ROOT=0
declare -ri SHELTER_BLOCK_SUITES=1
declare -ri SHELTER_BLOCK_SUITE=2
declare -ri SHELTER_BLOCK_TESTCASE=3

declare -Ag SHELTER_PATCHED_COMMANDS=()
declare -Ag SHELTER_PATCHED_COMMAND_STRATEGIES=()

## @var SHELTER_FORMATTER_ERREXIT_ON
## @brief Set the error exit condition for the built-in formatters
## @details The following values are supported:
## - none Exit with 0 even when there are failing tests
## - failures-present Run all tests, exit with non-zero code if at least
##   one test has failed
## - first-failing Exit with non-zero code immediately after the first
##   failed test
declare -g SHELTER_FORMATTER_ERREXIT_ON='failures-present'

## @var SHELTER_SKIP_TEST_CASES
## @brief A list of test case commands to skip
## @details When set before executing test suites allows to skip
## certain test cases
declare -ag SHELTER_SKIP_TEST_CASES=()

# shellcheck disable=SC2034
# This variable is used internally by the assert_ functions
# It provides a side channel for assertion messages
[[ -n "${SHELTER_ASSERT_FD:-}" ]] || exec {SHELTER_ASSERT_FD}>&2

SHELTER_TEMP_DIR=$(mktemp -d)
declare -rg SHELTER_TEMP_DIR

mkdir "${SHELTER_TEMP_DIR}/bin"
PATH="${SHELTER_TEMP_DIR}/bin:${PATH}"

_shelter_cleanup_temp_dir () {
    declare name

    if [[ "${#SHELTER_PATCHED_COMMANDS[@]}" -gt 0 ]]; then
        for name in "${!SHELTER_PATCHED_COMMANDS[@]}"; do
            case "${SHELTER_PATCHED_COMMAND_STRATEGIES["$name"]:-}" in
                mount)
                    >&2 printf 'Removing %s patch_command mount\n' "$name"
                    umount "$name"
                    rm -f -- "${SHELTER_PATCHED_COMMANDS["$name"]}"
                    ;;
                path)
                    >&2 printf 'Removing %s patch_command path override\n' "${SHELTER_PATCHED_COMMANDS["$name"]}"
                    rm -f -- "${SHELTER_PATCHED_COMMANDS["$name"]}"
                    ;;

            esac
        done
    fi
}

_shelter_cleanup () {
    rmdir "${SHELTER_TEMP_DIR}/bin"
    rmdir "$SHELTER_TEMP_DIR"
}

trap _shelter_cleanup EXIT

_annotated_eval () {
    eval "$1" 2> >("$SHELTER_SED_CMD" -u "s/^/STDERR /") > >("$SHELTER_SED_CMD" -u "s/^/STDOUT /")
}

# This function is used internally to emit assertion messages
# to SHELTER_ASSERT_FD while retaining the exit code of a
# previous command.
# It may only be used inside another function!
# Exmaple:
#  $ exec {SHELTER_ASSERT_FD}>&1
#  $ test_fn () { bash -c 'exit 5' || _assert_msg 'FAILED!'; }
#  $ test_fn || rc="$?"
#  test_fn FAILED!
#  $ echo "$rc"
#  5
_assert_msg () {
    local rc="$?"
    local msg="$1"
    local assert_cmd="${FUNCNAME[1]}"

    printf '%s %s\n' "$assert_cmd" "$msg" >&"${SHELTER_ASSERT_FD}"
    return "$rc"
}

## @fn supported_shelter_versions ()
## @brief Return success if the current Shelter version matches at least one
## of the supplied versions
## @details Use this command to assert you are using a compatible version
## of Shelter framework by declaring a list of supported versions.
## This allows you to fail early when an unsupported version of Shelter is
## installed
## @param version version to match. Format is
## MAJOR or MAJOR.MINOR or MAJOR.MINOR.PATCH. May be specified multiple
## times
##
## Example:
##
## @code{.sh}
## supported_shelter_versions 0.5.0 0.6.1 1 2 4.9
## @endcode
supported_shelter_versions () {
    declare -r SEMVER_RE='^([0-9]+).([0-9]+).([0-9]+)(-([0-9A-Za-z.-]+))?(\+([0-9A-Za-z.-]))?$'
    declare -r VER_RE='^([0-9]+)(.([0-9]+))?(.([0-9]+))?$'

    if [[ "$SHELTER_VERSION" =~ $SEMVER_RE ]]; then

        declare major="${BASH_REMATCH[1]}"
        declare minor="${BASH_REMATCH[2]}"
        declare patch="${BASH_REMATCH[3]}"

        declare version

        for version in "$@"; do

            [[ "$version" =~ $VER_RE ]] || continue

            [[ "$major" -eq "${BASH_REMATCH[1]}" ]] || continue

            if [[ -n "${BASH_REMATCH[3]:+x}" ]]; then
                [[ "$minor" -eq "${BASH_REMATCH[3]}" ]] || continue
            fi

            if [[ -n "${BASH_REMATCH[5]:+x}" ]]; then
                [[ "$patch" -eq "${BASH_REMATCH[5]}" ]] || continue
            fi

            return 0
        done
    fi

    printf >&2 'Unsupported version %s of Shelter detected. Supported versions are: %s\n' \
               "$SHELTER_VERSION" \
               "$*"
    return 1
}

## @fn assert_stdout ()
## @brief Assert the STDOUT output of the supplied command matches the expected
## @details In case the STDOUT output does not match the expected one -
## a diff will be printed to STDOUT, an assertion name and message
## will be output to SHELTER_ASSERT_FD, and the function will exit
## with a non-zero exit code
## @param cmd command. Will be passed to 'eval'
## @param expected_file OPTIONAL. File containing the expected output.
## Use dash (the default) for STDIN. Process substitution will also work
## @param msg assertion message
##
## Examples
##
## Using process substitution
## @code{.sh}
## assert_stdout 'bc <<< 1+1' <(echo '2')
## @endcode
##
## Using STDIN to pass the expected output
## @code{.sh}
## assert_stdout 'bc << 1+1' <<< 2
## @endcode
assert_stdout () {
    declare cmd="$1"
    declare expected_file="${2:--}"
    declare msg="${3:-STDOUT of \"${cmd}\" does not match the contents of \"${expected_file}\"}"

    diff -du <(eval "$cmd") "$expected_file" || _assert_msg "$msg"
}

## @fn assert_success ()
## @brief Assert the command executes with a zero exit code
## @details If the supplied command fails - an assertion name and message
## will be output to SHELTER_ASSERT_FD and the function will exit
## with the same error code as the supplied command did
## @param cmd command. Will be passed to 'eval'
## @param msg OPTIONAL assertion message
##
## Example
##
## @code{.sh}
## assert_success 'systemctl -q is-active sshd' 'SSH daemon is not running!'
## @endcode
assert_success () {
    declare cmd="$1"
    declare msg="${2:-\"${cmd}\" failed}"

    declare -i rc

    set +e
    (
        set -e
        eval "$cmd"
    )
    rc="$?"
    set -e

    # shellcheck disable=SC2181
    [[ "$rc" -eq 0 ]] || _assert_msg "$msg"
}

## @fn assert_fail ()
## @brief Assert command executes with a non-zero exit code
## @details If the supplied command succeeds - an assertion name and message
## will be output to SHELTER_ASSERT_FD and the function will exit
## with a non-zero exit code
## @param cmd command. Will be passed to 'eval'
## @param exit_code OPTIONAL expected exit code.
## Must be greater than zero or an empty string (the default) which
## will match any non-zero exit code
## @param msg OPTIONAL assertion message
##
## Examples
##
## Catching specific exit code
## @code{.sh}
## assert_fail 'ls --invalid-arg' 2
## @endcode
##
## Catching any non-zero exit code
## @code{.sh}
## assert_fail 'systemctl -q is-enabled httpd' '' 'httpd service should be disabled'
## @endcode
assert_fail () {
    declare cmd="$1"
    declare exit_code="${2:-}"
    declare msg="${3:-\"${cmd}\" did not fail}"

    if [[ "$exit_code" = '0' ]]; then
        printf 'Invalid value for exit_code (%s)\n' "$exit_code" >&2
        return 1
    fi

    declare -i rc=0

    set +e
    (
        set -e
        eval "$cmd"
    )
    rc="$?"
    set -e

    if [[ -z "$exit_code" ]]; then
        [[ "$rc" -gt 0 ]] || _assert_msg "$msg"
    else
        [[ "$rc" -eq "$exit_code" ]] || _assert_msg "$msg"
    fi
}


## @fn assert_stdout_contains ()
## @brief Assert a line in STDOUT of the supplied command will match the regex
## @details In case none of the STDOUT lines match the regex -
## an assertion name and message will be output to SHELTER_ASSERT_FD,
## and the function will exit with a non-zero exit code
## @param cmd command. Will be passed to 'eval'
## @param regex. Regex to match (ERE)
##
## Example
##
## @code{.sh}
## assert_stdout_contains 'echo Hello World' 'World$'
## @endcode
assert_stdout_contains () {
    declare cmd="$1"
    declare regex="${2}"
    declare msg="${3:-STDOUT of \"${cmd}\" does not contain \"${regex}\"}"

    grep -E "$regex" <(eval "$cmd") &>/dev/null || _assert_msg "$msg"
}


## @fn assert_stdout_not_contains ()
## @brief Assert none of the STDOUT lines will match the regex
## @details In case of a match - an assertion name and message
## will be output to SHELTER_ASSERT_FD, and the function will
## exit with a non-zero exit code
## @param cmd command. Will be passed to 'eval'
## @param regex. Regex to match (ERE)
##
## Example
##
## @code{.sh}
## assert_stdout_not_contains 'echo Hello World' 'foo'
## @endcode
assert_stdout_not_contains () {
    declare cmd="$1"
    declare regex="${2}"
    declare msg="${3:-STDOUT of \"${cmd}\" contains \"${regex}\"}"

    ! grep -E "$regex" <(eval "$cmd") &>/dev/null || _assert_msg "$msg"
}


## @fn shelter_run_test_case ()
## @brief Run a command in an isolated environment and return an annotated output
## @details The command is executed with errexit and nounset enabled.
## STDOUT and STDERR are processed by separate threads, therefore might
## be slightly out of order in relation to each other. Ordering within a
## single stream (STDOUT or STDERR) is guaranteed to be correct.
## The output is machine-readable.
## @param cmd command. Will be passed to 'eval'
##
## Example (number of variables reduced for clarity)
##
## @code{.sh}
## $ shelter_run_test_case 'echo Hi; echo Bye >&2; echo Hi again'
## CMD echo Hi; echo Bye >&2; echo Hi again
## ENV BASH declare\ --\ BASH=\"/usr/bin/bash\"
## ENV TERM declare\ --\ TERM=\"dumb\"
## ENV TIMEFORMAT declare\ --\ TIMEFORMAT=\"%R\"
## ENV UID declare\ -ir\ UID=\"1000\"
## ENV _ declare\ --\ _=\"var\"
## EXIT 0
## TIME 0.009
## STDOUT 1 Hi
## STDERR 2 Bye
## STDOUT 3 Hi again
## @endcode
shelter_run_test_case () {
    if [[ "${#SHELTER_SKIP_TEST_CASES[@]}" -gt 0 ]]; then
        declare cmd
        for cmd in "${SHELTER_SKIP_TEST_CASES[@]}"; do
            if [[ "$cmd" = "$1" ]]; then
                printf 'SKIPPED %s\n' "$1"
                return 0
            fi
        done
    fi

    printf 'CMD %s\n' "$1"

    declare var

    while read -r var; do
        printf 'ENV %s %q\n' "$var" "$(declare -p "$var")"
    done < <(compgen -A variable)

    unset var

    {
        {
            TIMEFORMAT=%R

            # Backup shell options. errexit is propagated to process
            # substitutions, therefore no special handling is needed

            declare -a shelter_shopt_backup
            readarray -t shelter_shopt_backup < <(shopt -po)

            set +e

            # sequence numbers added by the last component allow
            # user to perform sorting (sort -V) to split STDOUT and STDERR into
            # separate blocks (preserving the correct order within the block)
            # and reassemble back into a single block later (sort -V -k 2).
            time eval '(set -eu; unset TIMEFORMAT shelter_shopt_backup; trap "_annotated_eval _shelter_cleanup_temp_dir" EXIT; _annotated_eval "$1")' \
                | { grep -n '' || true; } \
                | "$SHELTER_SED_CMD" -u 's/^\([0-9]\+\):\(STDOUT\|STDERR\) /\2 \1 /'

            declare rc="$?"

            # Restore shell options
            declare cmd
            for cmd in "${shelter_shopt_backup[@]}"; do
                eval "$cmd"
            done

        } 2> >("$SHELTER_SED_CMD" -u "s/^/TIME /") {SHELTER_ASSERT_FD}> >("$SHELTER_SED_CMD" -u "s/^/ASSERT /")

        printf 'EXIT %s\n' "$rc"

    } | cat  ## Synchronize all async output processors, otherwise some output (such as "TIME") may be sent to a consumer _after_ this function has completed execution, possible interfering with the output of the output of the subsequent test
}


## @fn shelter_run_test_class ()
## @brief Run a pattern-based list of functions as test cases
## @details Pass every function name starting with a specified prefix to
## the shelter_run_test_case command. A line containing "CLASS $class_name"
## will be added to the end of every test case output block
## @param class_name class name
## @param fn_prefix function prefix. All functions starting with
## this prefix (in the current scope) will be executed.
##
## Example (assumes there are "test_1" and "test_2" functions.
## Outut reduced for clarity)
##
## @code{.sh}
## $ shelter_run_test_class testclass test_
## CMD test_1
## ...
## CLASS testclass
## CMD test_2
## ...
## CLASS testclass
## @endcode
shelter_run_test_class () {
    declare fn

    while read -r fn; do
        shelter_run_test_case "$fn"
        printf 'CLASS %s\n' "$1"
    done < <(compgen -A function "$2")
}


## @fn shelter_run_test_suite ()
## @brief Run a command which runs multiple tests cases as a test suite
## @details Suite data starting with a SUITE-* set of
## keywords will be added at the top
## @param cmd command. Will be passed to 'eval'
##
## Example (assumes there is a "suite_1" command which executes
## "shelter_run_test_case test_1" and "shelter_run_test_case test_2" commands.
## Outut reduced for clarity)
##
## @code{.sh}
## $ shelter_run_test_suite suite_1
## SUITE ERRORS 1
## SUITE FAILURES 0
## SUITE NAME suite_1
## SUITE SKIPPED 0
## SUITE TESTS 2
## SUITE TIME 1.51
## CMD test_1
## EXIT 0
## TIME 0.01
## ...
## CMD test_2
## EXIT 1
## TIME 1.5
## ...
## @endcode
shelter_run_test_suite () {
    declare -i shelter_suite_tests=0
    declare -i shelter_suite_errors=0
    declare -i shelter_suite_failures=0
    declare -i shelter_suite_skipped=0
    declare -i shelter_suite_line=1
    declare shelter_suite_time='0.0'

    declare key
    declare value

    {
        printf '0 SUITE_NAME %s\n' "$1"

        while read -r key value; do
            case "$key" in
                CMD)
                    shelter_suite_tests+=1
                    ;;
                SKIPPED)
                    shelter_suite_tests+=1
                    shelter_suite_skipped+=1
                    ;;
                EXIT)
                    [[ "$value" = '0' ]] || shelter_suite_errors+=1
                    ;;
                ASSERT)
                    shelter_suite_failures+=1
                    ;;
                TIME)
                    shelter_suite_time=$(bc <<< "$shelter_suite_time + $value" | "$SHELTER_SED_CMD" 's/^\./0./')
                    ;;
            esac

            printf '%d %s %s\n' "$shelter_suite_line" "$key" "$value"

            shelter_suite_line+=1

        done < <(unset shelter_suite_tests shelter_suite_errors shelter_suite_failures shelter_suite_skipped shelter_suite_line shelter_suite_time; eval "$1")

        printf '0 SUITE_TESTS %s\n' "$shelter_suite_tests"
        printf '0 SUITE_ERRORS %s\n' "$((shelter_suite_errors - shelter_suite_failures))"
        printf '0 SUITE_FAILURES %s\n' "$shelter_suite_failures"
        printf '0 SUITE_SKIPPED %s\n' "$shelter_suite_skipped"
        printf '0 SUITE_TIME %s\n' "$shelter_suite_time"

    } | sort -n | "$SHELTER_SED_CMD" -u 's/^[0-9]\+ //'
}


## @fn shelter_run_test_suites ()
## @brief Run a pattern-based list of functions as test suites
## @details Pass every function name starting with a specified prefix to
## the shelter_run_test_suite command. Aggregated suite data starting
## with a SUITES-* set of keywords will be added at the top
## @param name a name of the collection
## @param fn_prefix function prefix. All functions starting with
## this prefix (in the current scope) will be executed.
##
## Example (assumes there is a "suite_1" command which executes
## "shelter_run_test_case test_1" and "shelter_run_test_case test_2" commands,
## and a "suite_2" command which executes "shelter_run_test_case test_3"
## command. Outut reduced for clarity)
##
## @code{.sh}
## $ shelter_run_test_suites 'A collection' suite_
## SUITES-ERRORS 1
## SUITES-FAILURES 0
## SUITES-NAME A collection
## SUITES-SKIPPED 0
## SUITES-TESTS 3
## SUITES-TIME 1.5
## SUITE-ERRORS 1
## SUITE-FAILURES 0
## SUITE-NAME suite_1
## SUITE-SKIPPED 0
## SUITE-TESTS 2
## SUITE-TIME 1
## CMD cmd_1
## EXIT 0
## TIME 0.4
## ...
## CMD cmd_2
## EXIT 1
## TIME 0.6
## ...
## SUITE-ERRORS 0
## SUITE-FAILURES 0
## SUITE-NAME suite_2
## SUITE-SKIPPED 0
## SUITE-TESTS 2
## SUITE-TIME 0.5
## CMD cmd_3
## EXIT 0
## TIME 0.5
## ...
## @endcode
shelter_run_test_suites () {
    declare -i shelter_suites_tests=0
    declare -i shelter_suites_errors=0
    declare -i shelter_suites_failures=0
    declare -i shelter_suites_line=1
    declare shelter_suites_time='0.0'

    declare fn

    declare key
    declare value

    {
        printf '0 SUITES_NAME %s\n' "$1"

        while read -r fn; do

            while read -r key value; do
                case "$key" in
                    SUITE_ERRORS)
                        shelter_suites_errors+="$value"
                        ;;
                    SUITE_FAILURES)
                        shelter_suites_failures+="$value"
                        ;;
                    SUITE_TESTS)
                        shelter_suites_tests+="$value"
                        ;;
                    SUITE_TIME)
                        shelter_suites_time=$(bc <<< "$shelter_suites_time + $value" | "$SHELTER_SED_CMD" 's/^\./0./')
                        ;;
                esac

                printf '%d %s %s\n' "$shelter_suites_line" "$key" "$value"

                shelter_suites_line+=1

            done < <(unset shelter_suites_tests shelter_suites_errors shelter_suites_failures shelter_suites_line shelter_suites_time; shelter_run_test_suite "$fn")

        done < <(compgen -A function "$2")

        printf '0 SUITES_TESTS %s\n' "$shelter_suites_tests"
        printf '0 SUITES_ERRORS %s\n' "$shelter_suites_errors"
        printf '0 SUITES_FAILURES %s\n' "$shelter_suites_failures"
        printf '0 SUITES_TIME %s\n' "$shelter_suites_time"

    } | sort -n | "$SHELTER_SED_CMD" -u 's/^[0-9]\+ //'
}

# This function is used internally to handle
# transitions between blocks while parsing
# It may only be used in an environment which defines the
# following functions:
# - output_suites_open
# - output_suites_close
# - output_suite_open
# - output_suite_close
# - output_testcase_open
# - output_testcase_body
# - output_testcase_close
# - output_body_add_error
_shelter_formatter_block_transition () {
    declare next_block="$1"

    case "$block" in
        "$SHELTER_BLOCK_ROOT")
            case "$next_block" in
                "$SHELTER_BLOCK_SUITES")
                    # shellcheck disable=SC2154
                    flags[suites]=1
                    ;;
                "$SHELTER_BLOCK_SUITE")
                    # shellcheck disable=SC2154
                    flags[suite]=1
                    ;;
            esac
            ;;

        "$SHELTER_BLOCK_SUITES")
            output_suites_open

            case "$next_block" in
                "$SHELTER_BLOCK_ROOT")
                    output_suites_close
                    flags[suites]=0
                    ;;
                "$SHELTER_BLOCK_SUITES")
                    output_suites_close
                    flags[suites]=1
                    ;;
                "$SHELTER_BLOCK_SUITE")
                    flags[suite]=1
                    ;;
            esac
            ;;

        "$SHELTER_BLOCK_SUITE")
            output_suite_open

            case "$next_block" in
                "$SHELTER_BLOCK_ROOT")
                    output_suite_close
                    flags[suite]=0
                    if [[ "${flags[suites]:-0}" -eq 1 ]]; then
                        output_suites_close
                        flags[suites]=0
                    fi
                    ;;
                "$SHELTER_BLOCK_SUITES")
                    output_suite_close
                    flags[suite]=0
                    if [[ "${flags[suites]:-0}" -eq 1 ]]; then
                        output_suites_close
                    fi
                    ;;
                "$SHELTER_BLOCK_SUITE")
                    output_suite_close
                    flags[suite]=1
                    ;;
            esac
            ;;

        "$SHELTER_BLOCK_TESTCASE")

            output_testcase_open
            if [[ "${flags[status]:-}" = error ]]; then
                output_body_add_error
            fi
            output_testcase_body
            output_testcase_close

            case "$next_block" in
                "$SHELTER_BLOCK_ROOT")
                    if [[ "${flags[suite]:-0}" -eq 1 ]]; then
                        output_suite_close
                        flags[suite]=0
                    fi
                    if [[ "${flags[suites]:-0}" -eq 1 ]]; then
                        output_suites_close
                        flags[suites]=0
                    fi
                    ;;
                "$SHELTER_BLOCK_SUITES")
                    if [[ "${flags[suite]:-0}" -eq 1 ]]; then
                        output_suite_close
                        flags[suite]=0
                    fi
                    flags[suite]=0
                    if [[ "${flags[suites]:-0}" -eq 1 ]]; then
                        output_suites_close
                    fi
                    flags[suites]=1
                    ;;
                "$SHELTER_BLOCK_SUITE")
                    if [[ "${flags[suite]:-0}" -eq 1 ]]; then
                        output_suite_close
                    fi
                    flags[suite]=1
                    ;;
            esac
            ;;
    esac

    block="$next_block"
    attributes=()
    body=()
    stdout=()
    stderr=()
    unset 'flags[status]'
}

# This function is used internally as a
# generic formatter
# It may only be used in an environment which defines the
# following functions:
# - output_header
# - output_body_add_skipped
# - output_body_add_failure
# - output_stdout_add_line
# - output_stdout_add_line
_shelter_formatter () {
    # shellcheck disable=SC2034
    declare block="$SHELTER_BLOCK_ROOT"

    declare -A attributes=()
    # shellcheck disable=SC2034
    declare -a body=()
    declare -a stdout=()
    declare -a stderr=()
    declare -A flags=()

    declare -i error_counter=0
    declare -i failure_counter=0

    declare transition_to
    declare lineno line

    output_header

    while read -r key value; do

        unset transition_to

        # Keys which are allowed to change the block
        case "$key" in
            SUITES_NAME)
                transition_to="$SHELTER_BLOCK_SUITES"
                ;;
            SUITE_NAME)
                transition_to="$SHELTER_BLOCK_SUITE"
                ;;
            CMD|SKIPPED)
                transition_to="$SHELTER_BLOCK_TESTCASE"
                ;;
        esac

        if [[ -n "${transition_to:-}" ]]; then
            if ! [[ "$error_counter" -eq 0 && "$failure_counter" -eq 0 ]] && [[ "$SHELTER_FORMATTER_ERREXIT_ON" = 'first-failing' ]]; then
                break
            fi

            _shelter_formatter_block_transition "$transition_to"
        fi

        case "$key" in
            SKIPPED)
                flags[status]=skipped
                output_body_add_skipped
                ;&
            SUITES_*|SUITE_*|CMD|CLASS|TIME)
                attributes["${ATTRIBUTE_MAP["$key"]}"]="$value"
                ;;
            EXIT)
                attributes[status]="$value"
                if [[ "$value" -eq 0 ]]; then
                    [[ "${flags[status]:-}" = failure ]] || flags[status]=success
                else
                    if ! [[ "${flags[status]:-}" = failure ]]; then
                        flags[status]=error
                        error_counter=$((error_counter+1))
                    fi
                fi
                ;;
            ASSERT)
                flags[status]=failure
                failure_counter=$((failure_counter+1))
                output_body_add_failure "${value%% *}" "${value#* }"
                ;;
            STDOUT)
                read -r lineno line <<< "$value"
                stdout["$lineno"]="$line"
                ;;
            STDERR)
                read -r lineno line <<< "$value"
                stderr["$lineno"]="$line"
                ;;
        esac

    done

    _shelter_formatter_block_transition "$SHELTER_BLOCK_ROOT"

    output_footer

    if ! [[ "$SHELTER_FORMATTER_ERREXIT_ON" = 'none' ]]; then
        [[ "$failure_counter" -eq 0 ]] || return 1
        [[ "$error_counter" -eq 0 ]] || return 2
    fi
}

# shellcheck disable=SC2030,SC2031
## @fn shelter_junit_formatter ()
## @brief Format output of the test runner as JUnit XML
##
## Examples
##
## @code{.sh}
## {
##     shelter_run_test_case foo
##     shelter_run_test_case bar
##     shelter_run_test_class SuccessfulTests test_good_
##     shelter_run_test_class FailingTests test_bad_
## } | shelter_junit_formatter
## @endcode
##
## @code{.sh}
## shelter_run_test_suite suite_1 | shelter_unit_formatter
## @endcode
shelter_junit_formatter () {
    (
        declare -rA ATTRIBUTE_MAP=(
            [SUITES_ERRORS]=errors
            [SUITES_FAILURES]=failures
            [SUITES_NAME]=name
            [SUITES_TESTS]=tests
            [SUITES_TIME]=time
            [SUITE_ERRORS]=errors
            [SUITE_FAILURES]=failures
            [SUITE_NAME]=name
            [SUITE_SKIPPED]=skipped
            [SUITE_TESTS]=tests
            [SUITE_TIME]=time
            [CMD]=name
            [CLASS]=classname
            [SKIPPED]=name
            [TIME]=time
        )

        output_header () {
            printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        }

        xml_escaped () {
            "$SHELTER_SED_CMD" -e 's/\&/\&amp;/g' \
                               -e 's/</\&lt;/g' \
                               -e 's/>/\&gt;/g' \
                               -e 's/"/\&quot;/g' \
                               -e "s/'/\\&apos;/g"
        }

        xml_attributes () {
            declare item
            declare -i first_item=1

            [[ "${#attributes[@]}" -gt 0 ]] || return 0

            while read -r item; do
                if [[ "$first_item" -eq 1 ]]; then
                    first_item=0
                else
                    printf ' '
                fi

                printf '%s="%s"' "$item" "$(xml_escaped <<< "${attributes["$item"]}")"
            done < <(for index in "${!attributes[@]}"; do printf '%s\n' "$index"; done | sort)

            printf '\n'
        }

        output_suites_open () {
            printf '<testsuites %s>\n' "$(xml_attributes)"
        }

        output_suite_open () {
            printf '<testsuite %s>\n' "$(xml_attributes)"
        }

        output_testcase_open () {
            printf '<testcase %s>\n' "$(xml_attributes)"
        }

        output_testcase_body () {
            declare item

            if [[ "${#body[@]}" -gt 0 ]]; then
                for item in "${body[@]}"; do
                    printf '%s\n' "$item"
                done
            fi

            output_testcase_stdout
            output_testcase_stderr
        }

        output_testcase_stdout () {
            declare -i i

            [[ "${#stdout[@]}" -gt 0 ]] || return 0

            printf '<system-out>\n'
            for i in "${!stdout[@]}"; do
                printf '%s %s\n' "$i" "$(xml_escaped <<< "${stdout["$i"]}")"
            done
            printf '</system-out>\n'
        }

        output_testcase_stderr () {
            declare -i i

            [[ "${#stderr[@]}" -gt 0 ]] || return 0

            printf '<system-err>\n'
            for i in "${!stderr[@]}"; do
                printf '%s %s\n' "$i" "$(xml_escaped <<< "${stderr["$i"]}")"
            done
            printf '</system-err>\n'
        }

        output_testcase_close () {
            printf '</testcase>\n'
        }

        output_suites_close () {
            printf '</testsuites>\n'
        }

        output_suite_close () {
            printf '</testsuite>\n'
        }

        output_body_add_failure () {
            declare type="$1"
            declare message="$2"

            # shellcheck disable=SC2034
            declare -A attributes=([type]="$type" [message]="$message")

            body+=("<failure $(xml_attributes)></failure>")
        }

        output_body_add_skipped () {
            body+=('<skipped></skipped>')
        }

        output_body_add_error () {
            body+=('<error></error>')
        }

        output_footer () {
            true
        }

        _shelter_formatter

    )
}

# shellcheck disable=SC2030,SC2031
## @fn shelter_human_formatter ()
## @brief Format output of the test runner in a human-friendly form
##
## Examples
##
## @code{.sh}
## {
##     shelter_run_test_case foo
##     shelter_run_test_case bar
##     shelter_run_test_class SuccessfulTests test_good_
##     shelter_run_test_class FailingTests test_bad_
## } | shelter_human_formatter
## @endcode
##
## @code{.sh}
## shelter_run_test_suite suite_1 | shelter_human_formatter
## @endcode
shelter_human_formatter () {
    (
        declare -rA ATTRIBUTE_MAP=(
            [SUITES_ERRORS]=errors
            [SUITES_FAILURES]=failures
            [SUITES_NAME]=name
            [SUITES_TESTS]=tests
            [SUITES_TIME]=time
            [SUITE_ERRORS]=errors
            [SUITE_FAILURES]=failures
            [SUITE_NAME]=name
            [SUITE_SKIPPED]=skipped
            [SUITE_TESTS]=tests
            [SUITE_TIME]=time
            [CMD]=name
            [CLASS]=classname
            [SKIPPED]=name
            [TIME]=time
        )

        declare -rA STATUS_MAP=(
            [success]='+'
            [error]='E'
            [failure]='F'
            [skipped]='-'
        )

        declare -rA COLOUR_MAP=(
            [success]=92
            [error]=31
            [failure]=91
            [skipped]=90
        )

        declare -A TEST_RESULTS=(
            [success]=0
            [error]=0
            [failure]=0
            [skipped]=0
        )

        declare -i first_suite=1

        indentation_level () {
            declare -i level="$1"

            declare -i i

            for ((i=1; i<="$level"; i++)); do
                printf ' '
            done
            printf '\n'
        }

        output_header () {
            true
        }

        output_suites_open () {
            printf 'Suites: %s\n\n' "${attributes[name]}"
        }

        output_suite_open () {
            if [[ "$first_suite" -eq 1 ]]; then
                first_suite=0
            else
                printf '\n'
            fi

            declare indent
            indent=$(indentation_level "${flags[suites]:-0}")
            printf '%sSuite: %s (%ss)\n\n' "$indent" "${attributes[name]}" "${attributes[time]}"
        }

        output_testcase_open () {
            declare indent
            indent=$(indentation_level $(("${flags[suites]:-0}" + "${flags[suite]:-0}")))

            declare -a components=(
                "$indent"
                "${COLOUR_MAP["${flags[status]}"]}"
                "${STATUS_MAP["${flags[status]}"]}"
                "${attributes[classname]:+${attributes[classname]}/}${attributes[name]}"
            )

            if [[ -n "${attributes[status]:-}" && "${attributes[status]}" -gt 0 ]]; then
                components+=(" (exit [1;31m${attributes[status]}[m)")
            else
                components+=('')
            fi

            if ! [[ "${flags[status]}" = 'skipped' ]]; then
                components+=(" (${attributes[time]}s)")
            else
                components+=('')
            fi

            printf '%s[\e[1;%sm%s\e[m] \e[1;97m%s\e[m%s%s\n' "${components[@]}"
        }

        output_testcase_body () {
            declare -i i=1
            declare indent
            indent=$(indentation_level $(("${flags[suites]:-0}" + "${flags[suite]:-0}")))

            declare item

            if [[ "${#body[@]}" -gt 0 ]]; then
                for item in "${body[@]}"; do
                    printf '%s    %s\n' "$indent" "$item"
                done
                printf '\n'
            fi

            TEST_RESULTS["${flags[status]}"]=$((TEST_RESULTS["${flags[status]}"] + 1))

            if [[ "${#stdout[@]}" -gt 0 || "${#stderr[@]}" -gt 0 ]]; then
                printf '%s    captured output:\n' "$indent"
                printf '%s    ---------------\n' "$indent"
                while true; do
                    if [[ "${stdout["$i"]+defined}" = 'defined' ]]; then
                        printf '%s    \e[0;90m%s\e[m\n' "$indent" "${stdout["$i"]}"
                    elif [[ "${stderr["$i"]+defined}" = 'defined' ]]; then
                        printf '%s    \e[0;33m%s\e[m\n' "$indent" "${stderr["$i"]}"
                    else
                        break
                    fi

                    i=$((i+1))
                done
                printf '\n'
            fi
         }

        output_testcase_close () {
            true
        }

        output_suites_close () {
            true
        }

        output_suite_close () {
            true
        }

        output_body_add_failure () {
            declare type="$1"
            declare message="$2"

            body+=("[1;91m${message}[m (${type})")
        }

        output_body_add_skipped () {
            true
        }

        output_body_add_error () {
            true
        }

        output_footer () {
            printf '\nTest results: %d passed, %d failed, %d errors, %d skipped\n' "${TEST_RESULTS[success]}" "${TEST_RESULTS[failure]}" "${TEST_RESULTS[error]}" "${TEST_RESULTS[skipped]}"
        }

        _shelter_formatter
    )
}


## @fn patch_command ()
## @brief Overload a command with a mock
## @details There are multiple patching strategies available, see below
## @param strategy patch method. Use 'function', 'mount' or 'path'
## @param name name or path of the command to patch
## @param cmd command to execute when `name` is called. Will be passed to `eval`
##
## Strategies
##
## function. Define function with the same name as the mocked command.
## Will only work in a shell. `name` argument may not contain a path in
## this case. This method will only work if the mocked command is called
## using it's name withot a path. Will override shell built-ins
##
## mount. Create a temporary script and mount it over the actual command.
## While this is the most reliable mocking method - it also requires the
## root privileges and mocks the command systemwide. `name` argument must be set
## to a full path of the mocked command (i.e. `/usr/bin/echo`)
##
## path. Create a temporary script with the same name as the mocked command
## in a temporary directory prepended to the `PATH`. Will only affect the
## current process and it's children. This method will only work if the mocked
## command is called using it's name withot a path. Will not override shell
## built-ins
##
## Examples (every example will output "Hello World")
##
## @code{.sh}
## patch_command function echo 'printf "Hello %s" "$1"'
## echo World
## @endcode
##
## This one needs root privileges
## @code{.sh}
## patch_command mount /usr/bin/echo 'printf "Hello %s" "$1"'
## /usr/bin/echo World
## @endcode
##
## `env` is used to prevent shell built-in from being used
## @code{.sh}
## patch_command path echo 'printf "Hello %s" "$1"'
## env echo World
## @endcode
patch_command () {
    declare strategy="$1"
    declare name="$2"
    declare cmd="$3"

    declare script

    if [[ -n "${SHELTER_PATCHED_COMMANDS["$name"]:-}" ]]; then
        printf 'Command %s is already patched\n' "$name" >&2
        return 1
    fi

    case "$strategy" in
        function)
            script="${name} () { ${cmd}; }"

            eval "$script"
            # shellcheck disable=SC2163
            export -f "$name"

            SHELTER_PATCHED_COMMANDS["$name"]="$script"
            ;;
        mount)
            script=$(mktemp --tmpdir="$SHELTER_TEMP_DIR")
            cat >"$script" <<EOF
#!/usr/bin/env bash

set -euo pipefail

$cmd
EOF
            chmod 755 "$script"
            if mount --bind "$script" "$name"; then
                SHELTER_PATCHED_COMMANDS["$name"]="$script"
            else
                rm -f -- "$script"
                return 1
            fi
            ;;
        path)
            script="${SHELTER_TEMP_DIR}/bin/${name}"
            cat >"$script" <<EOF
#!/usr/bin/env bash

set -euo pipefail

$cmd
EOF
            chmod 755 "$script"
            SHELTER_PATCHED_COMMANDS["$name"]="$script"
            ;;
        *)
            printf 'Unsupported strategy %s\n' "$strategy" >&2
            return 1
            ;;
    esac

    SHELTER_PATCHED_COMMAND_STRATEGIES["$name"]="$strategy"
}


## @fn unpatch_command ()
## @brief Restore the original command patched with `patch_command`
## @param name exactly the same name as was provided to `patch_command`
unpatch_command () {
    declare name="$1"

    if [[ -z "${SHELTER_PATCHED_COMMANDS["$name"]:-}" ]]; then
        printf 'Command %s is not patched\n' "$name" >&2
        return 1
    fi

    case "${SHELTER_PATCHED_COMMAND_STRATEGIES["$name"]}" in
        function)
            unset -f "$name"
            ;;
        mount)
            umount "$name"
            rm -f -- "${SHELTER_PATCHED_COMMANDS["$name"]}"
            ;;
        path)
            rm -f -- "${SHELTER_PATCHED_COMMANDS["$name"]}"
            ;;
        *)
            printf 'Unsupported strategy %s\n' "$strategy" >&2
            return 1
            ;;
    esac

    unset SHELTER_PATCHED_COMMANDS["$name"]
    unset SHELTER_PATCHED_COMMAND_STRATEGIES["$name"]
}
