# Third-party fixtures: genuine encoder output

Round-3 acceptance criterion 16 requires that a *real* Vorbis or Opus file still passes the
scanner. Nothing in this environment can encode one (no `ffmpeg`, `oggenc`, `opusenc`, `sox`, no
`libopus`/`libvorbis`, no `pip`, no `sudo` -- see the task log), and a hand-built stream would be
worthless as evidence anyway: it would share this repository's reading of the specifications with
the parser it is meant to test, which is exactly what criterion 13 forbids.

So both files below are unmodified, byte-for-byte, from established open-source test corpora. They
were produced by real encoders (`libvorbis` / `libopus` via `libavformat`, per their own vendor
strings), by people with no knowledge of this scanner.

| File | Bytes | SHA-256 | Origin | Licence |
|---|---|---|---|---|
| `real-vorbis-sound_0.oga` | 4239 | `b0508595f9de6f6d81c6d00f687e423265877ac5fac8a7649e6d3f7e4ecf7fc8` | [web-platform-tests](https://github.com/web-platform-tests/wpt) `media/sound_0.oga`, fetched 2026-09-03 | WPT: 3-Clause BSD / W3C Test Suite Licence |
| `real-opus-opus-test.opus` | 14128 | `78214b3eac788076db103e3f84c89995bc124cde0c86fc5096e74e66abaf5c66` | [Chromium](https://github.com/chromium/chromium) `media/test/data/opus-test.opus`, fetched 2026-09-03 | Chromium: 3-Clause BSD |

Exact digests are in `sha256sums.txt` next to this file; `python3 -c "import hashlib,sys;
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" <file>` reproduces them.

Their internal shape (why they are useful as fixtures):

- `real-vorbis-sound_0.oga` -- 3 pages, one logical bitstream. Page 0 carries the `\x01vorbis`
  identification header; page 1 carries the `\x03vorbis` comment header (vendor `Lavf56.40.101`,
  one `encoder=` tag) *and* the `\x05vorbis` setup header, with the setup packet spanning 16
  lacing values of 255. That exercises the packet-reassembly path, not just a one-packet-per-page
  happy case.
- `real-opus-opus-test.opus` -- 3 pages, one logical bitstream: `OpusHead` (channel mapping family
  0, 19 bytes), `OpusTags` (vendor `Lavf54.20.4`, one tag, no padding), then one audio page of 102
  segments.

Do not regenerate or "clean up" these files. Their value is that this project did not make them.
