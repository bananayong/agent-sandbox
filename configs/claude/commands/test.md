---
description: Discover and run the project's test suite
---
Detect the project's test framework by checking for:
- package.json (npm test, jest, vitest, mocha)
- pytest.ini / pyproject.toml / setup.cfg (pytest)
- Cargo.toml (cargo test)
- go.mod (go test ./...)
- Makefile (make test)

Run the appropriate test command and analyze results.
If tests fail, provide a summary of failures with suggested fixes.
