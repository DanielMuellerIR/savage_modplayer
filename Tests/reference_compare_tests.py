#!/usr/bin/env python3
"""Synthetische Regressionstests fuer tools/reference_compare.py."""

from __future__ import annotations

import importlib.util
import json
import math
import struct
import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "reference_compare", ROOT / "tools" / "reference_compare.py"
)
assert SPEC and SPEC.loader
reference_compare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reference_compare)


def write_wav(
    path: Path,
    values: list[float],
    rate: int = 44_100,
    channels: int = 2,
    sample_width: int = 2,
) -> None:
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(sample_width)
        wav.setframerate(rate)
        frames = bytearray()
        for value in values:
            if sample_width == 2:
                sample = max(-32767, min(32767, round(value * 32767)))
                frames.extend(struct.pack("<" + "h" * channels, *([sample] * channels)))
            else:
                sample = max(0, min(255, round(value * 127 + 128)))
                frames.extend(bytes([sample] * channels))
        wav.writeframes(frames)


def test_signal(seconds: float = 3.0, gain: float = 0.5) -> list[float]:
    count = round(seconds * 44_100)
    result: list[float] = []
    for index in range(count):
        time = index / 44_100
        gate = 1.0 if (index // 11_025) % 2 == 0 else 0.2
        result.append(gain * gate * math.sin(2.0 * math.pi * 440.0 * time))
    return result


class ReferenceCompareTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def compare(self, left: list[float], right: list[float]) -> dict[str, object]:
        left_path = self.directory / "left.wav"
        right_path = self.directory / "right.wav"
        write_wav(left_path, left)
        write_wav(right_path, right)
        return reference_compare.analyze_wavs(left_path, right_path)

    def test_identical_signals_have_unit_metrics_and_zero_lag(self) -> None:
        signal = test_signal()
        metrics = self.compare(signal, signal)
        self.assertEqual(metrics["timing"]["best_lag_frames"], 0)
        self.assertGreater(metrics["rms_envelope"]["correlation"], 0.99999)
        self.assertGreater(metrics["stft_cosine"]["mean"], 0.99999)
        self.assertEqual(metrics["stft_cosine"]["window_count"], 3)
        self.assertGreater(metrics["onsets"]["matches"], 0)
        self.assertEqual(metrics["onsets"]["max_error_ms"], 0.0)

    def test_defined_delay_is_found_within_one_hop(self) -> None:
        signal = test_signal()
        delay = 8_192
        delayed = [0.0] * delay + signal
        metrics = self.compare(delayed, signal)
        measured = metrics["timing"]["best_lag_frames"]
        self.assertLessEqual(abs(measured - delay), reference_compare.RMS_HOP * 4)

    def test_negative_lag_keeps_stft_windows(self) -> None:
        signal = test_signal(seconds=4.0)
        delay = 8_192
        metrics = self.compare(signal, [0.0] * delay + signal)
        self.assertLess(metrics["timing"]["best_lag_frames"], 0)
        self.assertGreater(metrics["stft_cosine"]["window_count"], 0)
        self.assertIsNotNone(metrics["stft_cosine"]["mean"])

    def test_periodic_correlation_tie_prefers_zero_lag(self) -> None:
        periodic = [0.0, 1.0] * 100
        lag, correlation = reference_compare.best_envelope_lag(periodic, periodic)
        self.assertEqual(lag, 0)
        self.assertAlmostEqual(correlation, 1.0)

    def test_gain_change_preserves_similarity_and_reports_db(self) -> None:
        signal = test_signal(gain=0.6)
        quieter = [value * 0.5 for value in signal]
        metrics = self.compare(signal, quieter)
        self.assertAlmostEqual(metrics["levels"]["difference_db"], 6.0206, places=2)
        self.assertGreater(metrics["rms_envelope"]["correlation"], 0.99999)
        self.assertGreater(metrics["stft_cosine"]["mean"], 0.99999)

    def test_silence_and_different_lengths_are_controlled(self) -> None:
        metrics = self.compare([0.0] * 44_100, [0.0] * 22_050)
        self.assertIsNone(metrics["levels"]["savage_rms_dbfs"])
        self.assertIsNone(metrics["rms_envelope"]["correlation"])
        self.assertIsNone(metrics["stft_cosine"]["mean"])
        self.assertEqual(metrics["timing"]["difference_frames"], 22_050)
        json.dumps(metrics, allow_nan=False)

    def test_invalid_wav_is_rejected(self) -> None:
        invalid = self.directory / "invalid.wav"
        invalid.write_bytes(b"kein wav")
        valid = self.directory / "valid.wav"
        write_wav(valid, [0.0] * 100)
        with self.assertRaises(reference_compare.ComparisonError):
            reference_compare.analyze_wavs(invalid, valid)

    def test_wrong_wav_format_is_rejected(self) -> None:
        wrong = self.directory / "wrong.wav"
        write_wav(wrong, [0.0] * 100, rate=48_000)
        valid = self.directory / "valid.wav"
        write_wav(valid, [0.0] * 100)
        with self.assertRaises(reference_compare.ComparisonError):
            reference_compare.analyze_wavs(wrong, valid)

    def test_mono_and_eight_bit_wavs_are_rejected_separately(self) -> None:
        valid = self.directory / "valid.wav"
        write_wav(valid, [0.0] * 100)
        mono = self.directory / "mono.wav"
        write_wav(mono, [0.0] * 100, channels=1)
        eight_bit = self.directory / "eight-bit.wav"
        write_wav(eight_bit, [0.0] * 100, sample_width=1)
        with self.assertRaises(reference_compare.ComparisonError):
            reference_compare.analyze_wavs(mono, valid)
        with self.assertRaises(reference_compare.ComparisonError):
            reference_compare.analyze_wavs(eight_bit, valid)

    def test_active_end_and_onset_tolerance_boundaries(self) -> None:
        self.assertEqual(reference_compare.active_end([1.0], 100), 100)
        inside = reference_compare.onset_metrics([0], [2], 0)
        outside = reference_compare.onset_metrics([0], [3], 0)
        self.assertEqual(inside["matches"], 1)
        self.assertLessEqual(inside["max_error_ms"], 50.0)
        self.assertEqual(outside["matches"], 0)

    def test_it_is_accepted_after_public_integration(self) -> None:
        module = self.directory / "fixture.it"
        module.write_bytes(b"IMPM")
        self.assertEqual(reference_compare.validate_modules([module]), [module.resolve()])

    def test_unknown_format_is_rejected_before_any_subprocess(self) -> None:
        module = self.directory / "fixture.unknown"
        module.write_bytes(b"synthetic-module")
        with mock.patch.object(reference_compare.subprocess, "run") as run:
            with self.assertRaises(reference_compare.ComparisonError):
                reference_compare.run_comparison([module], self.directory / "out")
            run.assert_not_called()

    def test_openmpt_version_contract_and_override(self) -> None:
        canonical = "openmpt123 v0.8.7\nlibopenmpt 0.8.7+r25325.pkg"
        reference_compare.require_openmpt_version(canonical)
        with self.assertRaises(reference_compare.ComparisonError):
            reference_compare.require_openmpt_version("openmpt123 v9")
        reference_compare.require_openmpt_version("openmpt123 v9", allow_mismatch=True)

    def test_openmpt_duration_parser_supports_minutes_andHours(self) -> None:
        self.assertEqual(
            reference_compare.parse_openmpt_duration("Duration...: 00:46.080\n"),
            46.08,
        )
        self.assertEqual(
            reference_compare.parse_openmpt_duration("Duration...: 01:02:03.500\n"),
            3723.5,
        )
        with self.assertRaises(reference_compare.ComparisonError):
            reference_compare.parse_openmpt_duration("Title......: leer\n")

    def test_render_subprocess_arguments_match_contract(self) -> None:
        module = self.directory / "fixture.mod"
        module.write_bytes(b"synthetic-module")
        output = self.directory / "reports"
        commands: list[list[str]] = []

        def fake_run(command: list[str], **_: object) -> mock.Mock:
            commands.append(command)
            output_flag = "--out" if "--out" in command else "--output"
            wav_path = Path(command[command.index(output_flag) + 1])
            write_wav(wav_path, test_signal(seconds=2.2))
            return mock.Mock(returncode=0)

        canonical = "openmpt123 v0.8.7\nlibopenmpt 0.8.7+r25325.pkg"
        with mock.patch.object(reference_compare, "openmpt_version", return_value=canonical):
            with mock.patch.object(reference_compare, "openmpt_module_duration", return_value=2.2):
                with mock.patch.object(reference_compare.subprocess, "run", side_effect=fake_run):
                    reports = reference_compare.run_comparison([module], output)

        self.assertEqual(len(commands), 2)
        self.assertEqual(
            commands[0][:3],
            [".build/release/savage-cli", str(module.resolve()), "--out"],
        )
        self.assertEqual(commands[0][4:], ["--rate", "44100", "--seconds", "600", "--quiet"])
        self.assertEqual(
            commands[1][:12],
            ["openmpt123", "--batch", "--quiet", "--samplerate", "44100",
             "--channels", "2", "--no-float", "--gain", "0", "--stereo", "80"],
        )
        self.assertEqual(
            commands[1][12:28],
            ["--filter", "2", "--ramping", "0", "--tempo", "1", "--pitch", "1",
             "--dither", "0", "--subsong", "0", "--repeat", "0", "--end-time", "600"],
        )
        self.assertEqual(commands[1][28], "--force")
        self.assertEqual(commands[1][29], "--output")
        self.assertEqual(commands[1][-2:], ["--", str(module.resolve())])
        self.assertEqual(len(reports), 1)

    def test_report_json_is_deterministic(self) -> None:
        module = self.directory / "fixture.mod"
        module.write_bytes(b"synthetic-module")
        wav = self.directory / "same.wav"
        write_wav(wav, test_signal(seconds=2.2))
        version = "openmpt123 v0.8.7\nlibopenmpt 0.8.7+r25325.pkg"
        first = reference_compare.make_report(module, wav, wav, version)
        second = reference_compare.make_report(module, wav, wav, version)
        first_json = json.dumps(first, sort_keys=True, allow_nan=False)
        second_json = json.dumps(second, sort_keys=True, allow_nan=False)
        self.assertEqual(first_json, second_json)
        self.assertNotIn(self.temporary.name, first_json)
        self.assertEqual(first["schema"], "savage-reference-report/v2")


if __name__ == "__main__":
    unittest.main(verbosity=2)
