#!/bin/sh
# Usage: fetch-commit REPOSITORY COMMIT DIRECTORY
# Fetches only COMMIT (with its submodules) into DIRECTORY.
set -eu
repository=$1
commit=$2
directory=$3
git init -q "$directory"
git -C "$directory" fetch -q --depth 1 "$repository" "$commit"
git -C "$directory" checkout -q FETCH_HEAD
git -C "$directory" submodule update -q --init --recursive --depth 1
