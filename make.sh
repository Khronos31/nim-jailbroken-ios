#!/bin/bash
# com.khronos.nim | make.sh

set -e
set -u

PROJECTROOT="$(cd $(dirname $0)&&pwd)"
readonly PROJECTROOT
cd "${PROJECTROOT}"

ARCH="${ARCH-$(arch)}"
if [ "${ARCH}" = arm ]; then
  ARCH=armv7
fi

VERSION="1.2.0"
PATCHVERSION="1"

download() {
  if [ ! -r "${PROJECTROOT}/nim-${VERSION}.tar.xz" ]; then
    curl -o "${PROJECTROOT}/nim-${VERSION}.tar.xz" "https://nim-lang.org/download/nim-${VERSION}.tar.xz"
  fi
  tar xvf "${PROJECTROOT}/nim-${VERSION}.tar.xz" --exclude c_code -C "${BUILDROOT}"
}

init() {
  ARCH="$1"
  BUILDROOT="${PROJECTROOT}/${ARCH}"
  BUILDNIMROOT="${BUILDROOT}/nim-${VERSION}"
  if [ -e "${BUILDROOT}" ]; then
    rm -rf "${BUILDROOT}"
  fi
  mkdir -p "${BUILDROOT}"
}

applyPatch() {
  for p in $(find "${PROJECTROOT}/patches" -name "*.patch"); do
    patch -u -p0 -d "${BUILDROOT}" -i "$p"
  done
}

build() {
  cd "${BUILDNIMROOT}"
  mkdir -p "${BUILDNIMROOT}/bin"

  local cpu
  if [ "${ARCH}" = armv7 ]; then
    cpu=arm
  else
    cpu="${ARCH}"
  fi

  nim compile --os:macosx --cpu:"${cpu}" -d:release --opt:size koch
  ./koch boot --os:macosx --cpu:"${cpu}" -d:release --opt:size
  ./bin/nim compile --os:macosx --cpu:"${cpu}" -d:release --opt:size koch
  ./koch tools --os:macosx --cpu:"${cpu}" -d:release --opt:size
  cd "${PROJECTROOT}"
}

bundle() {
  local destdir="${BUILDROOT}/build"
  rm -rf "${destdir}"
  mkdir -p "${destdir}"

  local sharedir="${destdir}/usr/share"
  local bindir="${destdir}/usr/bin"
  local configdir="${destdir}/etc/nim"
  local libdir="${destdir}/usr/lib/nim"
  local docdir="${sharedir}/nim/doc"
  local licensedir="${sharedir}/licenses/nim"

  cd "${BUILDNIMROOT}"

  mkdir -p "${bindir}"
  cp -R bin/. "${bindir}"
  chmod -R 755 "${bindir}"

  mkdir -p "${configdir}"
  cp -R config/. "${configdir}"

  mkdir -p "${libdir}"
  cp -R lib/. "${libdir}"

  mkdir -p "${docdir}"
  cp -R doc/. "${docdir}"
  rm -rf "${docdir}/html"
  cp -R examples "${docdir}"

  mkdir -p "${licensedir}"
  cp -R copying.txt dist/nimble/license.txt "${licensedir}"

  mkdir -p "${sharedir}/bash-completion/completions"
  cp -R tools/nim.bash-completion "${sharedir}/bash-completion/completions/nim"
  cp -R dist/nimble/nimble.bash-completion "${sharedir}/bash-completion/completions/nimble"

  mkdir -p "${sharedir}/zsh/vendor-completions"
  cp -R tools/nim.zsh-completion "${sharedir}/zsh/vendor-completions/_nim"
  cp -R dist/nimble/nimble.zsh-completion "${sharedir}/zsh/vendor-completions/_nimble"

  cd "${PROJECTROOT}"
}

merge() {
  mkdir -p "${PROJECTROOT}/fat/build"
  cp -nR "${PROJECTROOT}/arm64/build/." "${PROJECTROOT}/fat/build"
  cp -nR "${PROJECTROOT}/armv7/build/." "${PROJECTROOT}/fat/build"

  cd "${PROJECTROOT}"

  find "fat/build" -type f |
  while read x; do
    if lipo -info "$x" >/dev/null 2>&1; then
      rm "$x"
      lipo -create "${x/fat/arm64}" "${x/fat/armv7}" -output "$x"
      if test -x "$x"; then
        ldid -S/usr/share/SDKs/entitlements.xml "$x"
      fi
    fi
  done
}

pack() {
  local ARCHS
  if [ "$1" = fat ]; then
    ARCHS="ARM64/ARMv7"
  elif [ "$1" = arm64 ]; then
    ARCHS=ARM64
  elif [ "$1" = armv7 ]; then
    ARCHS=ARMv7
  else
    echo "Unknown architecture." >&2
    exit 1
  fi
  BUILDROOT="${PROJECTROOT}/$1"
  cp -R "${PROJECTROOT}/deb/." "${BUILDROOT}/build"
  sed -e "/^Version:/s/%%VERSION%%/${VERSION}-${PATCHVERSION}/" \
      -e "/^Description:/s_%%ARCHS%%_${ARCHS}_" \
      -i -- "${BUILDROOT}/build/DEBIAN/control"
  if dpkg --compare-versions "$(dpkg-query -f '${Version}' -W dpkg)" ge 1.19.0; then
    dpkg-deb -Zgzip --root-owner-group --build "${BUILDROOT}/build" "${BUILDROOT}"
  else
    su <<<"chown -R 0:0 \"${BUILDROOT}/build\""
    dpkg-deb -Zgzip --build "${BUILDROOT}/build" "${BUILDROOT}"
  fi
}

init "${ARCH}"
download
applyPatch
build
bundle

# merge

pack "${ARCH}"
