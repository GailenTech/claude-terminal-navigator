# Proposed CLAUDE.md Updates for Better Branching

## Problem
Claude didn't create a feature branch when implementing the Swift menu bar app, despite the instruction "Branches for experiments: Always propose creating new branches when conducting experiments or tests."

## Root Cause
The branching instruction was:
1. Too brief and vague
2. Buried in the middle of other instructions  
3. Lacking concrete triggers and examples

## Proposed Addition to CLAUDE.md

Add this section after the "Commands" section:

```markdown
## 🌿 Git Branching Strategy

### CRITICAL: Always Create Feature Branches

**STOP before writing any code** - Ask yourself: "Does this need a branch?"

#### When to Create a Branch (REQUIRED):
- ✅ Adding new features (e.g., "add a widget", "implement X")
- ✅ Changing architecture or technology (e.g., "convert to Swift", "add database")
- ✅ Experiments or POCs (e.g., "try using X", "see if Y works")
- ✅ Any changes that might break existing functionality
- ✅ Multi-file changes that introduce new concepts

#### When NOT to Branch:
- ❌ Simple bug fixes in existing code
- ❌ Documentation updates only
- ❌ Configuration tweaks
- ❌ Single-file refactoring

#### Branch Workflow:
1. **IDENTIFY**: User says "implement/add/create/build" → NEEDS BRANCH
2. **PROPOSE**: "I'll create a feature branch for this: `feature/menu-bar-widget`"
3. **CREATE**: `git checkout -b feature/descriptive-name`
4. **WORK**: Make all changes on the feature branch
5. **PUSH**: Push branch and suggest PR when ready

#### Examples:
```bash
# User: "Add a menu bar widget"
git checkout -b feature/menu-bar-widget

# User: "Try implementing this in Swift"  
git checkout -b experiment/swift-implementation

# User: "Fix the typo in README"
# NO BRANCH NEEDED - direct commit to main
```

### Branch Naming Convention:
- `feature/` - New features
- `fix/` - Bug fixes (if complex)
- `experiment/` - Trying new approaches
- `refactor/` - Code restructuring
```

## Additional Workflow Update

In the "Development Workflow" section, update item #1:

```markdown
1. **Before starting**: 
   - Verify context and credentials
   - Read last DIARY.md entries for context
   - 🌿 **DECISION POINT: Does this task need a feature branch?**
     - If adding features/experiments → Create branch FIRST
     - If simple fixes → Can use main
```

This makes branching decisions an explicit part of the workflow, preventing oversights like the Swift app implementation.