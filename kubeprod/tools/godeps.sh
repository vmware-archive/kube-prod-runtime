#!/bin/sh

set -e

: ${GO:=go}

$GO list -f '{{.ImportPath}} {{join .Deps " "}}' "$@" |
    xargs $GO list -f '{{$d := .Dir}}{{range .GoFiles}}{{$d}}/{{.}} {{end}}'
