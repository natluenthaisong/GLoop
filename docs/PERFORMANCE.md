# GLoop 3.0.1 performance

Measured 25 October 2026 on an Apple M2 with 8 GB RAM, macOS 27.0.1.
Apple Swift 6.4 compiled in Swift 5 mode with `-O`, arm64/macOS 13 target.
The Rust trial used rustc 1.99.0, `opt-level=3`, C ABI, no third-party crates.

## What changed

- Decoding requests planar PCM and copies directly through CoreMedia. This
  removes a temporary interleaved array and the per-sample Swift channel loop.
- An unchanged A/B range reuses its prepared phrase. Repeat-count changes and
  replay no longer copy the whole phrase again.
- A seek copies a 32-frame fade-in, then schedules a retained read-only view of
  the prepared phrase. Very short tails use the original small-copy path.
- Initial phrase preparation runs on the decoder queue. First-time phrase copying
  still costs time and memory, but no longer runs on the UI thread during loading.

## Measurements

Two alternating-order comparison batches were run. Each used five fresh-process
runs per variant and input; compilation was completed before timing. Inputs were
one 22.4-second local video and a generated 600-second stereo AAC pulse track.
BPM analysis reads at most 90 seconds. No input media or personal paths are shipped.

The final batch's medians are below. Times are milliseconds. Buffer preparation
is a kernel measurement, not total UI/video seek latency.

| Operation | Before | Optimized native | Rust copy trial |
| --- | ---: | ---: | ---: |
| 22-second clip decode | 320.66 | 346.96 | 340.19 |
| 22-second seek-buffer work | 2.634 | 0.072 | 2.673 |
| 10-minute clip decode | 759.49 | 609.94 | 836.23 |
| 10-minute repeated loop configuration | 56.947 | 0.068 | 87.361 |
| 10-minute seek-buffer work | 92.517 | 0.067 | 149.103 |
| 10-minute preparation/seek peak RSS, MiB | 567.4 | 460.6 | 565.3 |

In the earlier batch, 10-minute seek-buffer work was 66.24 → 0.045 ms and peak
RSS was 569.0 → 460.5 MiB. These buffer/memory gains were consistent across batches.
Long-clip decoding improved by 9–20% in wall time across batches. Short-clip decode
wall times changed direction between batches, so no short-clip loading speedup is
claimed. BPM estimation itself was unchanged (about 54 ms for the 90-second pulse
in the final batch), and did not warrant a rewrite.

This was an interactive development machine, not an isolated performance lab.
Background load and memory pressure varied. Peak RSS is a process high-water
measurement spanning decode, whole-phrase preparation, five reconfigurations and
a halfway seek; it is not idle app memory. First phrase-copy timing was variable
(95.7 ms before, 126.5 ms after in the final long-clip batch); the improvement
there is moving that work off the UI thread, not eliminating the initial copy.

## Rust decision

The benchmark-only Rust prototype replaced the old interleaved channel-copy loop
with an optimized Rust loop, leaving the decoder and allocation strategy intact.
It produced identical PCM but did not consistently beat the native implementation;
it was slower on the long-clip decode in both paired batches. GLoop therefore keeps
Swift and Apple's system frameworks. Rust is not a build or runtime dependency.
This does not claim every possible Rust implementation would perform the same.

## Correctness and reproduction

Decoded stereo PCM hashes match all three variants for both inputs. Tests also
check partial-phrase sample equality, backing-buffer lifetime, cache invalidation,
finite/infinite repeats, fades, seek, and continuous rendered joins at 100%/75%.
The render test rejects silent 5 ms windows across the tested joins.

Use `scripts/profile.py` to rebuild and measure the current production kernels.
Use `scripts/profile/compare.py` to alternate compiled variants. Details and
measurement definitions are in `scripts/profile/README.md`. Raw local results and
baseline source snapshots are under ignored `dist/performance/`.
