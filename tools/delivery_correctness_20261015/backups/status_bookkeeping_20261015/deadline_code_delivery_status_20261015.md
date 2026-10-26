# Deadline code delivery status

Date: 2026-10-15 UTC

Archive: `C:\Users\User1\Downloads\kiwi_predator_deadline_code_20261015.zip` (367,932 bytes; SHA-256 `18c79ee22bc4fa01aebb48b1629d6d75e40a399c70b20ddc2657f4dfd39327cc`). Safely extracted to a unique staging folder; all 37 files listed in `CONTENTS_SHA256.json` verified. Applied only Kiwi batch 10 and Predator Isle batch 03.

## Kiwi batch 10

All four candidates matched the exact batch 9 baseline, all 72 listed dependencies matched, and the batch 10 postcondition map matched after readback.

- `Workspaces/AudioWorkspace/audio_analysis.gd` — `f66a57da209d19657296031054191836c15b2bb3232200dc0e2d672a0de4c0c0`
- `Workspaces/AudioWorkspace/audio_document.gd` — `13834a6e44e4dff88550a7623a7da5a96fe5b2917be831078615f8e0b413646a`
- `Workspaces/AudioWorkspace/audio_edit_session.gd` — `c898dd2fe21ed562eb587d696b3549cd8ed4e2d91eb6b943381238c5c6272b2a`
- `Workspaces/AudioWorkspace/audio_workspace.gd` — `4b63280a33318822285dba1b3c496f29b91b5095643d8f0e015458c1af9aacce`

Byte-preserving backups: `tools/delivery_correctness_20261015/backups/kiwi_batch10_portable_copy_20261015_54ccf96820d1415a82d37372ee9f2287/`.

## Predator Isle batch 03

Both required prior delivery manifests, all five exact target baselines, four staged candidates, and 10 unchanged dependencies matched. The four shared geology files were applied as one group; drainage was applied independently. All five final hashes match their candidates.

- `scripts/desert_settings.gd` — `d8a1342721551527eec7ec7333f9c322f30f51a5c3794f61a420ce055cf50df1`
- `scripts/desert_sampler.gd` — `ccf80fce4377387fc83cc637bbcf9b525fa35c13b8691eb097b84824d2e0c41e`
- `scripts/chunk_terrain.gd` — `0ba196911db397d505b8e4119e45629bf4b124b26203e714e93d9c95ea67adfd`
- `shaders/desert_material.gdshaderinc` — `be720b40a9bfa282ccab818190cbba1de1bdb5d40840fa75e7c506f1a648a990`
- `scripts/desert_drainage.gd` — `ccc183aca094d9c1422d05e3b27c56a1c00708a018295905bbb3c0f08f0f2c10`

Byte-preserving backups: `tools/delivery_correctness_20261015/backups/predator_batch03_desert_20261015_7537f52946ac4faca56d7fcf6c6353ec/`.

## Verification limits

No tests, builds, imports, asset packing, benchmarks, synthesis, or game launches were run. These are source-only changes and remain untested in the engine. Predator delivery notes also leave authentic salt-crust PBR absent, coast and mixed-biome bedding approximate, and the historical CPU performance gate unmeasured.