# Consolidation validation

No production source changes occur in these scripts. Use Python 3 and Godot 4.6.x, with all processes bounded to 30 seconds and Dummy audio.

- `../verify_pending.py --archives DIR --target SOURCE`: read-only archive/76-file chain validation and exact resume-state detection. Only the existing batch 4–7 ZIPs are required. This is the intended future bridge preflight.
- `run_crossbatch.py --archives DIR --source FINAL_SOURCE`: reruns archived batches 3–6 against the exact final batch-7 76-file source. Requires existing batch 3–6 ZIPs. Test-only prefix/dependency adjustments are explicit; original test assertions remain unchanged.
- `run_unchanged_guards.py --archives DIR --source FINAL_SOURCE`: reruns batch-1 conductor/save guards and batch-2 export guards, with the existing archives. Verifies the tested production files/functions are byte-identical to their intended candidates.
- `run_cross_flow.py --source FINAL_SOURCE --batch7-package EXTRACTED_PACKAGE`: composes actual current model operations and save/reopen; uses the already-extracted batch-7 validation dependencies and exact recording-signature excerpts.
- `test_ledger.py --archives DIR --workspace CLOUD_WORKSPACE`: source-workspace test of valid resume states and refusal cases. It only creates temporary copies for negative cases and removes those copies afterward. This test needs the preserved historical cloud candidates and is not a native apply tool.

The ledger package intentionally does not duplicate source trees or the original ZIP payloads. Materialize those referenced Library packages separately when rerunning. `FINAL_SOURCE` must be a separately verified final 76-file candidate tree; do not point destructive application tools at the native source merely to obtain a test tree. All runner outputs go to this ledger's validation directory, never to `FINAL_SOURCE`.

Final results: 1,108 unchanged conductor/save/export checks; 1,042 historical edit/gesture/relink/recording checks; 27 composed-flow checks; 13 read-only ledger checks. All pass with zero engine errors/warnings. Batch-7's original 613-check receipt remains valid because production source is unchanged. These are assertion counts, not counts of complete native workflows.


## Ledger version1: batch8 extension
Use exact final batch8 candidate for --source. Fresh original-to-batch8 reconstruction is in reconstruct_chain.py; read-only resume tests now cover batch3–8. run_final_review.py reruns archived dialogue tests against batch8. cross_flow_tests.gd adds recovery/independent-owner/relink/cleanup/Undo/signature checks. test_inline_payloads.py verifies the optional bounded inline transfer diffs against all76 pre/post hashes. git_apply_results.json records unchanged originaldiff acceptance and exact hashes. No original production package is edited.
