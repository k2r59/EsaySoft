#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD/.tools/vendor"
RUNTIME_OUTPUT="${EASYMUSIC_RUNTIME_OUTPUT:-$PWD/.tools/runtime}"
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
     make -j 6 && make install) > "$PREFIX/lame-build.log" 2>&1
  fi
  if [ ! -f "$PREFIX/bin/ffmpeg" ] || [ "$(cat "$PREFIX/.ffmpeg-build-revision" 2>/dev/null || true)" != "$FFMPEG_BUILD_REVISION" ]; then
    (cd "$PREFIX/ffmpeg-build"
     "$ROOT/FFmpeg-n8.1.2/configure" --prefix="$PREFIX" --cc="clang -arch $ARCH" --arch="$ARCH" --target-os=darwin --enable-cross-compile --disable-asm --disable-shared --enable-static --disable-autodetect --disable-doc --disable-debug --disable-ffplay --disable-everything --enable-ffmpeg --enable-ffprobe --enable-avformat --enable-avcodec --enable-avfilter --enable-swresample --enable-swscale --enable-network --enable-securetransport --enable-libmp3lame --enable-zlib --extra-cflags="-I$PREFIX/include -mmacosx-version-min=13.0" --extra-ldflags="-L$PREFIX/lib -mmacosx-version-min=13.0" --enable-protocol=file,http,https,tcp,tls,crypto,pipe --enable-demuxer=mov,mp3,ogg,matroska,wav,aac,flac,hls,mpegts,image2,jpeg_pipe,png_pipe,webp_pipe --enable-muxer=mp3,mp4,mov,ipod,adts,flac,wav,ogg,matroska,webm,image2,null --enable-decoder=aac,aac_latm,ac3,eac3,alac,flac,mp3,mp3float,opus,vorbis,pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le,png,mjpeg,webp --enable-encoder=aac,alac,flac,pcm_s16le,pcm_s24le,pcm_s32le,libmp3lame,png,mjpeg --enable-parser=aac,aac_latm,ac3,flac,mpegaudio,opus,vorbis,png,mjpeg --enable-filter=anull,aresample,atrim,asetpts,aformat,scale,format,apad --enable-bsf=aac_adtstoasc,extract_extradata,mjpeg2jpeg
     make -j 6 && make install) > "$PREFIX/ffmpeg-build.log" 2>&1
    echo "$FFMPEG_BUILD_REVISION" > "$PREFIX/.ffmpeg-build-revision"
  fi
  echo "Audio runtime built: $ARCH"
done
for TOOL in ffmpeg ffprobe; do lipo -create "$ROOT/arm64/bin/$TOOL" "$ROOT/x86_64/bin/$TOOL" -output "$RUNTIME_OUTPUT/$TOOL"; done
fetch https://nodejs.org/dist/v22.23.4/node-v22.23.4-darwin-arm64.tar.gz "$ROOT/node-arm64.tar.gz" c9e1dbc748b33ed2d14f42445191ecaf14c56259c7a9a26d0042c49ec2b66428
fetch https://nodejs.org/dist/v22.23.4/node-v22.23.4-darwin-x64.tar.gz "$ROOT/node-x64.tar.gz" efcc2b0db6f94bf53eddb038fe2b370277a042bd29e4f19b8f8e23598795b819
for ARCH in arm64 x64; do [ -d "$ROOT/node-v22.23.4-darwin-$ARCH" ] || tar -xf "$ROOT/node-$ARCH.tar.gz" -C "$ROOT"; done
lipo -create "$ROOT/node-v22.23.4-darwin-arm64/bin/node" "$ROOT/node-v22.23.4-darwin-x64/bin/node" -output "$RUNTIME_OUTPUT/node"

[ -f "$ROOT/yt-dlp-THIRD-PARTY-LICENSES.txt" ] || curl -fL --max-time 60 https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.10.26/THIRD_PARTY_LICENSES.txt -o "$ROOT/yt-dlp-THIRD-PARTY-LICENSES.txt"
