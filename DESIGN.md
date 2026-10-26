# GLoop interface

Native AppKit controls, system fonts, neutral gray surfaces. A 236 pt library sidebar, video and transport in the center, 320 pt settings column. Separate Speed, Loop, Tempo and Metronome with rules, not cards.

Use 12–14 pt control text, an 18 pt clip title and a 24 pt speed readout. Playback and BPM values use tabular digits. Use color for selection and focus. Keep keyboard shortcuts and accessibility labels.

No slogans, oversized in-window branding, decorative panels or promotional status messages. Status text reports loading, playback, completion and errors. Put optional explanations in tooltips. Show BPM confidence when available. Keep beat alignment behind a disclosure.

Dark and light themes remain available. Preserve all playback, loop, metronome and library behavior.

Keyboard first for everyday practice: ⌘F focuses the library search, Return opens the first match and returns focus to the player, Down moves into the list. Return or Home goes back to A. [ and ] step speed by 5% and Shift steps by 1%; the slider moves in 1% steps because auto speed works in 1% steps. C marks the last completed loop clean. Up/Down in the A/B fields nudge a marker without restarting from A. Full Screen stays on the standard ⌃⌘F. With Full Keyboard Access, a focused control keeps Space and the arrows. Space during audio loading queues playback rather than being ignored. Library rows name a missing file in the detail line; the status line keeps its full text as a tooltip when it is truncated.

## Components

Place the waveform directly below the video in a compact strip (88 pt high), using the existing neutral surface and bounded peaks from decoded audio. Draw unselected peaks in muted gray, the selected A/B range and labeled marker badges in the theme accent, and the playhead in the text color. Keep timestamps tabular. Support dragging a new range or either marker, clicking to seek within the loop, and Escape to cancel a drag. Provide native Zoom to loop and Fit clip buttons; zoom changes only the visible range. Show factual loading and unavailable messages. Retain the native playback slider and editable A/B time fields as keyboard-accessible alternatives, with accessibility labels and gesture help.

Keep practice actions in one compact row below playback controls: Played cleanly and Undo together, with Practice stats at the trailing edge. Use native buttons and disabled states; change Played cleanly to Marked clean after marking. Explain eligibility and undo behavior in tooltips.

Practice history opens in a separate, nonmodal, resizable native window that follows the player's theme. Keep totals above a plain table, with All clips / Current clip scope and native segmented navigation for Sessions, Speed history and Completed loops. Use an 18 pt tabular summary, 12 pt table text, alternating row backgrounds and scrollbars for overflow. Preserve legibility at the 760 pt minimum window width; show truncated cell contents in tooltips.

Use factual empty states that name the next action. Keep the local-storage and manual-assessment explanation visible below history: clean marks are the player's own assessment. Clearly distinguish the latest history entries from all-time totals; do not present clean marks as automatic performance scores.

Place Pitch between Speed and Loop in the scrollable inspector. Use native minus, plus and Reset buttons with a centered semitone readout. Show half-step examples for E/E♭, disable pitch controls while audio loads or buffered playback is unavailable, and explain the unavailable state. Pitch changes audio only and remains independent of speed.

Place Ask AI below transport, opening a separate nonmodal AI Trim window with the same neutral AppKit controls and theme. Order agent configuration, current clip and sharing context, then request, plain-language reply, timestamped suggestion and actions. Keep raw response JSON out of the reply; use tabular loop times and native Use loop and Undo loop change buttons. Audio sharing requires explicit opt-in with its scope visible. Keep Export current loop separate from applying markers. Stop and error messages must identify the affected operation and give an accurate next step. Verify legibility and action visibility in both themes at the actual 700 pt AI Trim window and 1180 pt player widths.
