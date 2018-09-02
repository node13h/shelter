#!/usr/bin/env bash

# MIT license
# Copyright 2018 Sergej Alikov <sergej.alikov@gmail.com>

## @file
## @author Sergej Alikov <sergej.alikov@gmail.com>
## @copyright MIT License
## @brief Shell script (Bash) unit-testing framework

set -euo pipefail

## @fn assert_stdout ()
## @brief Assert command's STDOUT output matches the expected one
## @details In case STDOUT output does not match the expected -
## a diff will be printed to STDERR and the command will exit
## with a non-zero exit code
## @param cmd command. Will be passed to 'eval'
## @param expected_file OPTIONAL file containing the expected output.
## If not specified STDIN will be used
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

    diff -du <(eval "$cmd") "$expected_file" >&2
}


## @fn shute_run_test_case ()
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
## $ shute_run_test_case 'echo Hi; echo Bye >&2; echo Hi again'
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
shute_run_test_case () {
    printf 'CMD %s\n' "$1"

    declare var

    while read -r var; do
        printf 'ENV %s %q\n' "$var" "$(declare -p "$var")"
    done < <(compgen -A variable)

    unset var

    {
        TIMEFORMAT=%R

        # Backup shell options. errexit is propagated to process
        # substitutions, therefore no special handling is needed

        declare -a shute_shopt_backup
        readarray -t shute_shopt_backup < <(shopt -po)

        set +e

        # sequence numbers added by the last component allow
        # user to perform sorting (sort -V) to split STDOUT and STDERR into
        # separate blocks (preserving the correct order within the block)
        # and reassemble back into a single block later (sort -V -k 2).
        time eval '(set -eu; unset TIMEFORMAT shute_shopt_backup; eval "$1" 2> >(sed -u -e "s/^/STDERR /") > >(sed -u -e "s/^/STDOUT /"))' \
            | grep -n '.' \
            | sed -u 's/^\([0-9]\+\):\(STDOUT\|STDERR\) /\2 \1 /'

        declare rc="$?"

        # Restore shell options
        declare cmd
        for cmd in "${shute_shopt_backup[@]}"; do
            eval "$cmd"
        done

    } 2> >(sed -u -e "s/^/TIME /")

    printf 'EXIT %s\n' "$rc"
}


## @fn shute_run_test_class ()
## @brief Run a pattern-based list of functions as test cases
## @details Pass every function name starting with a specified prefix to
## the shute_run_test_case command. A line containing "CLASS $class_name"
## will be added to the end of every test case output block
## @param class_name class name
## @param fn_prefix function prefix. All functions starting with
## this prefix (in the current scope) will be executed.
##
## Example (assumes there are "test_1" and "test_2" functions.
## Outut reduced for clarity)
##
## @code{.sh}
## $ shute_run_test_class testclass test_
## CMD test_1
## ...
## CLASS testclass
## CMD test_2
## ...
## CLASS testclass
## @endcode
shute_run_test_class () {
    declare fn

    while read -r fn; do
        shute_run_test_case "$fn"
        printf 'CLASS %s\n' "$1"
    done < <(compgen -A function "$2")
}


## @fn shute_run_test_suite ()
## @brief Run a command which runs multiple tests cases as a test suite
## @details Suite data starting with a SUITE-* set of
## keywords will be added at the top
## @param cmd command. Will be passed to 'eval'
##
## Example (assumes there is a "suite_1" command which executes
## "shute_run_test_case test_1" and "shute_run_test_case test_2" commands.
## Outut reduced for clarity)
##
## @code{.sh}
## $ shute_run_test_suite suite_1
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
shute_run_test_suite () {
    declare -i shute_suite_tests=0
    declare -i shute_suite_errors=0
    declare -i shute_suite_failures=0
    declare -i shute_suite_skipped=0
    declare -i shute_suite_line=1
    declare shute_suite_time='0.0'

    declare key
    declare value

    {
        printf '0 SUITE-NAME %s\n' "$1"

        while read -r key value; do
            case "$key" in
                CMD)
                    shute_suite_tests+=1
                    ;;
                EXIT)
                    [[ "$value" = '0' ]] || shute_suite_errors+=1
                    ;;
                TIME)
                    shute_suite_time=$(bc <<< "$shute_suite_time + $value" | sed 's/^\./0./')
                    ;;
            esac

            printf '%d %s %s\n' "$shute_suite_line" "$key" "$value"

            shute_suite_line+=1

        done < <(unset shute_suite_tests shute_suite_errors shute_suite_failures shute_suite_skipped shute_suite_line shute_suite_time; eval "$1")

        printf '0 SUITE-TESTS %s\n' "$shute_suite_tests"
        printf '0 SUITE-ERRORS %s\n' "$shute_suite_errors"
        printf '0 SUITE-FAILURES %s\n' "$shute_suite_failures"
        printf '0 SUITE-SKIPPED %s\n' "$shute_suite_skipped"
        printf '0 SUITE-TIME %s\n' "$shute_suite_time"

    } | sort -n | sed -u 's/^[0-9]\+ //'
}


## @fn shute_run_test_suites ()
## @brief Run a pattern-based list of functions as test suites
## @details Pass every function name starting with a specified prefix to
## the shute_run_test_suite command. Aggregated suite data starting
## with a SUITES-* set of keywords will be added at the top
## @param name a name of the collection
## @param fn_prefix function prefix. All functions starting with
## this prefix (in the current scope) will be executed.
##
## Example (assumes there is a "suite_1" command which executes
## "shute_run_test_case test_1" and "shute_run_test_case test_2" commands,
## and a "suite_2" command which executes "shute_run_test_case test_3"
## command. Outut reduced for clarity)
##
## @code{.sh}
## $ shute_run_test_suites 'A collection' suite_
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
shute_run_test_suites () {
    declare -i shute_suites_tests=0
    declare -i shute_suites_errors=0
    declare -i shute_suites_failures=0
    declare -i shute_suites_skipped=0
    declare -i shute_suites_line=1
    declare shute_suites_time='0.0'

    declare fn

    declare key
    declare value

    {
        printf '0 SUITES-NAME %s\n' "$1"

        while read -r fn; do

            while read -r key value; do
                case "$key" in
                    SUITE-ERRORS)
                        shute_suites_errors+="$value"
                        ;;
                    SUITE-FAILURES)
                        shute_suites_failures+="$value"
                        ;;
                    SUITE-SKIPPED)
                        shute_suites_skipped+="$value"
                        ;;
                    SUITE-TESTS)
                        shute_suites_tests+="$value"
                        ;;
                    SUITE-TIME)
                        shute_suites_time=$(bc <<< "$shute_suites_time + $value" | sed 's/^\./0./')
                        ;;
                esac

                printf '%d %s %s\n' "$shute_suites_line" "$key" "$value"

                shute_suites_line+=1

            done < <(unset shute_suites_tests shute_suites_errors shute_suites_failures shute_suites_skipped shute_suites_line shute_suites_time; shute_run_test_suite "$fn")

        done < <(compgen -A function "$2")

        printf '0 SUITES-TESTS %s\n' "$shute_suites_tests"
        printf '0 SUITES-ERRORS %s\n' "$shute_suites_errors"
        printf '0 SUITES-FAILURES %s\n' "$shute_suites_failures"
        printf '0 SUITES-SKIPPED %s\n' "$shute_suites_skipped"
        printf '0 SUITES-TIME %s\n' "$shute_suites_time"

    } | sort -n | sed -u 's/^[0-9]\+ //'
}
