# Command Checklist Template

Track repeatable validation steps for a task.

## Preflight
- [ ] `git status --short`
- [ ] `rg -n "<target-pattern>" <paths>`

## Build / Lint / Test
- [ ] `<build command>`
- [ ] `<lint command>`
- [ ] `<test command>`

## Runtime Checks
- [ ] `<start command>`
- [ ] `<smoke check command>`
- [ ] `<path/assertion command>`

## Final Verification
- [ ] `git diff -- <owned paths>`
- [ ] `<quality gate command>`
