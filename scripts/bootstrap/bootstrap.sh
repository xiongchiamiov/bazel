#!/bin/bash

# Copyright 2015 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Use bazel to bootstrap various tools
# Configuration:
#   BAZEL: path to the bazel binary
#   EMBED_LABEL: the label to embed in tools using --embed_label (optional)
#   BAZEL_ARGS: list of other arguments to pass to bazel (optional)
#   BAZELRC: the rc file to use

: ${BAZELRC:="/dev/null"}
: ${EMBED_LABEL:=""}

EMBED_LABEL_ARG=()
if [ -n "${EMBED_LABEL}" ]; then
    EMBED_LABEL_ARG=(--stamp --embed_label "${EMBED_LABEL}")
fi

: ${JAVA_VERSION:="1.8"}
: ${BAZEL_ARGS="--singlejar_top=//src/java_tools/singlejar:bootstrap_deploy.jar \
      --javabuilder_top=//src/java_tools/buildjar:bootstrap_deploy.jar \
      --genclass_top=//src/java_tools/buildjar:bootstrap_genclass_deploy.jar \
      --ijar_top=//third_party/ijar \
      --strategy=Javac=worker --worker_quit_after_build \
      ${EXTRA_BAZEL_ARGS-}"}

function bazel_bootstrap() {
  local mode=${3:-"0644"}
  if [[ ! ${BAZEL_SKIP_TOOL_COMPILATION-} =~ "$2" ]]; then
    log "Building $2"
    if [ -n "${4-}" ]; then
      ${BAZEL} --nomaster_bazelrc --bazelrc=${BAZELRC} \
          build ${BAZEL_ARGS} \
          --javacopt="-source ${JAVA_VERSION} -target ${JAVA_VERSION}" \
          "${EMBED_LABEL_ARG[@]}" $1
    else
      run_silent ${BAZEL} --nomaster_bazelrc --bazelrc=${BAZELRC} \
          build ${BAZEL_ARGS} \
          --javacopt="-source ${JAVA_VERSION} -target ${JAVA_VERSION}" \
          "${EMBED_LABEL_ARG[@]}" $1
    fi
    local file=bazel-bin/${1##//}
    cp -f ${file/:/\/} $2
    chmod ${mode} $2
  fi
}

function md5_outputs() {
  [ -n "${BAZEL_TEST_XTRACE:-}" ] && set +x  # Avoid garbage in the output
  # runfiles/MANIFEST & runfiles_manifest contain absolute path, ignore.
  # ar on OS-X is non-deterministic, ignore .a files.
  for i in $(find bazel-bin/ -type f -a \! -name MANIFEST -a \! -name '*.runfiles_manifest' -a \! -name '*.a'); do
    md5_file $i
  done
  for i in $(find bazel-genfiles/ -type f); do
    md5_file $i
  done
  [ -n "${BAZEL_TEST_XTRACE:-}" ] && set -x
}

function get_outputs_sum() {
  md5_outputs | sort -k 2
}

function bootstrap_test() {
  local BAZEL_BIN=$1
  local BAZEL_SUM=$2
  local BAZEL_TARGET=${3:-//src:bazel}
  [ -x "${BAZEL_BIN}" ] || fail "syntax: bootstrap bazel-binary"
  run_silent ${BAZEL_BIN} --nomaster_bazelrc --bazelrc=${BAZELRC} clean \
      --expunge || return $?
  run_silent ${BAZEL_BIN} --nomaster_bazelrc --bazelrc=${BAZELRC} build \
      ${BAZEL_ARGS} \
      --fetch --nostamp \
      --javacopt="-source ${JAVA_VERSION} -target ${JAVA_VERSION}" \
      ${BAZEL_TARGET} || return $?
  if [ -n "${BAZEL_SUM}" ]; then
    cat bazel-genfiles/src/java.version >${BAZEL_SUM}
    get_outputs_sum >> ${BAZEL_SUM} || return $?
  fi
  if [ -z "${BOOTSTRAP:-}" ]; then
    tempdir
    BOOTSTRAP=${NEW_TMPDIR}/bazel
    local FILE=bazel-bin/${BAZEL_TARGET##//}
    cp -f ${FILE/:/\/} $BOOTSTRAP
    chmod +x $BOOTSTRAP
  fi
}
