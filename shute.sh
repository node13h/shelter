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
    local cmd="$1"
    local expected_file="${2:--}"

    diff -du <(eval "$cmd") "$expected_file" >&2
}


## @fn _shute_do ()
## @brief Run command in an isolated environment and return annotated output
## @details The command is executed with errexit and nounset enabled
## The output is machine-readable
## @param cmd command. Will be passed to 'eval'
##
## Example
##
## @code{.sh}
## $  _shute_do 'echo Hi; echo Bye >&2'
## EXIT 0
## STDERR Bye
## TIME 0.002
## STDOUT Hi
## @endcode
_shute_do () {
    # shellcheck disable=SC2034
    declare cmd="$1"
    declare -i rc

    TIMEFORMAT=%R

    {
        set +e

        # change to double quotes to allow functions with parameters
        time eval "(set -eu; $cmd)" 2> >(sed -e "s/^/STDERR /") > >(sed -e "s/^/STDOUT /")

        rc="$?"
        set -e

    } 2> >(sed -e "s/^/TIME /")

    printf 'EXIT %s\n' "$rc"
}

_shute_json_string () {
    declare str="$1"

    declare -A trans
    declare hex

    # shellcheck disable=SC1003
    trans=([5c]='\\'
           [22]='\"'
           [08]='\b'
           [0c]='\f'
           [0a]='\n'
           [0d]='\r'
           [09]='\t')

    for hex in "${!trans[@]}"; do
        # shellcheck disable=SC2059
        str="${str//$(printf "\\x${hex}")/${trans[$hex]}}"
    done

    printf '%s\n' "$str"
}

_shute_is_true () {
    [[ "$1" = TRUE ]]
}

shute_run_test_case () {
    declare class_name="$1"
    declare cmd="$2"
    declare partial="${3:-FALSE}"
    declare key value
    declare first_line=TRUE
    declare exit_code
    declare time

    if _shute_is_true "$partial"; then
        printf '{'
    fi

    printf '"%s": {' "$(_shute_json_string "$cmd")"
    printf '"output": ['

    while read -r key value; do
        case "$key" in
            EXIT)
                exit_code="$value"
                ;;
            TIME)
                time="$value"
                ;;
            STDOUT|STDERR)
                if _shute_is_true "$first_line"; then
                    first_line=FALSE
                else
                    printf ', '
                fi

                printf '{"%s": "%s"}' "$(_shute_json_string "$key")"  "$(_shute_json_string "$value")"
               ;;
        esac

    done < <(_shute_do "$cmd")
        printf '], '
        printf '"time": "%s", ' "$(_shute_json_string "$time")"
        printf '"class": "%s", ' "$class_name"
        printf '"exit": %d' "$exit_code"
        printf '}'

    if _shute_is_true "$partial"; then
        printf '}'
    fi

    printf '\n'
}
