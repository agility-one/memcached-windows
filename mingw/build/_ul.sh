#!/bin/sh

# Copyright 2014-2019 Viktor Szakats <https://vsz.me/>
# See LICENSE.md

cd "$(dirname "$0")" || exit

# Detect host OS
case "$(uname)" in
  *_NT*)   os='win';;
  Linux*)  os='linux';;
  Darwin*) os='mac';;
  *BSD)    os='bsd';;
esac

do_upload() {
  arch_ext="$1"

  if [ "${_BRANCH#*master*}" != "${_BRANCH}" ]; then
    _sufpkg=
    _suf=

    if [ ! "${PUBLISH_PROD_FROM}" = "${os}" ]; then
      _suf="-built-on-${os}"
      mv "${_BAS}${arch_ext}" "${_BAS}${_suf}${arch_ext}"
    fi
  else
    # Do not sign test packages
    GPG_PASSPHRASE=
    _sufpkg='-test'
    _suf="-test-built-on-${os}"
    mv "${_BAS}${arch_ext}" "${_BAS}${_suf}${arch_ext}"
  fi

  # <filename>: <size> bytes <YYYY-MM-DD> <HH:MM>
  case "${os}" in
    bsd|mac) TZ=UTC stat -f '%N: %z bytes %Sm' -t '%Y-%m-%d %H:%M' "${_BAS}${_suf}${arch_ext}";;
    *)       TZ=UTC stat -c '%n: %s bytes %y' "${_BAS}${_suf}${arch_ext}";;
  esac

  openssl dgst -sha256 "${_BAS}${_suf}${arch_ext}" | tee -a hashes.txt
  openssl dgst -sha512 "${_BAS}${_suf}${arch_ext}" | tee -a hashes.txt

  if [ "${_BRANCH#*master*}" != "${_BRANCH}" ] && \
     [ -n "${VIRUSTOTAL_APIKEY}" ]; then
  (
    set +x

    hshl="$(openssl dgst -sha256 "${_BAS}${_suf}${arch_ext}" \
      | sed -n -E 's,.+= ([0-9a-fA-F]{64}),\1,p')"
    # https://developers.virustotal.com/v3.0/reference
    out="$(curl -fsS \
      -X POST 'https://www.virustotal.com/api/v3/files' \
      --header "x-apikey: ${VIRUSTOTAL_APIKEY}" \
      --form "file=@${_BAS}${_suf}${arch_ext}")"
    # shellcheck disable=SC2181
    if [ "$?" = 0 ]; then
      id="$(echo "${out}" | jq -r '.data.id')"
      out="$(curl -fsS \
        -X GET "https://www.virustotal.com/api/v3/analyses/${id}" \
        --header "x-apikey: ${VIRUSTOTAL_APIKEY}")"
      # shellcheck disable=SC2181
      if [ "$?" = 0 ]; then
        hshr="$(echo "${out}" | jq -r '.meta.file_info.sha256')"
        if [ "${hshr}" = "${hshl}" ]; then
          echo "VirusTotal URL for '${_BAS}${_suf}${arch_ext}':"
          echo "https://www.virustotal.com/file/${hshr}/analysis/"
        else
          echo "VirusTotal hash mismatch with local hash:"
          echo "Remote: '${hshr}' vs."
          echo " Local: '${hshl}'"
        fi
      else
        echo "Error querying VirusTotal upload: $?"
      fi
    else
      echo "Error uploading to VirusTotal: $?"
    fi
  )
  fi
}

do_upload '.tar.xz'
do_upload '.zip'
