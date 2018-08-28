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
