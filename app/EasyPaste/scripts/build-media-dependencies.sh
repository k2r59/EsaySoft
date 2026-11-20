#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="${EASYPASTE_MEDIA_CACHE:-$PWD/.tools}/vendor"
RUNTIME_OUTPUT="${EASYPASTE_MEDIA_CACHE:-$PWD/.tools}/runtime"
FFMPEG_BUILD_REVISION=2
mkdir -p "$ROOT" "$RUNTIME_OUTPUT"
fetch() {
  local url="$1" file="$2" hash="$3"
  [ -f "$file" ] || curl -fL --retry 2 --connect-timeout 15 --max-time 180 "$url" -o "$file"
  [ "$(shasum -a 256 "$file" | cut -d ' ' -f 1)" = "$hash" ] || { echo "Invalid checksum: $file" >&2; exit 1; }
}
fetch https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz "$ROOT/lame-3.100.tar.gz" ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
[ -d "$ROOT/lame-3.100" ] || tar -xf "$ROOT/lame-3.100.tar.gz" -C "$ROOT"
fetch https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n8.1.2.tar.gz "$ROOT/ffmpeg-8.1.2.tar.gz" 9fd092511605bbebafe095ea6d38d9e40f34d12f7386e1258372df8be0576eb7
[ -d "$ROOT/FFmpeg-n8.1.2" ] || tar -xf "$ROOT/ffmpeg-8.1.2.tar.gz" -C "$ROOT"
for ARCH in arm64 x86_64; do
  PREFIX="$ROOT/$ARCH"
  HOST="$ARCH-apple-darwin"
  [ "$ARCH" != "arm64" ] || HOST="arm-apple-darwin"
  mkdir -p "$PREFIX/lame-build" "$PREFIX/ffmpeg-build"
  if [ ! -f "$PREFIX/lib/libmp3lame.a" ]; then
    (cd "$PREFIX/lame-build"
     CC="clang -arch $ARCH" CFLAGS="-O2 -mmacosx-version-min=13.0" LDFLAGS="-mmacosx-version-min=13.0" "$ROOT/lame-3.100/configure" --prefix="$PREFIX" --host="$HOST" --disable-shared --enable-static --disable-frontend --disable-nasm
     make -j 2 && make install) > "$PREFIX/lame-build.log" 2>&1
  fi
  if [ ! -f "$PREFIX/bin/ffmpeg" ] || [ "$(cat "$PREFIX/.ffmpeg-build-revision" 2>/dev/null || true)" != "$FFMPEG_BUILD_REVISION" ]; then
    (cd "$PREFIX/ffmpeg-build"
     "$ROOT/FFmpeg-n8.1.2/configure" --prefix="$PREFIX" --cc="clang -arch $ARCH" --arch="$ARCH" --target-os=darwin --enable-cross-compile --disable-asm --disable-shared --enable-static --disable-autodetect --disable-doc --disable-debug --disable-ffplay --disable-everything --enable-ffmpeg --enable-ffprobe --enable-avformat --enable-avcodec --enable-avfilter --enable-swresample --enable-swscale --enable-network --enable-securetransport --enable-libmp3lame --enable-zlib --extra-cflags="-I$PREFIX/include -mmacosx-version-min=13.0" --extra-ldflags="-L$PREFIX/lib -mmacosx-version-min=13.0" --enable-protocol=file,http,https,tcp,tls,crypto,pipe --enable-demuxer=mov,mp3,ogg,matroska,wav,aac,flac,hls,mpegts,image2,jpeg_pipe,png_pipe,webp_pipe --enable-muxer=mp3,mp4,mov,ipod,adts,flac,wav,ogg,matroska,webm,image2,null --enable-decoder=aac,aac_latm,ac3,eac3,alac,flac,mp3,mp3float,opus,vorbis,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,png,mjpeg,webp --enable-encoder=aac,alac,flac,pcm_s16le,pcm_s24le,pcm_s32le,libmp3lame,png,mjpeg --enable-parser=aac,aac_latm,ac3,flac,mpegaudio,opus,vorbis,png,mjpeg --enable-filter=anull,aresample,atrim,asetpts,aformat,scale,format,apad --enable-bsf=aac_adtstoasc,extract_extradata,mjpeg2jpeg
     make -j 2 && make install) > "$PREFIX/ffmpeg-build.log" 2>&1
    echo "$FFMPEG_BUILD_REVISION" > "$PREFIX/.ffmpeg-build-revision"
  fi
  echo "Media runtime built: $ARCH"
done
for TOOL in ffmpeg ffprobe; do lipo -create "$ROOT/arm64/bin/$TOOL" "$ROOT/x86_64/bin/$TOOL" -output "$RUNTIME_OUTPUT/$TOOL"; done
fetch https://nodejs.org/dist/v22.23.4/node-v22.23.4-darwin-arm64.tar.gz "$ROOT/node-arm64.tar.gz" c9e1dbc748b33ed2d14f42445191ecaf14c56259c7a9a26d0042c49ec2b66428
fetch https://nodejs.org/dist/v22.23.4/node-v22.23.4-darwin-x64.tar.gz "$ROOT/node-x64.tar.gz" efcc2b0db6f94bf53eddb038fe2b370277a042bd29e4f19b8f8e23598795b819
for ARCH in arm64 x64; do [ -d "$ROOT/node-v22.23.4-darwin-$ARCH" ] || tar -xf "$ROOT/node-$ARCH.tar.gz" -C "$ROOT"; done
lipo -create "$ROOT/node-v22.23.4-darwin-arm64/bin/node" "$ROOT/node-v22.23.4-darwin-x64/bin/node" -output "$RUNTIME_OUTPUT/node"

fetch https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.10.26/THIRD_PARTY_LICENSES.txt "$ROOT/yt-dlp-THIRD-PARTY-LICENSES.txt" 472aefe951c7db35e1657c1d13fd337140511ed6f2b329205105ad441c5a02b7
fetch https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.10.26/LICENSE "$ROOT/yt-dlp-LICENSE.txt" 7e12e5df4bae12cb21581ba157ced20e1986a0508dd10d0e8a4ab9a4cf94e85c
# Corresponding sources accompany the source distribution, never the app bundle.
fetch https://files.pythonhosted.org/packages/83/31/4be3987022a6244550ab6a3afe45ad10ac10b5e5ab8874bd8eecc7f8b937/yt_dlp-2026.10.26.tar.gz "$ROOT/yt_dlp-2026.10.26.tar.gz" abe5c6b94c3b2f0560500add1c42e0a97641752743a5b65588ac2007a6e23eb6
fetch https://files.pythonhosted.org/packages/df/70/1675da133ea92227da41bf5b24e1c66be597ff736a1533ade41da986852f/mutagen-1.48.1.tar.gz "$ROOT/mutagen-1.48.1.tar.gz" 8f95637ab9f6f305cec6bd1294e197debe207998e3e068596563c74f86b0a173
fetch https://files.pythonhosted.org/packages/fd/11/b524cbd9bbdaca58608e4cf4053fd463417549e1959fa8d3aa18319f9555/certifi-2026.10.23.tar.gz "$ROOT/certifi-2026.10.23.tar.gz" a9895e6e2758b371e0545e321a3a8fd1fcfd9829ada8824a936dfb16aaaf36cd
