# Project instructions

<!-- ProjectBridge offline-patch instructions; do not duplicate -->
## ProjectBridge delivery modes — choose based on the request

- **Codex, IDE agents, local coding agents, and any agent working in a writable checkout:** **edit files directly** using the normal coding workflow, then test and report results. **Do NOT produce `ProjectBridge_patch.zip`** unless the user specifically requests it. The presence of these instructions does not mean ZIP delivery was requested.
- **Normal ChatGPT reading GitHub read-only, without a writable checkout:** for coding-change requests, **default to a ProjectBridge patch ZIP** unless the user requests another output. Read `PROJECTBRIDGE_PATCH_INSTRUCTIONS.md` **in full** before building a ZIP, then package only the relevant changes against the GitHub baseline.
- For all other tasks, use the tools and delivery format explicitly requested by the user. Never replace direct Codex edits, commits, or PRs with a ZIP without the user asking.
- Preserve project-specific build/optimization instructions elsewhere in `AGENTS.md`. Report tests honestly.
