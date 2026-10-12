#!/bin/bash
# エラーが発生したら即座にスクリプトを終了させる設定
set -euo pipefail

# 💡 一般ユーザー（ec2-userなど）で実行された場合は、自動的にsudoを適用してrootで再実行します
if [ "$EUID" -ne 0 ]; then
  echo "root権限で再実行しています..."
  exec sudo "$0" "$@"
fi

echo "=========================================================="
echo "=== 1. GitHubから特定のディレクトリ（ENV_1011）のみを取得 ==="
echo "=========================================================="
dnf install -y git
sleep 5

mkdir -p /opt/deploy_data
cd /opt/deploy_data

# 既存の古いフォルダがあればリセット（手動で何回も実行できるようにするため）
rm -rf .git ENV_1011

# Sparse Checkout（部分チェックアウト）の設定
git init
git remote add origin https://github.com/wata123-t/deploy_data
git config core.sparseCheckout true
echo "ENV_1011/" >> .git/info/sparse-checkout

# データの引っ張りと移動
git pull origin main
cd ENV_1011

echo "=========================================================="
echo "=== 2. Docker & Docker Compose のインストールと起動 ==="
echo "=========================================================="
dnf install -y docker
sleep 5
systemctl enable --now docker

# Docker Compose V2 のインストール（すでに存在する場合はスキップ）
if [ ! -f /usr/local/lib/docker/cli-plugins/docker-compose ]; then
  mkdir -p /usr/local/lib/docker/cli-plugins/
  curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

echo "=========================================================="
echo "=== 3. Grafana Labs公式「LGTMスタック」デモの実行 ==="
echo "=========================================================="
chmod +x ./run-lgtm.sh
./run-lgtm.sh
sleep 10

echo "=========================================================="
echo "=== 4. Python 3.11 & 開発ツールのインストール ==="
echo "=========================================================="
dnf install -y python3.11 python3.11-pip python3.11-devel gcc
sleep 10

echo "=========================================================="
echo "=== 5. 必要なPythonライブラリの一括インストール ==="
echo "=========================================================="
python3.11 -m pip install --upgrade pip
sleep 10
python3.11 -m pip install flask opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-instrumentation-flask opentelemetry-instrumentation-system-metrics locust
sleep 10

echo "=========================================================="
echo "=== 6. アプリケーションフォルダの作成とファイルのコピー ==="
echo "=========================================================="
mkdir -p /opt/script/python/app

# GitHubから落としてきた相対パスからファイルをコピー
cp "./python/app.py" /opt/script/python/app/app.py
cp "./python/locustfile.py" /opt/script/python/locustfile.py

echo "=========================================================="
echo "=== 7. 各種サービス（systemd）ファイルの配置と起動 ==="
echo "=========================================================="
cp "./services/flask-app.service" /etc/systemd/system/flask-app.service
cp "./services/locust-worker.service" /etc/systemd/system/locust-worker.service

systemctl daemon-reload
systemctl enable --now flask-app locust-worker

echo "=========================================================="
echo "=== すべてのセットアップ処理が正常に完了しました！ ==="
echo "=========================================================="
