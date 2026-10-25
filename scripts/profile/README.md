# Local performance checks

`profile.py` builds an optimized Swift executable from the production decoder,
loop engine and BPM detector. Each measurement runs in a fresh process; timing
excludes compilation. `prepare` measures decode, first whole-clip configuration,
five repeated configurations, and a halfway seek. `bpm` separates mono decoding
(up to 90 seconds) from estimation. `fingerprint` hashes the decoded planar PCM.

```sh
python3 scripts/profile.py --output dist/profile-current --runs 5 --media short /path/to/short.mp4 --media long /path/to/long.mp4
```

To measure an older source snapshot, pass `--source /path/to/source`. It must
contain `NativeVideo.swift`, `GaplessAudio.swift`, and `BPMDetector.swift`.
`compare.py` alternates already-built variants to reduce ordering bias:

```sh
python3 scripts/profile/compare.py --variant before dist/profile-before/profile --variant after dist/profile-current/profile --media long /path/to/long.mp4 --runs 5 --output dist/comparison.json
```

Use generic labels. JSON reports omit media paths; media, source snapshots and
binaries should stay under ignored `dist/`. Do not run builds or other performance
tests concurrently with a measurement. An interactive Mac still has background
load; compare medians, CPU time and repeated runs rather than a single sample.

`peak_rss_mib` is the process high-water resident set across decoding and the
entire configuration/seek sequence, not idle app memory. Reported configuration
and seek times measure audio-buffer work, not end-to-end video-seek latency.

`copy.rs` is a benchmark-only Rust alternative to the old per-channel packet-copy
loop. It is not linked into GLoop and Rust is not needed to build the app.
The trial was compiled with `rustc --crate-type staticlib -C opt-level=3
-C panic=abort`. Its caller passed each interleaved channel pointer, a validated
planar destination, frame count and channel stride through a C ABI; all other
baseline decoder code was unchanged. See `docs/PERFORMANCE.md` for results.
