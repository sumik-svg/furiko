# furiko

A 4-voice generative pendulum sequencer with dynamic harmony, AWAKE polymetric melody mode, and softcut reverse tape effects.

Originally designed for **SONICWARE LIVEN Ambient Ø**, but equipped with full **Standard MIDI (GM)** and **Custom** mapping profiles for any multitimbral synthesizer or DAW setup.

---

## Concept

*furiko* (振り子, Japanese for *pendulum*) visualizes and sonigenerates sound through four asynchronous physical pendulums displayed in a minimal 4-quadrant layout:

- **Ch1 & Ch2 (Soprano & Alto):** Evolving arpeggios that unfurl as the pendulum passes through the center of its swing, with dynamic spatial panning and timbre modulation.
- **Ch3 (Tenor / Melody):** Can swing as a generative backing voice or transform into an **AWAKE-style dual-step sequencer** for evolving melodic lines.
- **Ch4 (Bass):** Anchored harmonic foundations clamped to low octaves (root, harmonic interval, and octaves) to ensure stable resonance.

---

## Features

- **4 Asynchronous Pendulum Layers:** Independent speed ratios create phasing, polyrhythmic ambient drift without rhythmic fatigue.
- **Harmonic Cleansing Engine:** Dynamic scale shifting automatically switches between Major and Minor scales across the chord cycle (`I -> IV -> VIm -> V`), eliminating dissonance.
- **AWAKE Melody Engine (Ch3):** Seamless integration of the dual-loop addition sequencer logic from the legendary norns script *awake*.
- **Integrated Softcut Tape FX:**
  - **Voice 1:** Warm *halfsecond* tape delay with bandpass filtering.
  - **Voice 2 (Reverse Buffer):** Probabilistic 0.5x half-speed reverse playback automatically triggered during melody sections.
- **Flexible MIDI Architecture:**
  - **Ambient Ø Profile:** Pre-mapped to Track Levels (CC 52), Pan (CC 53), Harmonic (CC 30), and Attack (CC 40).
  - **Standard (GM) Profile:** Mapped to standard Volume (CC 7), Pan (CC 10), Filter Cutoff (CC 74), and Attack (CC 73).
  - **Custom Profile:** Freely assign MIDI channels (1–16) and CC numbers per function.

---

## Requirements

- **[monome norns](https://monome.org/norns/)** (or norns shield)
- External MIDI synthesizer (e.g., SONICWARE LIVEN Ambient Ø, multi-timbral synth, or DAW)
- Stereo audio input to norns (to take advantage of internal Softcut delay & reverse tape FX)

---

## Installation

In the maiden command line (the `>>` prompt at the bottom of the maiden web interface), enter [1]:

```text
;install https://github.com/sumik-svg/furiko
```

---

## Hardware Controls

### Normal Mode

| Control | Action |
| :--- | :--- |
| **K1 (hold)** | Shift button |
| **K1 + K2** | Toggle **SYNC Mode** (gradually aligns all pendulums to Ch2's speed and phase) |
| **K1 + K3** | Toggle **Ch3 AWAKE Melody Mode** (switches quadrant 3 to step sequencer) |
| **K2 (tap)** | Cycle active pendulum count (`0 -> 1 -> 2 -> 3 -> 4 -> 3 -> 2 -> 1 -> 0`) |
| **K3 (tap)** | Play / Pause (stops and sends `all-notes-off` on pause) |
| **E1** | Manual chord transpose step (`I`, `IV`, `VIm`, `V`) |
| **E2** | Base Speed (Hz) |
| **E3** | Harmonic interval degree (`1st` to `8th`) |

---

### AWAKE Melody Mode (Ch3 Active)

When AWAKE mode is engaged (`K1 + K3`), **E1** navigates through 4 sub-modes:

| Mode | E2 | E3 | K2 | K3 |
| :--- | :--- | :--- | :--- | :--- |
| **STEP** | Edit Position | Note Pitch (0–8) | Switch Track (1/2) | Randomize steps |
| **LOOP** | Track 1 Length | Track 2 Length | Reset phase | Randomize phase |
| **SOUND** | Edit Param 1 | Edit Param 2 | Prev param pair | Next param pair |
| **OPTION** | Base Speed | Root Scale Key | Default speed | Advance chord |

---

## MIDI Configuration & Profiles

Access `PARAMS > MIDI Profile & Mapping` to switch between operational profiles:

| Profile | Channel 1–4 | Level / Volume | Pan | Mod / Harmonic | Attack | Pitch Reset |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Ambient Ø** | Ch 1, 2, 3, 4 | CC 52 | CC 53 | CC 30 | CC 40 | CC 32 |
| **Standard (GM)** | Ch 1, 2, 3, 4 | CC 7 | CC 10 | CC 74 | CC 73 | Pitchbend |
| **Custom** | User (1–16) | User / Off | User / Off | User / Off | User / Off | User / Off |

> **Note:** Editing any individual CC or Channel setting while in *Ambient Ø* or *Standard* mode will automatically set the profile to **Custom**.

---

## Softcut Audio Path

To use the tape delay and reverse FX:
1. Connect the stereo audio output of your synthesizer to the **audio inputs** of norns.
2. Monitor norns through your mixer/headphones.
3. In `PARAMS > Tape Delay (halfsecond)`, adjust delay volume, feedback, and rate.
4. Set `Reverse FX Probability (%)` under `Auto Effects` to determine how often half-speed reverse swells are introduced.

---

## License

MIT License. Feel free to modify and expand.
