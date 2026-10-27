"""Generate only Streamify-owned synthetic HLS, without a network input.

Usage: python generate_offline_hls_control.py --ffmpeg /trusted/path/ffmpeg
The pinned FFmpeg version and executable SHA-256 are recorded in fixture.json.
Run with the same binary for byte-identical output. The AES key below is PUBLIC
TEST DATA, derived locally from a fixture label; it is never a provider key.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(binary, args, cwd, timeout=60):
    # Lists, no shell/interpolation/network input; stdin is never interactive.
    result = subprocess.run([str(binary), "-nostdin", "-hide_banner", *args],
                            cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True,
                            text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"Local FFmpeg exited {result.returncode}: {result.stderr[-4000:]}")
    return result


def rates(folder, rendition):
    text = (folder / f"{rendition}.m3u8").read_text(encoding="utf-8")
    durations = [float(value) for value in re.findall(r"#EXTINF:([^,]+),", text)]
    segments = [line for line in text.splitlines() if line and not line.startswith("#")]
    bits = [(folder / name).stat().st_size * 8 for name in segments]
    assert len(bits) == len(durations) == 3
    return max(size / duration for size, duration in zip(bits, durations)), sum(bits) / sum(durations)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", required=True, type=Path)
    args = parser.parse_args()
    binary = args.ffmpeg.resolve(strict=True)
    root = Path(__file__).resolve().parent / "Fixtures" / "offline-hls-control"
    root.mkdir(parents=True, exist_ok=True)
    # No caller-supplied destination and no recursive delete/move. The only
    # overwritten files are this generator's explicitly named test outputs.
    commands = []
    key = hashlib.sha256(b"Streamify public synthetic HLS fixture AES-128 v1").digest()[:16]
    iv = "00112233445566778899aabbccddeeff"
    for protected in [False, True]:
        folder = root / ("aes128" if protected else "clear")
        folder.mkdir(exist_ok=True)
        keyinfo = None
        try:
            encryption = []
            if protected:
                (folder / "fixture.key").write_bytes(key)
                with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="\n",
                                                 suffix=".keyinfo", prefix="own-fixture-", dir=folder,
                                                 delete=False) as file:
                    keyinfo = Path(file.name)
                    file.write(f"fixture.key\n{(folder / 'fixture.key').as_posix()}\n{iv}\n")
                encryption = ["-hls_key_info_file", str(keyinfo)]
            common = ["-t", "5", "-map_metadata", "-1", "-fflags", "+bitexact"]
            hls = ["-f", "hls", "-hls_time", "2", "-hls_playlist_type", "vod", "-start_number", "0"]
            video = ["-y", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24", *common,
                     "-an", "-c:v", "libx264", "-preset", "veryfast", "-threads", "1",
                     "-x264-params", "threads=1:lookahead-threads=1:sliced-threads=0",
                     "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
                     "-b:v", "900k", "-maxrate", "1000k", "-bufsize", "1500k",
                     "-g", "48", "-keyint_min", "48", "-sc_threshold", "0", "-flags:v", "+bitexact",
                     *hls, "-hls_flags", "independent_segments", *encryption,
                     "-hls_segment_filename", "video-%02d.ts", "video.m3u8"]
            audio = ["-y", "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000", *common,
                     "-vn", "-ac", "2", "-c:a", "aac", "-profile:a", "aac_low", "-b:a", "96k",
                     "-flags:a", "+bitexact", *hls, *encryption,
                     "-hls_segment_filename", "audio-en-%02d.ts", "audio-en.m3u8"]
            for command in [video, audio]:
                run(binary, command, folder)
                # Replace machine-specific, temporary local path in the audit.
                commands.append(["<local-own-keyinfo>" if keyinfo and part == str(keyinfo) else part for part in command])
            video_peak, video_average = rates(folder, "video")
            audio_peak, audio_average = rates(folder, "audio-en")
            peak = math.ceil(video_peak + audio_peak)
            average = math.ceil(video_average + audio_average)
            master = "\n".join([
                "#EXTM3U", "#EXT-X-VERSION:6", "#EXT-X-INDEPENDENT-SEGMENTS",
                '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="english",NAME="English",LANGUAGE="en",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="audio-en.m3u8"',
                f'#EXT-X-STREAM-INF:BANDWIDTH={peak},AVERAGE-BANDWIDTH={average},RESOLUTION=1920x1080,FRAME-RATE=24.000,CODECS="avc1.640028,mp4a.40.2",AUDIO="english"',
                "video.m3u8", ""])
            (folder / "master.m3u8").write_text(master, encoding="utf-8", newline="\n")
        finally:
            if keyinfo:
                # Exactly this process's temporary key-info text, no directory
                # deletion. The deliberately public fixture key stays in place.
                keyinfo.unlink(missing_ok=True)

    validations = []
    for name in ["clear", "aes128"]:
        folder = root / name
        for path in folder.glob("*.m3u8"):
            text = path.read_text(encoding="utf-8")
            assert "http:" not in text and "https:" not in text, "All fixture URIs must remain relative"
            assert ":/" not in text and ".." not in text, "No machine path or traversal in fixture"
            if path.name != "master.m3u8":
                assert "#EXT-X-ENDLIST" in text and "#EXT-X-PLAYLIST-TYPE:VOD" in text
                assert text.count("#EXTINF:") == 3
                assert ('METHOD=AES-128' in text) == (name == "aes128")
                assert "KEYFORMAT" not in text and "SAMPLE-AES" not in text
        result = run(binary, ["-protocol_whitelist", "file,crypto,data", "-allowed_extensions", "ALL",
                             "-i", "master.m3u8", "-map", "0:v:0", "-map", "0:a:0", "-threads", "2",
                             "-progress", "pipe:1", "-nostats", "-f", "null", "-"], folder)
        frames = re.findall(r"^frame=(\d+)$", result.stdout, re.MULTILINE)
        assert frames and int(frames[-1]) == 120, "Must decode the complete five-second, 24fps fixture"
        assert "1920x1080" in result.stderr and "48000 Hz, stereo" in result.stderr
        assert "progress=end" in result.stdout
        validations.append({"version": name, "localFFmpegFullDecode": True, "decodedVideoFrames": 120,
                            "width": 1920, "height": 1080, "audio": "AAC LC, 48000 Hz, stereo, English rendition",
                            "appleNativePackageTest": "not run by generator"})

    files = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.name not in ["fixture.json", "SHA256SUMS.txt"]:
            data = path.read_bytes()
            files.append({"path": path.relative_to(root).as_posix(), "bytes": len(data), "sha256": sha(data)})
    total = sum(item["bytes"] for item in files)
    assert total < 2 * 1024 * 1024, "Combined fixture assets must remain below 2 MiB"
    version = subprocess.run([str(binary), "-version"], capture_output=True, text=True, check=True).stdout.splitlines()[0]
    record = {"fixture": "Streamify-owned synthetic five-second HLS control", "generatorVersion": 1,
              "durationSeconds": 5, "videoFrames": 120, "fps": 24,
              "sources": ["FFmpeg lavfi testsrc2", "FFmpeg lavfi sine 880Hz"],
              "externalMedia": False, "networkRequests": 0,
              "key": "PUBLIC TEST KEY, locally derived from a fixture label; no provider key",
              "keyDerivationLabel": "Streamify public synthetic HLS fixture AES-128 v1", "keyHex": key.hex(), "ivHex": iv,
              "ffmpegVersion": version, "ffmpegExecutableSHA256": sha(binary.read_bytes()),
              "commands": commands, "totalAssetBytes": total, "files": files, "validation": validations}
    (root / "fixture.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8", newline="\n")
    (root / "SHA256SUMS.txt").write_text("".join(f"{item['sha256']}  {item['path']}\n" for item in files), encoding="ascii", newline="\n")
    print(json.dumps({"root": str(root), "totalAssetBytes": total, "files": len(files), "validation": validations}, indent=2))


if __name__ == "__main__":
    main()
