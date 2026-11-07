"""Synthetische MODs für visuelle Kanal-/Pegelvergleiche; keine Fremdmusik."""
import math
from pathlib import Path
import sys


def module(channels=4):
    assert channels in (4, 8, 32, 64)
    frames = 256
    data = bytearray(1084 + channels * 64 * 4 + frames)
    title = f"GUI signal {channels:02d} channels".encode()
    data[:len(title)] = title
    data[20:32] = b"Sine fixture"
    data[42:44] = (frames // 2).to_bytes(2, "big")
    data[45] = 64
    data[48:50] = (frames // 2).to_bytes(2, "big")
    data[950] = 1
    data[1080:1084] = b"M.K." if channels == 4 else f"{channels:02d}CH".encode()
    for row in range(0, 64, 8):
        for channel in range(channels):
            period = (428, 360, 320, 285)[channel % 4]
            offset = 1084 + (row * channels + channel) * 4
            data[offset:offset+4] = bytes([period >> 8, period & 255, 0x1C,
                                          (12, 32, 48, 64)[channel % 4]])
    start = 1084 + channels * 64 * 4
    for i in range(frames):
        data[start+i] = round(60 * math.sin(2 * math.pi * i / frames)) & 255
    return bytes(data)


if __name__ == "__main__":
    Path(sys.argv[1]).write_bytes(module(int(sys.argv[2]) if len(sys.argv)>2 else 4))
