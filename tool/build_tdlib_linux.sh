#!/usr/bin/env bash
#
# Builds TDLib for Linux into linux/tdlib/linux-<arch>/libtdjson.so.
#
#   tool/build_tdlib_linux.sh [x64|arm64]
#
# handy_tdlib ships TDLib for Android only. This builds the same TDLib commit
# from source, with OpenSSL linked in, inside an Ubuntu 22.04 container, so
# the library runs on any Linux with glibc 2.35 or newer whatever machine
# built it. It needs Docker; on a Mac, Docker runs the other architecture
# through emulation, which is slow. The architecture defaults to this
# machine's. Run it again after changing TD_COMMIT or OPENSSL_VERSION.
set -euo pipefail

# The commit handy_tdlib's Dart API was generated from (TDLib 1.8.36). Keep
# the two in step: a different TDLib can send objects the Dart side cannot
# parse, or reject requests it builds.
TD_COMMIT=87d881071fe514936bb17029e96761141287d2be

OPENSSL_VERSION=3.5.9
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a

IMAGE=ubuntu:22.04

root="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-$(uname -m)}" in
  x64 | x86_64 | amd64) arch=x64 docker_platform=linux/amd64 openssl_target=linux-x86_64 ;;
  arm64 | aarch64) arch=arm64 docker_platform=linux/arm64 openssl_target=linux-aarch64 ;;
  *) echo "usage: $0 [x64|arm64]" >&2; exit 1 ;;
esac

work="build/tdlib-linux-$arch"
out="linux/tdlib/linux-$arch"

# Outside the container: start it on this script, with the repository
# mounted, and come back once the library is in place.
if [ "${TDLIB_IN_CONTAINER:-}" != 1 ]; then
  command -v docker > /dev/null || { echo "docker is required" >&2; exit 1; }
  docker run --rm --platform "$docker_platform" \
    -e TDLIB_IN_CONTAINER=1 -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$root:/src" -w /src "$IMAGE" tool/build_tdlib_linux.sh "$arch"
  echo "Built $root/$out/libtdjson.so"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential cmake gperf git curl ca-certificates perl zlib1g-dev binutils > /dev/null

# Some of TDLib's files take about 2 GB each to compile, so the jobs are
# held to what memory allows; TDLIB_JOBS overrides it.
memory_gb=$(($(awk '/MemTotal/ { print $2 }' /proc/meminfo) / 1024 / 1024))
jobs="${TDLIB_JOBS:-$(( memory_gb / 2 < $(nproc) ? memory_gb / 2 : $(nproc) ))}"
[ "$jobs" -ge 1 ] || jobs=1
mkdir -p "$work"
cd "$work"

# Sources.
if [ ! -d td ]; then
  git clone https://github.com/tdlib/td.git td
fi
git config --global --add safe.directory "$PWD/td"
git -C td cat-file -e "$TD_COMMIT^{commit}" 2> /dev/null || git -C td fetch origin
git -C td checkout -q "$TD_COMMIT"

openssl_tar="openssl-$OPENSSL_VERSION.tar.gz"
if [ ! -f "$openssl_tar" ]; then
  curl -fL -o "$openssl_tar.part" \
    "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/$openssl_tar"
  mv "$openssl_tar.part" "$openssl_tar"
fi
echo "$OPENSSL_SHA256  $openssl_tar" | sha256sum -c -

# OpenSSL, static and position-independent, to link into libtdjson.
ssl="$PWD/openssl"
if [ ! -f "$ssl/lib/libcrypto.a" ]; then
  rm -rf openssl-src
  mkdir openssl-src
  tar xzf "$openssl_tar" -C openssl-src --strip-components 1
  (
    cd openssl-src
    ./Configure "$openssl_target" no-shared no-tests no-apps no-docs no-engine no-async \
      -fPIC --prefix="$ssl" --libdir=lib
    make -j "$jobs" build_libs
    make install_dev
  )
fi

# The C++ runtime goes in too, so the library needs nothing but glibc, zlib
# and what every desktop has.
cmake -S td -B td-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL" \
  -DOPENSSL_FOUND=1 \
  -DOPENSSL_INCLUDE_DIR="$ssl/include" \
  -DOPENSSL_CRYPTO_LIBRARY="$ssl/lib/libcrypto.a" \
  -DOPENSSL_SSL_LIBRARY="$ssl/lib/libssl.a" \
  -DOPENSSL_LIBRARIES="$ssl/lib/libssl.a;$ssl/lib/libcrypto.a"
cmake --build td-build --target tdjson -j "$jobs"

cd /src
mkdir -p "$out"
cp -L "$work/td-build/libtdjson.so" "$out/libtdjson.so"
strip --strip-unneeded "$out/libtdjson.so"

# The library must not need a shared OpenSSL or C++ runtime, nor carry text
# relocations.
needed="$(readelf -d "$out/libtdjson.so" | grep NEEDED || true)"
if echo "$needed" | grep -qE 'libssl|libcrypto|libstdc\+\+|libgcc_s'; then
  echo "libtdjson.so needs a library that isn't on every Linux:" >&2
  echo "$needed" >&2
  exit 1
fi
if readelf -d "$out/libtdjson.so" | grep -q TEXTREL; then
  echo "libtdjson.so has text relocations" >&2
  exit 1
fi
echo "$needed"
chown -R "$HOST_UID:$HOST_GID" "$work" linux/tdlib
