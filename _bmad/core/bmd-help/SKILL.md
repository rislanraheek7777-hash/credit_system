# bmd-help

**BMad Help** - Analyzes current state and user query to answer BMad questions or recommend the next skill(s) to use.

## Purpose

The `bmd-help` skill is invoked when the user asks for help, asks "bmad help", wants to know "what to do next", or wants to know "what to start with in BMad". It analyzes the current project state, the user's query, and the BMad workflow phase to provide guidance on the next appropriate skill or action.

## Triggers

Invoke this skill when the user asks:

- "bmad help"
- "what should I do next?"
- "what skill should I use?"
- "help me get started with BMad"
- "what's the next step in my project?"

## Behavior

1. **Analyze the current state**: Review the project's BMad status, including:
   - Current phase (planning, building, etc.)
   - Recently used or pending skills
   - Project structure and artifacts
   - Any existing documentation or configuration

2. **Analyze the user query**: Understand the intent and context of the user's request.

3. **Recommend next steps**: Based on the analysis, recommend the most appropriate BMad skill(s) to use next, along with a brief explanation of why that skill is appropriate.

4. **Provide guidance**: Offer practical guidance on how to use the recommended skill, including any required inputs or context.

## Output

The skill should produce a helpful response that includes:

- Identification of the current BMad phase or state
- Recommendation of the next skill(s) to use
- Brief rationale for the recommendation
- Any relevant context or prerequisites for the recommended skill

## Example

```
User: "bmad help, I'm working on a credit system and need to define the architecture"
Skill Response: Based on your credit_system project, you're likely in the planning phase. I recommend using the `bmad-architecture` skill to define your architecture decisions before proceeding with epics and stories. This skill will help you record the architecture decisions that keep features, epics, and stories consistent.
```

## Integration

This skill works in concert with other BMad skills. It does not perform the actual work of other skills but instead helps users navigate the BMad methodology and choose the right tools for their current needs.