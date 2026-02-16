# Agent Design Patterns and Best Practices

Detailed patterns for designing effective agents: architecture selection, prompt engineering, error handling, and anti-patterns to avoid.

## Table of Contents

1. [Architecture Patterns](#architecture-patterns)
2. [Prompt Engineering for Agents](#prompt-engineering-for-agents)
3. [Error Handling and Recovery](#error-handling-and-recovery)
4. [Task Decomposition](#task-decomposition)
5. [Anti-Patterns](#anti-patterns)
6. [Context Engineering](#context-engineering)

---

## Architecture Patterns

### Sequential Pipeline

Chain agents in a predefined linear order. Each agent's output feeds the next.

```
Planner → Implementer → Tester → Reviewer
```

- Best for: predictable workflows with clear stages
- Pros: linear, deterministic, easy to debug
- Cons: bottleneck at each stage, no parallelism

### Orchestrator-Workers

Central agent dynamically breaks tasks and delegates to specialized workers.

```
Orchestrator
  ├── Worker A (frontend)
  ├── Worker B (backend)
  └── Worker C (tests)
```

- Best for: complex tasks needing dynamic decomposition
- Pros: flexible, parallel execution
- Cons: orchestrator is a single point of failure

### Generator-Critic

One agent creates output, a separate agent evaluates it. Fresh context improves review quality since the reviewer isn't biased toward code it wrote.

```
Generator → Output → Critic → Feedback → Generator (iterate)
```

- Best for: code review, quality assurance, content refinement
- Pros: catches blind spots, reduces self-confirmation bias
- Cons: higher cost (two agents per cycle)

### Parallel Fan-Out

Distribute independent tasks across agents simultaneously.

```
Coordinator
  ├── Agent 1 (module A)
  ├── Agent 2 (module B)
  └── Agent 3 (module C)
Coordinator (merge results)
```

- Best for: independent, file-disjoint work units
- Cons: merge conflicts if file boundaries aren't clean

### Test-Driven Pipeline

A particularly effective pattern for code generation:

1. Tester subagent writes tests based on requirements
2. Run tests — confirm they fail
3. Implementer subagent makes tests pass (without changing tests)
4. Reviewer subagent checks linting, complexity, security

---

## Prompt Engineering for Agents

### The Right Altitude

System prompts must be between two failure modes:
- **Too rigid**: Hardcoded conditional logic creates brittle, maintenance-heavy prompts
- **Too vague**: High-level guidance without concrete signals fails to guide behavior

### Prompt Structure Template

```markdown
You are a [ROLE] specialized in [DOMAIN].

When invoked:
1. [First action — the most important step]
2. [Second action]
3. [Third action]
...

Constraints:
- [What NOT to do — explicit boundaries]
- [Safety guardrails]

Output format:
- [How to present results]
```

### Effective Prompt Techniques

**Use diverse canonical examples, not exhaustive edge-case lists:**

Bad:
```
Handle errors: null pointer, division by zero, stack overflow, out of memory, file not found, permission denied, network timeout, malformed input, circular reference, deadlock...
```

Good:
```
Handle errors gracefully. Examples:
- Null pointer → Return descriptive error with variable name and call site
- Network timeout → Retry with exponential backoff, max 3 attempts
- Malformed input → Validate at entry, report what's wrong and where
```

**Be directive, not descriptive:**

Bad: "It is generally considered best practice to validate user input before processing."

Good: "Validate all user input at system boundaries. Reject invalid input immediately with a descriptive error."

**Set explicit negative boundaries:**

```
Never:
- Modify files outside the target directory
- Commit directly to main/master
- Delete existing tests
- Suppress linter warnings without explanation
```

**Give permission to stop and ask:**

```
If requirements are ambiguous or the change could break existing behavior, stop and ask for clarification rather than guessing.
```

### Writing the Description Field

The `description` field is the primary triggering mechanism. Make it comprehensive:

Bad: "A code reviewer"

Good: "Reviews code changes for security vulnerabilities, performance issues, and adherence to project conventions. Use proactively after changes to authentication, database queries, or API endpoints. Also use when explicitly asked to review code."

---

## Error Handling and Recovery

### Give Agents Verification Methods

The single highest-leverage practice: provide agents a way to verify their own work.

| Method | Signal Strength | Example |
|--------|----------------|---------|
| Test suites | Strongest | "Run `pytest` after changes and ensure all tests pass" |
| Linter/type checker | Strong | "Run `eslint` and `tsc --noEmit` before reporting completion" |
| Screenshot comparison | Medium | "Capture screenshot and compare with expected layout" |
| Self-review subagent | Moderate | "Spawn a reviewer subagent to check your work" |

### Recovery Strategies

1. **Hooks as guardrails**: PreToolUse hooks validate operations before they execute
2. **Definition of Done**: Prevent incomplete handoffs — "Task is done when: tests pass, no lint errors, PR description written"
3. **Ask-first rules**: "If the proposed change affects >3 files, describe the plan before executing"
4. **Context reset**: After two failed corrections, clear context and start fresh with a better-structured prompt

---

## Task Decomposition

### Sizing for Subagents

- Each subagent should own a self-contained unit of work
- **File ownership is critical** — each agent should own distinct files to prevent overwrite conflicts
- Context loading is essential — detailed task descriptions dramatically improve output
- 5-6 tasks per team member maintains productivity

### Decomposition Strategy

1. **Identify natural boundaries**: modules, layers, file groups
2. **Check for dependencies**: tasks that share files or state cannot run in parallel
3. **Define clear interfaces**: what each agent produces and what the next one expects
4. **Add verification at boundaries**: test that each agent's output is valid before the next consumes it

### When NOT to Decompose

- Sequential tasks where every step depends on the previous
- Small changes that fit in one context window
- When coordination overhead exceeds parallelism benefit
- When multiple agents would edit the same files

---

## Anti-Patterns

### The Smart Agent Trap
Trying to make agents "figure out" what to do from vague instructions. Be explicit about the workflow.

### The Context Explosion
Passing entire conversation history to every subagent. Tokens are not free. Use minimal, focused context for each agent — let them gather what they need.

### The Kitchen Sink Agent
One agent that reviews code AND deploys AND writes docs AND manages tickets. Split into focused roles.

### The Kitchen Sink Session
Mixing unrelated tasks in one context window. Use `/clear` between unrelated tasks.

### The Correction Spiral
Correcting the same issue over and over with slightly different words. After two failures, the problem is architectural (wrong agent design, wrong tool set, or wrong decomposition) — not the prompt wording.

### The Premature Team
Using agent teams for a task a single agent could handle. Every teammate is a full session with its own context loading cost. Start simple.

### Over-Restricting Tools
Giving an agent so few tools it can't complete its task, forcing awkward workarounds. Test that the tool set is sufficient for all expected use cases.

---

## Context Engineering

### Just-in-Time Loading

Don't pre-load everything. Maintain lightweight references and let agents retrieve dynamically:

```markdown
When you need database schema information, read `docs/schema.md`.
When you need API documentation, read `docs/api-reference.md`.
Do NOT read these files unless the current task requires them.
```

### Compaction

When approaching context limits:
- Summarize conversation history, preserving architectural decisions
- Discard redundant tool outputs
- Keep unresolved issues and current task state

### Sub-agent Isolation

Main agent coordinates strategy. Sub-agents handle focused tasks with clean contexts. Each returns a condensed summary (aim for 1,000-2,000 tokens).

### Filesystem as Communication

Use the filesystem for persistent state between agents:
- Write plans, progress notes, and tracking files to disk
- Agents re-read them to verify work and maintain focus
- Git history provides a natural audit trail

### Persistent Memory

For agents that learn over time, configure memory scopes:
- **User scope**: Learnings across all projects
- **Project scope**: Project-specific, shareable via version control
- **Local scope**: Project-specific, not shared

Only store stable patterns confirmed across multiple interactions. Prune aggressively.
