<!-- ProjectBridge delivery-mode policy v2 -->
> **SCOPE: ZIP PACKAGING FOR NORMAL READ-ONLY CHATGPT OR EXPLICIT ZIP REQUESTS.** > Normal ChatGPT reading GitHub without a writable checkout uses these instructions > for coding-change requests by default unless another delivery is requested. > Codex, IDE agents and other agents that can edit files directly should modify > the project normally and must **not** create a ProjectBridge patch ZIP unless > the user specifically asks for one. Merely reading this file does not select > ZIP-delivery mode for Codex. Older unconditional requirements below apply **only** > when ProjectBridge ZIP delivery is the chosen workflow.

# ProjectBridge: Instructions for ChatGPT

**Project:** kiwi-studios-2
**GitHub reference:** https://github.com/Hi62384/kiwi-studios-2
**Offline patch format:** `projectbridge.offline-patch.v1` (supported by ProjectBridge Offline Patcher v4)

## 1. Read the project first

1. Use the **current, user-authorized repository or supplied baseline**. Search directories, imports, call sites, configs, registrations and nearby tests; don't edit the first similarly named file without checking references.
2. Read and follow all applicable `AGENTS.md` files, including the root one. Respect the project's existing build, style, and asset rules.
3. Record the **exact Git commit/ref** used. For existing files, fetch the **complete original bytes**, not just snippets, HTML or Git's blob SHA-1. Compute SHA-256 from the original bytes. If the baseline is not accessible, ask for the *specific missing files* and do not invent hashes.
4. Work only on the requested feature. Include all needed new, edited and deleted files. Never include unchanged files, generated build caches, or the full assets folder unless an asset actually changed.
5. Treat the local project as possibly different from GitHub. Preserve local work: ProjectBridge verifies hashes and can three-way-merge source changes when exact original bytes are provided.

## 2. Mandatory ZIP layout

The ZIP must be named `ProjectBridge_patch.zip` and have **no enclosing directory**. Example:

```text
ProjectBridge_patch.zip
├── projectbridge_patch.json     (required UTF-8 JSON)
├── README_CHANGES.txt           (optional explanatory summary)
├── files/0001                  (complete resulting bytes of the first write)
├── files/0002                  (complete resulting bytes of the second write)
└── base/0001                   (recommended ORIGINAL bytes for a modified text file)
```

**Exact manifest structure:**

```json
{
  "format": "projectbridge.offline-patch.v1",
  "title": "Implement requested improvement",
  "description": "What was changed and why",
  "source": {
    "repository": "OWNER/REPOSITORY-IF-KNOWN",
    "commit": "EXACT-BASE-COMMIT-IF-KNOWN"
  },
  "changes": [
    {
      "action": "write",
      "path": "src/example/Existing.java",
      "before_sha256": "64-lowercase-hex-of-ORIGINAL-file-bytes",
      "after_sha256": "64-lowercase-hex-of-NEW-file-bytes",
      "payload": "files/0001",
      "base_payload": "base/0001",
      "summary": "Modify existing source file"
    },
    {
      "action": "write",
      "path": "src/example/New.java",
      "before_sha256": null,
      "after_sha256": "64-lowercase-hex-of-NEW-file-bytes",
      "payload": "files/0002",
      "summary": "Create a file"
    },
    {
      "action": "delete",
      "path": "src/example/Obsolete.java",
      "before_sha256": "64-lowercase-hex-of-ORIGINAL-file-bytes",
      "summary": "Delete obsolete file"
    }
  ]
}
```

The above SHA-256 strings are **illustrative placeholders**. In a real delivered ZIP, all present hashes must be **actual lowercase 64-character hexadecimal digests** computed from **exact file bytes**. Do not paste the placeholder strings into a real manifest. Omit unknown optional source fields instead of inventing a commit. Git blob SHAs are not SHA-256.

## 3. ZIP validation rules

- `write` means the **entire final file**, not a unified diff. Each write uses a unique `files/NNNN` payload that hashes to `after_sha256`.
- To modify an existing file, include the original file's `before_sha256`. For a new file, set `before_sha256` to JSON `null`. To delete, include the original hash but no replacement payload.
- Whenever the original existing file is UTF-8 source/text and <= 2 MiB, also include its exact bytes as `base/NNNN`, with `base_payload` in the manifest. That base payload's SHA-256 must equal `before_sha256` so ProjectBridge can safely merge unrelated local modifications.
- For renames/moves, use one deletion of the old path and one write of the new path.
- Paths are **relative to the selected project root**, `/`-separated, no absolute paths, drive letters, `..`, duplicate destinations, or symlink targets.
- Never attempt to modify `.git/`, `.gradle/`, `.venv/`, `.projectbridge/`, credentials, private keys or `.env` files. Follow the patcher's additional path restrictions.
- The ZIP may only contain the manifest, optional `README_CHANGES.txt`, and referenced `files/NNNN` / `base/NNNN` byte entries. No extra directories or unreferenced entries.
- Patcher limits: 1,500 operations, 512 MiB per payload and 2 GiB total uncompressed content. The user's unrelated 50+ GB project size is irrelevant because only changed files go in the patch.
- Do not place executable steps inside the ZIP. ProjectBridge treats ZIPs as **data**; the user previews edits before applying them, and the program creates backups.

## 4. How ChatGPT should build the patch

Use the ProjectBridge `make_patch.py` helper when available:

1. Prepare a **small** `baseline/` directory containing only affected files as they existed in the exact GitHub commit.
2. Prepare an `edited/` directory containing only created and modified files at the same relative paths.
3. Run, using actual values:

```sh
python make_patch.py --before baseline --edits edited \
  --out ProjectBridge_patch.zip --title "Feature or bug fix" \
  --repo OWNER/REPOSITORY --commit EXACT_COMMIT_SHA \
  --delete path/to/deleted/file.txt
```

Omit `--delete` if nothing is deleted. If the script is unavailable, use Python `zipfile`, `json` and `hashlib.sha256` to construct the exact same manifest. Verify all hashes, paths and ZIP members before delivering. If possible, run unit/build tests and validate the patch by applying it to a disposable checkout of the recorded baseline; never claim a test succeeded unless it was run.

## 5. Delivery (only when offline ZIP delivery was requested)

When the user explicitly requests a ProjectBridge patch, return **one downloadable `ProjectBridge_patch.zip`**, a concise summary of changed paths and behavior, and honest test/verification status. The user adds the ZIP to ProjectBridge Offline Patcher, reviews it and clicks **Apply verified changes**. They should not need to manually copy files or run a second conflict utility. ProjectBridge preserves backups and offers Undo.

> **Important for normal ChatGPT:** A repository file cannot force an ordinary ChatGPT conversation to fetch it automatically. In a new chat, the user should start with: **"Read my repository-root `AGENTS.md` and `PROJECTBRIDGE_PATCH_INSTRUCTIONS.md` in full before making changes. Return a ProjectBridge patch ZIP for: [request]."** If the files were generated locally, the user must commit and push them to GitHub before ChatGPT can read them from that repository.
