#!/usr/bin/env bash

# MIT license
# Copyright 2012 Sergej Alikov <sergej.alikov@gmail.com>

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
## @brief Run command in an isolated environment and return an annotated output
## @details The command is executed with errexit and nounset enabled.
## STDOUT and STDERR are processed by separate threads, therefore might
## be slightly out of order in relation to each other. Ordering within a
## single stream (STDOUT or STDERR) is guaranteed to be correct
## The output is machine-readable
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

    TIMEFORMAT=%R

    printf 'CMD %s\n' "$1"

    declare var

    while read -r var; do
        printf 'ENV %s %q\n' "$var" "$(declare -p "$var")"
    done < <(compgen -A variable)

    unset var

    {
        set +e

        # sequence numbers added by the last component allow
        # user to perform sorting (sort -V) to split STDOUT and STDERR into
        # separate blocks (preserving the correct order within the block)
        # and reassemble back into a single block later (sort -V -k 2).
        time eval '(set -eu; eval "$1" 2> >(sed -u -e "s/^/STDERR /") > >(sed -u -e "s/^/STDOUT /"))' > >(grep -n '.' | sed -u 's/^\([0-9]\+\):\(STDOUT\|STDERR\) /\2 \1 /')

        declare rc="$?"

        set -e

    } 2> >(sed -u -e "s/^/TIME /")

    printf 'EXIT %s\n' "$rc"
}
