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


## @fn _shute_do ()
## @brief Run command in an isolated environment and return annotated output
## @details The command is executed with errexit and nounset enabled
## The output is machine-readable
## @param cmd command. Will be passed to 'eval'
##
## Example (number of variables reduced for clarity)
##
## @code{.sh}
## $  _shute_do 'echo Hi; echo Bye >&2'
## ENV SHLVL declare\ -x\ SHLVL=\"1\"
## ENV TERM declare\ --\ TERM=\"dumb\"
## ENV TIMEFORMAT declare\ --\ TIMEFORMAT=\"%R\"
## ENV UID declare\ -ir\ UID=\"1000\"
## ENV _ declare\ --\ _=\"var\"
## ENV cmd declare\ --\ cmd=\"echo\ Hi\;\ echo\ Bye\ \>\&2\"
## EXIT 0
## STDOUT Hi
## STDERR Bye
## TIME 0.003
## @endcode
_shute_do () {
    # shellcheck disable=SC2034
    declare cmd="$1"
    declare -i rc
    declare var

    TIMEFORMAT=%R

    # Output quoted variable declarations (to support values with newlines)
    while read -r var; do
        printf 'ENV %s %q\n' "$var" "$(declare -p "$var")"
    done < <(compgen -A variable)

    {
        set +e

        time eval "(set -eu; $cmd)" 2> >(sed -e "s/^/STDERR /") > >(sed -e "s/^/STDOUT /")

        rc="$?"
        set -e

    } 2> >(sed -e "s/^/TIME /")

    printf 'EXIT %s\n' "$rc"
}

_shute_json_string () {
    declare str="$1"

    # shellcheck disable=SC1003
    declare -a tr=(
        '\' '\\'
        '"' '\"'
        $'\b' '\b'
        $'\f' '\f'
        $'\n' '\n'
        $'\r' '\r'
        $'\t' '\t'
    )

    set "${tr[@]}"

    while [[ "${#}" -gt 1 ]]; do
        str="${str//"${1}"/"${2}"}"
        shift 2
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
    declare first_item
    declare exit_code
    declare time
    declare -A env=()

    if _shute_is_true "$partial"; then
        printf '{'
    fi

    printf '"%s": {' "$(_shute_json_string "$cmd")"
    printf '"output": ['

    first_item=TRUE

    while read -r key value; do
        case "$key" in
            EXIT)
                exit_code="$value"
                ;;
            TIME)
                time="$value"
                ;;
            ENV)
                env["${value%% *}"]="${value#* }"
                ;;
            STDOUT|STDERR)
                if _shute_is_true "$first_item"; then
                    first_item=FALSE
                else
                    printf ', '
                fi

                printf '{"%s": "%s"}' \
                       "$(_shute_json_string "$key")"  \
                       "$(_shute_json_string "$value")"
               ;;
        esac

    done < <(_shute_do "$cmd")

    printf '], '

    if [[ "${#env[@]}" -gt 0 ]]; then
        printf '"env": {'

        first_item=TRUE

        for key in "${!env[@]}"; do
            if _shute_is_true "$first_item"; then
                first_item=FALSE
            else
                printf ', '
            fi

            # Unquote the value (see _shell_do)
            value="$(eval "printf '%s\\n' ${env[$key]}")"
            printf '"%s": "%s"' \
                   "$(_shute_json_string "$key")" \
                   "$(_shute_json_string "$value")"

        done

        printf '}, '
    fi

    printf '"time": "%s", ' "$(_shute_json_string "$time")"
    printf '"class": "%s", ' "$class_name"
    printf '"exit": %d' "$exit_code"
    printf '}'

    if _shute_is_true "$partial"; then
        printf '}'
    fi

    printf '\n'
}
