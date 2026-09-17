#!/usr/bin/env python3
"""Render the voice cue clips with ElevenLabs.

Writes one mp3 per clip into Milepost/Resources/VoiceCues plus VoiceCues.json,
the manifest VoiceCueTests checks against VoiceCueScript.library. The clip list
here must match that Swift library; the test is what catches drift.

Idempotent: a clip that already exists is not rendered again, so re-running
after adding one phrase costs one phrase. A whole render is about 5,700
characters (~2,900 credits on Flash), well under one free-plan month.

    ./scripts/make_voice_cues.py            # render what is missing
    ./scripts/make_voice_cues.py --force    # re-render everything (costs a full run)
    ./scripts/make_voice_cues.py --dry-run  # list + character count, no calls

Key: keychain service `nemo-elevenlabs` (TTS-scoped; /v1/user returns 401,
that is expected).
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Milepost", "Resources", "VoiceCues")
MANIFEST = os.path.join(OUT, "VoiceCues.json")

# Sarah: clear, confident, reads over music without sounding like a dispatcher.
VOICE_ID = "EXAVITQu4vr4xnSDxMaL"
VOICE_NAME = "Sarah"
MODEL_ID = "eleven_flash_v2_5"          # 0.5 credits/char, lowest latency tier
OUTPUT_FORMAT = "mp3_22050_32"          # speech at 32 kbps: ~4 KB/s
# Hard ceiling on what one run of this script may send, in characters. A bug
# that looped would otherwise burn the month's credits in a minute.
MAX_CHARS_PER_RUN = 8000

MAX_WHOLE = {"mi": 30, "km": 50}
NOUN = {"mi": "mile", "km": "kilometer"}


def distance_phrase(units, unit):
    """Mirror of VoiceCuePhrase.distance."""
    whole = int(units)
    has_half = units - whole >= 0.25
    noun = NOUN[unit]
    if whole == 0 and has_half:
        return f"Half a {noun} complete."
    if whole == 1 and not has_half:
        return f"1 {noun} complete."
    if not has_half:
        return f"{whole} {noun}s complete."
    return f"{whole} and a half {noun}s complete."


def library():
    """Mirror of VoiceCueScript.library: clip name -> (text, previous, next)."""
    out = {}
    for unit in ("mi", "km"):
        out[f"dist_{unit}_0h"] = (distance_phrase(0.5, unit), "", "Time,")
        for n in range(1, MAX_WHOLE[unit] + 1):
            out[f"dist_{unit}_{n}"] = (distance_phrase(n, unit), "", "Time,")
            out[f"dist_{unit}_{n}h"] = (distance_phrase(n + 0.5, unit), "", "Time,")
    for n in range(60):
        out[f"num_{n}"] = (str(n), "Time,", "minutes 12 seconds.")
    out["phrase_time"] = ("Time,", "1 mile complete.", "9 minutes 12 seconds.")
    out["phrase_avg_pace"] = ("Average pace,", "Time, 9 minutes 12 seconds.", "9 minutes 12 seconds per mile.")
    out["phrase_avg_speed"] = ("Average speed,", "Time, 9 minutes 12 seconds.", "14 point 2 miles per hour.")
    for word in ("hour", "hours", "minute", "minutes", "second", "seconds"):
        out[f"word_{word}"] = (word, "Time, 9", "12 seconds.")
    out["word_point"] = ("point", "Average speed, 14", "2 miles per hour.")
    out["unit_per_mi"] = ("per mile.", "Average pace, 9 minutes 12 seconds", "")
    out["unit_per_km"] = ("per kilometer.", "Average pace, 5 minutes 40 seconds", "")
    out["unit_mph"] = ("miles per hour.", "Average speed, 14 point 2", "")
    out["unit_kmh"] = ("kilometers per hour.", "Average speed, 22 point 8", "")
    return out


def api_key():
    return subprocess.check_output(
        ["security", "find-generic-password", "-s", "nemo-elevenlabs", "-w"], text=True).strip()


def render(key, text, previous, nxt):
    body = {
        "text": text,
        "model_id": MODEL_ID,
        "previous_text": previous or None,
        "next_text": nxt or None,
        "voice_settings": {"stability": 0.6, "similarity_boost": 0.8, "style": 0.0, "speed": 1.0},
    }
    body = {k: v for k, v in body.items() if v is not None}
    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}?output_format={OUTPUT_FORMAT}",
        data=json.dumps(body).encode(),
        headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
        method="POST")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            if e.code in (429, 500, 502, 503) and attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            raise SystemExit(f"error: ElevenLabs HTTP {e.code} for {text!r}: {detail}")
    raise SystemExit("error: gave up")


def main():
    force = "--force" in sys.argv
    dry = "--dry-run" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    lib = library()
    todo = {name: spec for name, spec in lib.items()
            if force or not os.path.exists(os.path.join(OUT, f"cue_{name}.mp3"))}
    chars = sum(len(spec[0]) for spec in todo.values())
    print(f"{len(lib)} clips in library, {len(todo)} to render, {chars} characters "
          f"(~{chars // 2} credits on {MODEL_ID})")
    if chars > MAX_CHARS_PER_RUN:
        raise SystemExit(f"error: {chars} characters exceeds the per-run cap of {MAX_CHARS_PER_RUN}")
    if dry:
        return
    if todo:
        key = api_key()
        sent = 0
        for i, (name, (text, previous, nxt)) in enumerate(sorted(todo.items()), 1):
            sent += len(text)
            if sent > MAX_CHARS_PER_RUN:
                raise SystemExit("error: per-run character cap hit mid-run")
            audio = render(key, text, previous, nxt)
            if not audio or audio[:2] not in (b"\xff\xfb", b"\xff\xf3", b"ID") and audio[:3] != b"ID3":
                raise SystemExit(f"error: {name}: response is not mp3 ({len(audio)} bytes)")
            with open(os.path.join(OUT, f"cue_{name}.mp3"), "wb") as f:
                f.write(audio)
            print(f"  [{i}/{len(todo)}] cue_{name}.mp3  {len(audio):>6} B  {text!r}")
        print(f"sent {sent} characters (~{sent // 2} credits)")
    manifest = {
        "voiceID": VOICE_ID,
        "voiceName": VOICE_NAME,
        "modelID": MODEL_ID,
        "clips": {name: spec[0] for name, spec in lib.items()},
    }
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    total = sum(os.path.getsize(os.path.join(OUT, p)) for p in os.listdir(OUT))
    print(f"wrote {MANIFEST}; {total / 1e6:.2f} MB of clips")


if __name__ == "__main__":
    main()
