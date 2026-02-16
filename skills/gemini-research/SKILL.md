---
name: gemini-research
description: >
  Consult Gemini CLI (Google) for research, web search, and knowledge-intensive tasks. Use when
  you need up-to-date information, deep research on a topic, search-augmented answers, or a
  second opinion from a model with strong search capabilities. Triggers on requests like
  "ask gemini", "research this", "search with gemini", "look this up", or when a task requires
  current information, documentation lookup, or broad knowledge synthesis that would benefit
  from Gemini's grounded search.
---

# Gemini Research

Consult Gemini CLI for research, search-augmented answers, and knowledge-intensive tasks.
Gemini has strong integration with Google Search, making it ideal for questions that need
current information or broad knowledge synthesis.

## When to Use

- **Current information**: Questions about recent releases, CVEs, API changes, deprecations
- **Documentation lookup**: Finding correct usage patterns, library APIs, framework conventions
- **Research synthesis**: Gathering information from multiple sources on a topic
- **Fact verification**: Cross-checking technical claims, version compatibility, browser support
- **Comparative analysis**: Evaluating libraries, tools, or approaches with up-to-date data
- **Second opinion**: Getting Gemini's perspective on a difficult technical question

## How to Invoke Gemini

Use the Bash tool to run Gemini in non-interactive (headless) mode:

```bash
gemini -p "YOUR PROMPT HERE" -o text
```

### Key Flags

| Flag | Purpose |
|------|---------|
| `-p "prompt"` | Non-interactive headless mode (required) |
| `-o text` | Plain text output (recommended for parsing) |
| `-o json` | JSON output (for structured data extraction) |
| `-m MODEL` | Choose model (e.g., `-m gemini-2.5-pro`, `-m gemini-2.5-flash`) |
| `-y` / `--yolo` | Auto-accept all actions (the sandbox alias uses `--approval-mode yolo` for the same effect) |
| `-s` | Enable sandbox mode (restricts file system access) |

### Important Notes

- The sandbox has a shell alias that adds `--approval-mode yolo` automatically.
- Gemini can access the `/workspace` directory and read your codebase.
- Use `-o text` for most queries to get clean, parseable output.
- Use `-o json` when you need structured data (e.g., extracting specific fields).
- Gemini has built-in Google Search grounding — it can fetch current web information.

## Workflow

### Step 1: Formulate the Research Question

Write a focused, specific prompt. For research tasks, include:
- What you need to know
- Why you need it (context helps Gemini search better)
- What format you want the answer in
- Any specific constraints (version, platform, date range)

**Good prompt example:**
```
What are the recommended approaches for implementing real-time collaboration
in a React application as of 2025? Compare Yjs, Automerge, and ShareDB.
Include: maturity, bundle size, learning curve, and TypeScript support.
```

### Step 2: Run Gemini

```bash
gemini -p "YOUR RESEARCH QUESTION" -o text
```

For codebase-aware research:
```bash
gemini -p "Look at the dependencies in /workspace/package.json. Are there any known security vulnerabilities or major version updates available? Check for breaking changes." -o text
```

### Step 3: Evaluate and Integrate

After receiving Gemini's response:

1. **Verify**: Cross-check key claims against your own knowledge
2. **Filter**: Separate facts from opinions, current from outdated
3. **Contextualize**: Apply the findings to the user's specific situation
4. **Cite**: Note what came from Gemini's research vs your own knowledge

### Step 4: Follow-up Research (Optional)

Narrow down or expand based on initial findings. Each invocation is a new session (no memory
of prior queries), so include the relevant context:

```bash
gemini -p "What is the recommended setup for Yjs (a CRDT library for real-time collaboration) with Next.js 15? How does Yjs handle offline-first sync? Include code examples." -o text
```

## Research Patterns

### Pattern A: Technology Research
```bash
# Research a specific technology or approach
gemini -p "What is the current best practice for [TECHNOLOGY/PATTERN] in [YEAR]? Include recent changes, common pitfalls, and recommended libraries." -o text
```

### Pattern B: Bug/Error Research
```bash
# Research a specific error or issue
gemini -p "What causes '[ERROR MESSAGE]' in [FRAMEWORK/LIBRARY] version [VERSION]? What are the known fixes? Check GitHub issues and Stack Overflow." -o text
```

### Pattern C: API/Library Documentation
```bash
# Look up specific API usage
gemini -p "How do you use [API/FUNCTION] in [LIBRARY] v[VERSION]? Show correct usage with TypeScript types. Note any breaking changes from previous versions." -o text
```

### Pattern D: Comparative Analysis
```bash
# Compare options with current data
gemini -p "Compare [OPTION_A] vs [OPTION_B] vs [OPTION_C] for [USE_CASE]. Criteria: performance, bundle size, community activity, TypeScript support, last release date. Format as a comparison table." -o text
```

### Pattern E: Security/Vulnerability Check
```bash
# Check for known issues
gemini -p "Are there any known security vulnerabilities in [PACKAGE]@[VERSION]? Check CVE databases and recent advisories. What are the recommended mitigations?" -o text
```

### Pattern F: Migration/Upgrade Research
```bash
# Research migration paths
gemini -p "What are the breaking changes when upgrading from [LIB] v[OLD] to v[NEW]? List required code changes and common migration issues." -o text
```

## Combining Gemini Research with Claude Analysis

The most powerful pattern is using Gemini for information gathering and then applying
your own deeper reasoning:

```
1. [Identify what you don't know or need to verify]
2. [Run Gemini research query]
3. [Apply your own analysis to Gemini's findings]:
   - Verify technical accuracy
   - Apply to the specific codebase/context
   - Identify gaps in the research
   - Synthesize a recommendation
4. [Present to user with clear attribution]:
   "Based on research (via Gemini) and my analysis:
    - Gemini found that [CURRENT_INFO]
    - Applying this to your codebase, I recommend [RECOMMENDATION]
    - Reasoning: [YOUR_ANALYSIS]"
```

## Multi-Model Collaboration

For particularly hard problems, combine both Codex and Gemini (see the `codex-discuss` skill
for Codex invocation details):

```
1. [Gemini]: Research current best practices and gather facts
   gemini -p "What are the current best practices for [TOPIC]?" -o text
2. [Codex]: Analyze the specific implementation approach
   command codex exec -s read-only -C /workspace "Analyze [SPECIFIC_CODE] and suggest improvements"
3. [You]: Synthesize both into a final recommendation
```

This gives you:
- **Gemini**: Current information and broad search coverage
- **Codex**: Deep code reasoning from OpenAI's models
- **Claude**: Synthesis, judgment, and contextual application

## Output Handling

- Gemini's text output is generally clean and well-structured.
- For long research results, focus on extracting actionable information.
- When Gemini cites sources, note them for the user's reference.
- If Gemini's response seems outdated or uncertain, verify with a follow-up query
  or consult Codex as a cross-check.
- Always clearly indicate which information came from Gemini's research.
