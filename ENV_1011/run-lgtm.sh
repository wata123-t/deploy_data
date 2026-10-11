#!/usr/bin/env bash

set -euo pipefail

# データの保存先
LOCAL_VOLUME=${PWD}/container

# ディレクトリの作成
for dir in grafana prometheus loki; do
	test -d "${LOCAL_VOLUME}"/${dir} || mkdir -p "${LOCAL_VOLUME}"/${dir}
done

# ダミーの環境変数ファイル作成
test -f .env || touch .env

# Docker環境の固定値設定
RUNTIME=docker
RUNTIME_COMMAND=docker
MOUNT_OPTS=rw

# Docker Hubからダウンロードするイメージ
IMAGE="grafana/otel-lgtm:latest"

# 起動フラグの組み立て
RUN_FLAGS=(
	--name lgtm
	--init
)

# ポルト番号の設定とコンテナ自動削除(--rm)
RUN_FLAGS+=(
	-p 3000:3000
	-p 3200:3200
	-p 4040:4040
	-p 4317:4317
	-p 4318:4318
	-p 9090:9090
)

# マウントと環境変数の設定
RUN_FLAGS+=(
	-v "${LOCAL_VOLUME}"/grafana:/data/grafana:"${MOUNT_OPTS}"
	-v "${LOCAL_VOLUME}"/prometheus:/data/prometheus:"${MOUNT_OPTS}"
	-v "${LOCAL_VOLUME}"/loki:/data/loki:"${MOUNT_OPTS}"
    -v "${PWD}"/my-dashboards:/var/lib/grafana/dashboards/my-dashboards:"${MOUNT_OPTS}"
    -v "${PWD}"/my-dashboard-config.yaml:/otel-lgtm/grafana/conf/provisioning/dashboards/my-dashboard-config.yaml:"${MOUNT_OPTS}"
    -v "${PWD}"/clear-defaults.yaml:/otel-lgtm/grafana/conf/provisioning/dashboards/grafana-dashboards.yaml:"${MOUNT_OPTS}"
	-e GF_PATHS_DATA=/data/grafana
	-e CONTAINER_RUNTIME="$RUNTIME_COMMAND"
	-e OTEL_COLLECTOR_DEBUG_EXPORTER="${OTEL_COLLECTOR_DEBUG_EXPORTER:-}"
	--env-file .env
)

# コンテナの起動
"$RUNTIME_COMMAND" run -d "${RUN_FLAGS[@]}" "$IMAGE"


