# Tests

## bats (Bash Automated Testing System)

All `.sh` scripts are tested with bats.

### Running tests

```bash
cd E:/opensource/hanflow-evolve
bats tests/                          # all
bats tests/test-write-state.bats     # single file
```

### Conventions

- Test files: `tests/test-<script-name>.bats`
- Fixtures: `tests/__fixtures__/`
- Helper: `tests/test-helper.bash` (provides SCRIPTS_DIR / TEST_FIXTURES variables)
- Each test uses independent TMPDIR, does not pollute workspace
