# AI-assisted trimming

Open **Ask AI…** below GLoop’s playback controls, or **View → AI Trim…**.
GLoop is an [Agent Client Protocol](https://agentclientprotocol.com/) client. It
uses ACP v1 over stdio and works with a separately installed compatible agent.
No agent, model subscription, API key or AI service is bundled.

## Connect an agent

1. Install and sign in to your chosen ACP agent using its own instructions.
2. In AI Trim, choose its executable. Enter its ACP launch arguments as a JSON
   list, such as `["--acp"]` if that is what the agent’s documentation specifies.
   Some adapters need no arguments. A normal CLI without ACP support will not work.
3. Click **Connect**. GLoop shows the connected agent and whether it accepts audio.

The executable is launched directly, without shell interpretation. Paths and
arguments are saved in local preferences. Do not put API keys in arguments;
configure authentication through the agent. GLoop does not install agents or
perform their login flow. Connect only an agent you trust: it runs as your Mac
user and may have its own file tools, network access and provider charges.

## Ask for a trim

Set an approximate A/B range, then ask for a specific change—for example:

- “Keep the first four beats of this loop at 120 BPM.”
- “Remove the silence before the first note and after the final decay.”
- “Find a tighter repeat of the phrase in the attached audio.”

Every request includes its text, current loop times, original BPM when available,
clip duration and a bounded peak-amplitude summary. It does not include the video,
source path, library, practice history or other clip settings. A waveform summary
cannot reliably identify musical phrases. For requests requiring listening,
select **Share loop audio**, available only when the agent advertises audio support.
This sends the current A/B range, at original speed and pitch, as an in-memory WAV.
The range must be 0.16–60 seconds; GLoop never silently sends a larger range or
truncates one. Audio sharing is off initially and resets when switching clips.

The connected agent may send the request and optional audio to its model provider.
Its privacy, billing and retention rules apply. GLoop does not save conversations
or audio excerpts to disk. Each request starts a fresh agent session, so describe
the requested change fully rather than referring to an earlier answer.

## Use or export the result

The suggested A/B timestamps appear after the reply completes. GLoop rejects
malformed, ambiguous, too-short or out-of-bounds suggestions. **Use loop** applies
valid markers; nothing is applied automatically. Listen with GLoop’s normal
playback controls, refine the waveform markers if needed, or use **Undo loop
change**. Undo preserves newer manual marker edits instead of overwriting them.
Switching or removing a clip cancels an in-flight request and clears its suggestion.

**Export current loop…** writes a new MP4 at original speed and pitch. This uses
the current markers, whether chosen manually or by AI. It does not bake in speed,
pitch, metronome or repeats. Existing files cannot be overwritten, and the source
is retained. Open the exported file in GLoop to add it to the library.

**Stop** cancels an active request/export. Reconnect after stopping an agent.
Closing AI Trim disconnects the agent. File/terminal capabilities are not exposed
over ACP and agent permission requests are rejected; this is not an OS sandbox
for the executable itself.

## Validation and limits

ACP transport and lifecycle tests use a deterministic offline peer, including
fragmented messages, streamed UTF-8, optional audio, permission refusal, invalid
and oversized data, timeouts, cancellation and protocol mismatch. Export tests
check duration and preserve both the source and existing destinations. These tests
do not establish musical accuracy or compatibility with every agent/model.
A real authenticated provider has not been exercised for this build.

Protocol references: [initialization](https://agentclientprotocol.com/protocol/v1/initialization),
[stdio](https://agentclientprotocol.com/protocol/v1/transports),
[prompt turns](https://agentclientprotocol.com/protocol/v1/prompt-turn),
[audio content](https://agentclientprotocol.com/protocol/v1/content).
