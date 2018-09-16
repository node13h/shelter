#!/usr/bin/env bash

# MIT license
# Copyright 2018 Sergej Alikov <sergej.alikov@gmail.com>

## @file
## @author Sergej Alikov <sergej.alikov@gmail.com>
## @copyright MIT License
## @brief Shell-based testing framework

set -euo pipefail

declare -ri SHELTER_BLOCK_ROOT=0
declare -ri SHELTER_BLOCK_SUITES=1
declare -ri SHELTER_BLOCK_SUITE=2
declare -ri SHELTER_BLOCK_TESTCASE=3

## @var SHELTER_SKIP_TEST_CASES
## @brief A list of test case commands to skip
## @details When set before executing test suites allows to skip
## certain test cases
declare -ag SHELTER_SKIP_TEST_CASES=()

# shellcheck disable=SC2034
# This variable is used internally by the assert_ functions
# It provides a side channel for assertion messages
[[ -n "${SHELTER_ASSERT_FD:-}" ]] || exec {SHELTER_ASSERT_FD}>&2


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

## @fn assert_stdout ()
## @brief Assert the STDOUT output of the supplied command matches the expected
## @details In case the STDOUT output does not match the expected one -
## a diff will be printed to STDOUT, an assertion name and message
## will be output to SHELTER_ASSERT_FD, and the function will exit
## with a non-zero exit code
## @param cmd command. Will be passed to 'eval'
## @param OPTIONAL expected_file. File containing the expected output.
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

    eval "$cmd" || _assert_msg "$msg"
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

    declare rc=0

    eval "$cmd" || rc="$?"

    if [[ -z "$exit_code" ]]; then
        [[ "$rc" -gt 0 ]] || _assert_msg "$msg"
    else
        [[ "$rc" -eq "$exit_code" ]] || _assert_msg "$msg"
    fi
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
            time eval '(set -eu; unset TIMEFORMAT shelter_shopt_backup; eval "$1" 2> >(sed -u "s/^/STDERR /") > >(sed -u "s/^/STDOUT /"))' \
                | { grep -n '' || true; } \
                | sed -u 's/^\([0-9]\+\):\(STDOUT\|STDERR\) /\2 \1 /'

            declare rc="$?"

            # Restore shell options
            declare cmd
            for cmd in "${shelter_shopt_backup[@]}"; do
                eval "$cmd"
            done

        } 2> >(sed -u "s/^/TIME /") {SHELTER_ASSERT_FD}> >(sed -u "s/^/ASSERT /")

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
                    shelter_suite_time=$(bc <<< "$shelter_suite_time + $value" | sed 's/^\./0./')
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

    } | sort -n | sed -u 's/^[0-9]\+ //'
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
    declare -i shelter_suites_skipped=0
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
                    SUITE_SKIPPED)
                        shelter_suites_skipped+="$value"
                        ;;
                    SUITE_TESTS)
                        shelter_suites_tests+="$value"
                        ;;
                    SUITE_TIME)
                        shelter_suites_time=$(bc <<< "$shelter_suites_time + $value" | sed 's/^\./0./')
                        ;;
                esac

                printf '%d %s %s\n' "$shelter_suites_line" "$key" "$value"

                shelter_suites_line+=1

            done < <(unset shelter_suites_tests shelter_suites_errors shelter_suites_failures shelter_suites_skipped shelter_suites_line shelter_suites_time; shelter_run_test_suite "$fn")

        done < <(compgen -A function "$2")

        printf '0 SUITES_TESTS %s\n' "$shelter_suites_tests"
        printf '0 SUITES_ERRORS %s\n' "$shelter_suites_errors"
        printf '0 SUITES_FAILURES %s\n' "$shelter_suites_failures"
        printf '0 SUITES_SKIPPED %s\n' "$shelter_suites_skipped"
        printf '0 SUITES_TIME %s\n' "$shelter_suites_time"

    } | sort -n | sed -u 's/^[0-9]\+ //'
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
            output_testcase_stdout
            output_testcase_stderr
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

    output_header

    while read -r key value; do

        # Keys which are allowed to change the block
        case "$key" in
            SUITES_NAME)
                _shelter_formatter_block_transition "$SHELTER_BLOCK_SUITES"
                ;;
            SUITE_NAME)
                _shelter_formatter_block_transition "$SHELTER_BLOCK_SUITE"
                ;;
            CMD|SKIPPED)
                _shelter_formatter_block_transition "$SHELTER_BLOCK_TESTCASE"
                ;;
        esac


        case "$key" in
            SKIPPED)
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
                    [[ "${flags[status]:-}" = failure ]] || flags[status]=error
                fi
                ;;
            ASSERT)
                flags[status]=failure
                output_body_add_failure "${value%% *}" "${value#* }"
                ;;
            STDOUT)
                output_stdout_add_line "$value"
                ;;
            STDERR)
                output_stderr_add_line "$value"
                ;;
        esac

    done

    _shelter_formatter_block_transition "$SHELTER_BLOCK_ROOT"
}

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
            [SUITES_SKIPPED]=skipped
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
            sed -e 's/\&/\&amp;/g' \
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

            [[ "${#body[@]}" -gt 0 ]] || return 0

            for item in "${body[@]}"; do
                printf '%s\n' "$item"
            done
        }

        output_testcase_stdout () {
            declare item

            [[ "${#stdout[@]}" -gt 0 ]] || return 0

            printf '<system-out>\n'
            for item in "${stdout[@]}"; do
                printf '%s\n' "$(xml_escaped <<< "${item}")"
            done
            printf '</system-out>\n'
        }

        output_testcase_stderr () {
            declare item

            [[ "${#stderr[@]}" -gt 0 ]] || return 0

            printf '<system-err>\n'
            for item in "${stderr[@]}"; do
                printf '%s\n' "$(xml_escaped <<< "${item}")"
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

        output_stdout_add_line () {
            declare message="$1"

            stdout+=("$message")
        }

        output_stderr_add_line () {
            declare message="$1"

            stderr+=("$message")
        }

        _shelter_formatter

    )
}
