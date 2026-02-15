---
description: Review code changes and provide feedback
---
Review the current changes in this repository:
1. Run `git diff` to see unstaged changes
2. Run `git diff --cached` to see staged changes
3. If on a branch, run `git log --oneline main..HEAD` to see all branch commits

Analyze for:
- Bugs or logic errors
- Security issues (hardcoded secrets, injection risks)
- Performance concerns
- Code style and readability
- Missing error handling
- Test coverage gaps

Provide specific, actionable feedback organized by severity (critical, warning, suggestion).
