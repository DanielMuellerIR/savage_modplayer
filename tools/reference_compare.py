#!/usr/bin/env python3
"""Reproduzierbarer Audiovergleich mit openmpt123, ohne Python-Abhängigkeiten."""

from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import os
import statistics
import subprocess
import sys
import tempfile
import wave
from pathlib import Path
from typing import Sequence


SAMPLE_RATE = 44_100
ANALYSIS_RATE = 11_025
DOWNSAMPLE = SAMPLE_RATE // ANALYSIS_RATE
RMS_WINDOW = 1_024
RMS_HOP = 256
MAX_LAG_SECONDS = 2
STFT_WINDOW = 2_048
OPENMPT_VERSION_MARKERS = (
    "openmpt123 v0.8.7",
    "libopenmpt 0.8.7+r25325.pkg",
)
SUPPORTED_EXTENSIONS = {".mod", ".s3m", ".xm"}
SCHEMA = "savage-reference-report/v1"


class ComparisonError(RuntimeError):
    """Kontrollierter Fehler fuer Eingaben, Werkzeuge oder WAV-Formate."""


def _round(value: float | None, digits: int = 9) -> float | None:
    if value is None or not math.isfinite(value):
        return None
    return round(value, digits)


def validate_modules(paths: Sequence[Path]) -> list[Path]:
    """Prueft alle Eingaben, bevor irgendein Unterprozess gestartet wird."""
    if not paths:
        raise ComparisonError("Mindestens ein Modul ist erforderlich")
    checked: list[Path] = []
    for path in paths:
        resolved = path.expanduser().resolve()
        if resolved.suffix.lower() not in SUPPORTED_EXTENSIONS:
            raise ComparisonError(
                f"Nicht unterstuetztes Vergleichsformat: {path.suffix or '(ohne Endung)'}"
            )
        if not resolved.is_file():
            raise ComparisonError(f"Modul nicht gefunden: {path}")
        checked.append(resolved)
    return checked


def openmpt_version(executable: str) -> str:
    result = subprocess.run(
        [executable, "--long-version"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return result.stdout.strip()


def require_openmpt_version(version: str, allow_mismatch: bool = False) -> None:
    missing = [marker for marker in OPENMPT_VERSION_MARKERS if marker not in version]
    if missing and not allow_mismatch:
        raise ComparisonError(
            "Nicht kanonische openmpt123-Version; erwartet werden "
            + " und ".join(OPENMPT_VERSION_MARKERS)
            + ". Mit --allow-version-mismatch nur bewusst abweichend fortfahren."
        )


def _read_pcm(path: Path) -> tuple[array.array, int]:
    try:
        with wave.open(os.fspath(path), "rb") as wav:
            if wav.getnchannels() != 2:
                raise ComparisonError(f"WAV muss Stereo sein: {path}")
            if wav.getsampwidth() != 2:
                raise ComparisonError(f"WAV muss 16-Bit-PCM sein: {path}")
            if wav.getframerate() != SAMPLE_RATE:
                raise ComparisonError(f"WAV muss {SAMPLE_RATE} Hz haben: {path}")
            if wav.getcomptype() != "NONE":
                raise ComparisonError(f"WAV muss unkomprimiertes PCM sein: {path}")
            frames = wav.getnframes()
            raw = wav.readframes(frames)
    except (wave.Error, EOFError) as error:
        raise ComparisonError(f"Ungueltige WAV-Datei {path}: {error}") from error
    samples = array.array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    if len(samples) != frames * 2:
        raise ComparisonError(f"Abgeschnittener PCM-Payload: {path}")
    return samples, frames


def _signal(path: Path) -> dict[str, object]:
    pcm, frames = _read_pcm(path)
    if frames == 0:
        return {"frames": 0, "rms": 0.0, "dbfs": None, "samples": array.array("d")}

    mono_sum = 0.0
    mono_square_sum = 0.0
    for index in range(0, len(pcm), 2):
        value = (float(pcm[index]) + float(pcm[index + 1])) / (2.0 * 32768.0)
        mono_sum += value
        mono_square_sum += value * value
    dc = mono_sum / frames
    variance = max(0.0, mono_square_sum / frames - dc * dc)
    rms = math.sqrt(variance)

    # Fuer Huelle und STFT genuegt jedes vierte Frame. Die feste Auswahl ist
    # deterministisch und vermeidet songlange Float-Puffer bei 44,1 kHz.
    downsampled = array.array("d")
    append = downsampled.append
    for frame in range(0, frames, DOWNSAMPLE):
        index = frame * 2
        value = (float(pcm[index]) + float(pcm[index + 1])) / (2.0 * 32768.0)
        append(value - dc)
    del pcm
    return {
        "frames": frames,
        "rms": rms,
        "dbfs": 20.0 * math.log10(rms) if rms > 0.0 else None,
        "samples": downsampled,
    }


def rms_envelope(samples: Sequence[float]) -> list[float]:
    if len(samples) < RMS_WINDOW:
        if not samples:
            return []
        return [math.sqrt(sum(value * value for value in samples) / len(samples))]
    # Kein zweiter songlanger Python-Float-Puffer: Bei 600 Sekunden waere die
    # Hilfsliste deutlich groesser als der bereits heruntergesampelte Ton.
    rolling = sum(samples[index] * samples[index] for index in range(RMS_WINDOW))
    envelope: list[float] = []
    start = 0
    while start + RMS_WINDOW <= len(samples):
        envelope.append(math.sqrt(max(0.0, rolling / RMS_WINDOW)))
        next_start = start + RMS_HOP
        if next_start + RMS_WINDOW > len(samples):
            break
        rolling -= sum(samples[index] * samples[index] for index in range(start, next_start))
        rolling += sum(
            samples[index] * samples[index]
            for index in range(start + RMS_WINDOW, next_start + RMS_WINDOW)
        )
        start = next_start
    return envelope


def _pearson(left: Sequence[float], right: Sequence[float]) -> float | None:
    count = min(len(left), len(right))
    if count < 2:
        return None
    mean_left = sum(left[:count]) / count
    mean_right = sum(right[:count]) / count
    numerator = 0.0
    square_left = 0.0
    square_right = 0.0
    for index in range(count):
        a = left[index] - mean_left
        b = right[index] - mean_right
        numerator += a * b
        square_left += a * a
        square_right += b * b
    denominator = math.sqrt(square_left * square_right)
    return numerator / denominator if denominator > 0.0 else None


def best_envelope_lag(
    savage: Sequence[float], reference: Sequence[float]
) -> tuple[int, float | None]:
    max_lag = round(MAX_LAG_SECONDS * ANALYSIS_RATE / RMS_HOP)
    best_lag = 0
    best_correlation: float | None = None
    for lag in range(-max_lag, max_lag + 1):
        if lag >= 0:
            left = savage[lag:]
            right = reference
        else:
            left = savage
            right = reference[-lag:]
        correlation = _pearson(left, right)
        if correlation is None:
            continue
        better = best_correlation is None or correlation > best_correlation + 1e-12
        tied_and_closer = (
            best_correlation is not None
            and abs(correlation - best_correlation) <= 1e-12
            and (abs(lag), lag) < (abs(best_lag), best_lag)
        )
        if better or tied_and_closer:
            best_lag = lag
            best_correlation = correlation
    return best_lag, best_correlation


def active_end(envelope: Sequence[float], sample_count: int) -> int | None:
    if not envelope:
        return None
    threshold = max(envelope) * 0.001  # -60 dB relativ zum Huelle-Peak.
    if threshold <= 0.0:
        return None
    for index in range(len(envelope) - 1, -1, -1):
        if envelope[index] >= threshold:
            return min(sample_count, index * RMS_HOP + RMS_WINDOW)
    return None


def detect_onsets(envelope: Sequence[float]) -> list[int]:
    if len(envelope) < 2:
        return []
    positive = [max(0.0, envelope[i] - envelope[i - 1]) for i in range(1, len(envelope))]
    median = statistics.median(positive)
    mad = statistics.median(abs(value - median) for value in positive)
    threshold = median + 3.0 * mad
    if max(positive) <= 0.0:
        return []
    minimum_gap = max(1, math.ceil(0.050 * ANALYSIS_RATE / RMS_HOP))
    result: list[int] = []
    for index, delta in enumerate(positive, start=1):
        if delta > threshold and (not result or index - result[-1] >= minimum_gap):
            result.append(index)
    return result


def onset_metrics(savage: Sequence[int], reference: Sequence[int], lag: int) -> dict[str, object]:
    # Ein Hopschritt darf die vertraglichen +/-50 ms nicht nach oben runden.
    tolerance = max(1, math.floor(0.050 * ANALYSIS_RATE / RMS_HOP))
    unused = set(range(len(reference)))
    errors: list[float] = []
    for onset in savage:
        aligned = onset - lag
        candidates = [index for index in unused if abs(reference[index] - aligned) <= tolerance]
        if not candidates:
            continue
        match = min(candidates, key=lambda index: (abs(reference[index] - aligned), index))
        unused.remove(match)
        errors.append(abs(reference[match] - aligned) * RMS_HOP * 1000.0 / ANALYSIS_RATE)
    return {
        "savage_count": len(savage),
        "reference_count": len(reference),
        "matches": len(errors),
        "median_error_ms": _round(statistics.median(errors) if errors else None),
        "max_error_ms": _round(max(errors) if errors else None),
    }


def _fft(values: Sequence[complex]) -> list[complex]:
    count = len(values)
    if count == 0 or count & (count - 1):
        raise ValueError("FFT-Laenge muss eine Zweierpotenz sein")
    output = [complex(value) for value in values]
    bit = 0
    for index in range(1, count):
        mask = count >> 1
        while bit & mask:
            bit ^= mask
            mask >>= 1
        bit ^= mask
        if index < bit:
            output[index], output[bit] = output[bit], output[index]
    length = 2
    while length <= count:
        angle = -2.0 * math.pi / length
        step = complex(math.cos(angle), math.sin(angle))
        half = length // 2
        for base in range(0, count, length):
            factor = 1.0 + 0.0j
            for offset in range(half):
                even = output[base + offset]
                odd = factor * output[base + offset + half]
                output[base + offset] = even + odd
                output[base + offset + half] = even - odd
                factor *= step
        length *= 2
    return output


def _spectrum(samples: Sequence[float], start: int, scale: float) -> list[float] | None:
    if start < 0 or start + STFT_WINDOW > len(samples) or scale <= 0.0:
        return None
    windowed = [
        samples[start + index]
        / scale
        * (0.5 - 0.5 * math.cos(2.0 * math.pi * index / (STFT_WINDOW - 1)))
        for index in range(STFT_WINDOW)
    ]
    transformed = _fft(windowed)
    return [abs(value) for value in transformed[: STFT_WINDOW // 2 + 1]]


def _cosine(left: Sequence[float], right: Sequence[float]) -> float | None:
    numerator = sum(a * b for a, b in zip(left, right))
    denominator = math.sqrt(sum(a * a for a in left) * sum(b * b for b in right))
    return numerator / denominator if denominator > 0.0 else None


def _percentile(values: Sequence[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = percentile * (len(ordered) - 1)
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def stft_metrics(
    savage: Sequence[float],
    reference: Sequence[float],
    savage_rms: float,
    reference_rms: float,
    lag_envelope_hops: int,
) -> dict[str, object]:
    lag_samples = lag_envelope_hops * RMS_HOP
    values: list[float] = []
    second = 0
    first_reference_start = max(0, -lag_samples)
    while True:
        reference_start = first_reference_start + second * ANALYSIS_RATE
        savage_start = reference_start + lag_samples
        left = _spectrum(savage, savage_start, savage_rms)
        right = _spectrum(reference, reference_start, reference_rms)
        if left is None or right is None:
            break
        cosine = _cosine(left, right)
        if cosine is not None and math.isfinite(cosine):
            values.append(cosine)
        second += 1
    return {
        "window_count": len(values),
        "mean": _round(statistics.fmean(values) if values else None),
        "median": _round(statistics.median(values) if values else None),
        "p10": _round(_percentile(values, 0.10)),
    }


def analyze_wavs(savage_path: Path, reference_path: Path) -> dict[str, object]:
    savage = _signal(savage_path)
    reference = _signal(reference_path)
    savage_samples = savage["samples"]
    reference_samples = reference["samples"]
    assert isinstance(savage_samples, array.array)
    assert isinstance(reference_samples, array.array)
    savage_envelope = rms_envelope(savage_samples)
    reference_envelope = rms_envelope(reference_samples)
    lag_hops, correlation = best_envelope_lag(savage_envelope, reference_envelope)
    lag_frames = lag_hops * RMS_HOP * DOWNSAMPLE
    savage_frames = int(savage["frames"])
    reference_frames = int(reference["frames"])
    savage_rms = float(savage["rms"])
    reference_rms = float(reference["rms"])
    savage_end = active_end(savage_envelope, len(savage_samples))
    reference_end = active_end(reference_envelope, len(reference_samples))
    savage_onsets = detect_onsets(savage_envelope)
    reference_onsets = detect_onsets(reference_envelope)
    return {
        "levels": {
            "savage_rms_dbfs": _round(savage["dbfs"]),
            "reference_rms_dbfs": _round(reference["dbfs"]),
            "difference_db": _round(
                float(savage["dbfs"]) - float(reference["dbfs"])
                if savage["dbfs"] is not None and reference["dbfs"] is not None
                else None
            ),
        },
        "rms_envelope": {
            "correlation": _round(correlation),
            "best_lag_hops": lag_hops,
        },
        "timing": {
            "savage_frames": savage_frames,
            "reference_frames": reference_frames,
            "savage_duration_seconds": _round(savage_frames / SAMPLE_RATE),
            "reference_duration_seconds": _round(reference_frames / SAMPLE_RATE),
            "difference_frames": savage_frames - reference_frames,
            "difference_ms": _round((savage_frames - reference_frames) * 1000.0 / SAMPLE_RATE),
            "best_lag_frames": lag_frames,
            "best_lag_ms": _round(lag_frames * 1000.0 / SAMPLE_RATE),
            "savage_active_end_frames": savage_end * DOWNSAMPLE if savage_end is not None else None,
            "reference_active_end_frames": reference_end * DOWNSAMPLE if reference_end is not None else None,
        },
        "onsets": onset_metrics(savage_onsets, reference_onsets, lag_hops),
        "stft_cosine": stft_metrics(
            savage_samples,
            reference_samples,
            savage_rms,
            reference_rms,
            lag_hops,
        ),
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _command_report(module_name: str) -> dict[str, list[str]]:
    return {
        "savage": [
            ".build/release/savage-cli", "<module>", "--out", "<savage.wav>",
            "--rate", "44100", "--seconds", "600", "--quiet",
        ],
        "openmpt": [
            "openmpt123", "--batch", "--quiet", "--samplerate", "44100",
            "--channels", "2", "--no-float", "--gain", "0", "--stereo", "80",
            "--filter", "2", "--ramping", "0", "--tempo", "1", "--pitch", "1",
            "--dither", "0", "--subsong", "0", "--repeat", "0", "--end-time",
            "600", "--force", "--output", "<reference.wav>", "--", "<module>",
        ],
        "module_name": [module_name],
    }


def make_report(
    module: Path,
    savage_wav: Path,
    reference_wav: Path,
    version: str,
) -> dict[str, object]:
    return {
        "schema": SCHEMA,
        "module": {
            "name": module.name,
            "sha256": _sha256(module),
            "format": module.suffix.lower()[1:],
        },
        "render": {
            "sample_rate": SAMPLE_RATE,
            "channels": 2,
            "sample_bits": 16,
            "seconds_limit": 600,
            "interpolation": "linear",
            "normalization": False,
            "openmpt_version": version,
            "commands": _command_report(module.name),
        },
        "analysis": {
            "sample_rate": ANALYSIS_RATE,
            "similarity_normalization": "unit_rms",
            "rms_window": RMS_WINDOW,
            "rms_hop": RMS_HOP,
            "max_lag_seconds": MAX_LAG_SECONDS,
            "stft_window": STFT_WINDOW,
            "stft_windows_per_second": 1,
            "active_end_relative_db": -60,
            "onset_tolerance_ms": 50,
        },
        "metrics": analyze_wavs(savage_wav, reference_wav),
    }


def write_report(report: dict[str, object], path: Path) -> None:
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )


def run_comparison(
    modules: Sequence[Path],
    output_dir: Path,
    savage_cli: str = ".build/release/savage-cli",
    openmpt: str = "openmpt123",
    allow_version_mismatch: bool = False,
    keep_wavs: bool = False,
) -> list[Path]:
    checked = validate_modules(modules)
    version = openmpt_version(openmpt)
    require_openmpt_version(version, allow_version_mismatch)
    output_dir.mkdir(parents=True, exist_ok=True)
    reports: list[Path] = []
    for module in checked:
        digest = _sha256(module)[:12]
        basename = f"{module.stem}-{digest}"
        with tempfile.TemporaryDirectory(prefix="savage-reference-") as temporary:
            temp_dir = Path(temporary)
            savage_wav = temp_dir / "savage.wav"
            reference_wav = temp_dir / "reference.wav"
            subprocess.run(
                [savage_cli, os.fspath(module), "--out", os.fspath(savage_wav),
                 "--rate", "44100", "--seconds", "600", "--quiet"],
                check=True,
            )
            subprocess.run(
                [openmpt, "--batch", "--quiet", "--samplerate", "44100",
                 "--channels", "2", "--no-float", "--gain", "0", "--stereo", "80",
                 "--filter", "2", "--ramping", "0", "--tempo", "1", "--pitch", "1",
                 "--dither", "0", "--subsong", "0", "--repeat", "0", "--end-time",
                 "600", "--force", "--output", os.fspath(reference_wav), "--", os.fspath(module)],
                check=True,
            )
            report = make_report(module, savage_wav, reference_wav, version)
            report_path = output_dir / f"{basename}.json"
            write_report(report, report_path)
            reports.append(report_path)
            if keep_wavs:
                (output_dir / f"{basename}-savage.wav").write_bytes(savage_wav.read_bytes())
                (output_dir / f"{basename}-openmpt.wav").write_bytes(reference_wav.read_bytes())
    return reports


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("modules", nargs="+", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--savage-cli", default=".build/release/savage-cli")
    parser.add_argument("--openmpt", default="openmpt123")
    parser.add_argument("--allow-version-mismatch", action="store_true")
    parser.add_argument("--keep-wavs", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    options = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        reports = run_comparison(
            options.modules,
            options.output_dir,
            savage_cli=options.savage_cli,
            openmpt=options.openmpt,
            allow_version_mismatch=options.allow_version_mismatch,
            keep_wavs=options.keep_wavs,
        )
    except (ComparisonError, OSError, subprocess.CalledProcessError) as error:
        print(f"Fehler: {error}", file=sys.stderr)
        return 1
    for report in reports:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
