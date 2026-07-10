#!/usr/bin/env bash

SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
TEST_FIXTURES="$(cd "$(dirname "$BATS_TEST_FILENAME")/__fixtures__" && pwd)"

export SCRIPTS_DIR TEST_FIXTURES
