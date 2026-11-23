# Terravise production regression checks

Run from the repository root. iOS checks require Xcode and a booted Simulator.
The current scripts use the installed iPad Simulator ID; adjust the destination
in your local test invocation if that device is unavailable.

## Current production checks

- `bash Tests/CPTUploadHandler/run.sh`: upload/navigation, Practical STOP presentation,
  no-candidate CONTINUE, storage, provenance, invalidation and history.
- `bash Tests/BearingIdentificationUncertaintyBinding/run.sh`: current identification
  uncertainty formatting, refreshed-state replacement and unavailable-result fallback.
- `bash Tests/BearingRelativeUncertaintyAvailability/run.sh`: frozen Bearing V3
  Python–Swift model fixtures and invalid-input rejection. The existing fixture lives
  in the sibling `cpt_super_learn` research archive; it is a test dependency, not an
  application runtime dependency.
- `bash Tests/PracticalCoverage80/run.sh`: current 80% policy against 4,489 previously
  captured prefix states. Requires the existing capture at
  `/tmp/terravise-practical-integration/fixtures.jsonl`, sibling research artifacts,
  and its Python environment. This does not generate new geology or train a model.
- `bash Tests/PartialDepthObservation/run.sh [/path/to/projects.json /tmp/partial-depth.json]`:
  native depth-evidence adapter and genuine-history regression fixtures, including
  partial/latest-partial CPTs, unsupported depths, rounded endpoints, save/reopen,
  invalidation and STOP dispatch. An optional existing 127-CPT snapshot verifies
  baseline capture without reconstructing a predecessor. Uses the same built app
  resources and native wrapper as the adaptive-spacing check below.
- `bash Tests/AdaptiveCandidateSpacing/run.sh /path/to/projects.json /tmp/adaptive.json`:
  native SchemaGAN/Uncertainty/DQN checks, normal and relaxed candidate pools,
  physical limits, current snapshot and save/reopen on existing project snapshots.
  It reuses `Tests/CPTProductionReplay/run_runtime_diagnosis.sh` as the native compiler
  and resource wrapper. This helper requires an explicit `TERRAVISE_DIAG_ENTRY`
  (the adaptive runner supplies it), rather than defaulting to an unstaged one-off audit.
  Build the app in `/tmp/terravise-strat-build` first, or supply
  the wrapper's `TERRAVISE_SOURCE_APP` override. Do not commit private project inputs.
- `bash Tests/RecommendedPointSketch/run_native.sh` and
  `bash Tests/BearingSubsurfaceSheetReuse/run_native.sh`: actual native sheet visuals
  using explicitly identified UI fixtures, not claims about real project sufficiency.

## Output and required fixtures

UI runners write generated logs/screenshots/results to a temporary directory outside
this repository. Set `TERRAVISE_TEST_ARTIFACTS_DIR=/absolute/output/directory` to retain
or collect them. The upload runner accepts `CPT_TEST_ARTIFACTS_DIR` for the same purpose.
Never include private project snapshots or generated native-app bundles in a commit.

Native UI checks compile the current production views directly. Obsolete before-only
audit source snapshots are not required by the production regression suite.

`Tests/PipelineParity/parity_manifest.json` and `attested_fixture.json` are also inputs
to the application's build attestation. Their location under Tests does not make them
optional generated output. Preserve the build phase and their resource fingerprints.

Some older tracked replay scripts require external fixtures and are separate from
the current production checks above. Current STOP intentionally permits manual CPT
uploads while suppressing automatic DQN recommendations.
