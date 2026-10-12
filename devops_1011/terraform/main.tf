terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# 1. VPC（仮想ネットワーク）の作成
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "study-vpc"
  }
}

# 2. パブリックサブネットの作成
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # 起動時にパブリックIPを自動割り当て
  tags = {
    Name = "study-public-subnet"
  }
}

# 3. インターネットゲートウェイの作成（外の世界と繋ぐ窓口）
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "study-igw"
  }
}

# 4. ルートテーブルの作成と紐付け（ネットへの道を登録）
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "study-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# =================================================================================
# 1. セキュリティグループの定義
# =================================================================================
resource "aws_security_group" "ec2" {
  name        = "study-ec2-sg"
  description = "Security Group for OpenTelemetry and App Server"
  vpc_id      = aws_vpc.main.id # ※環境に合わせてVPC IDの変数名を調整してください

  # -------------------------------------------------------------------------------
  # 各種アプリケーション・可観測性ツール用のインバウンドルール（dynamicブロックで一括管理）
  # -------------------------------------------------------------------------------
  dynamic "ingress" {
    for_each = {
      22    = "SSH"
      3000  = "Grafana UI"
      16686 = "Jaeger UI"
      9090  = "Prometheus UI"
      3100  = "Loki"
      8000  = "Python Web App"
      9464  = "OpenTelemetry Prometheus Exporter"
      5000  = "Python App (Flask)"
      4317  = "OpenTelemetry (OTLP/gRPC)"
      4318  = "OpenTelemetry (OTLP/HTTP)"
      8080  = "OpenTelemetry Demo Web & Grafana"
    }

    content {
      description = ingress.value
      from_port   = ingress.key
      to_port     = ingress.key
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # -------------------------------------------------------------------------------
  # 【超重要】EC2同士（VPC内部）の全通信を許可するルール
  # -------------------------------------------------------------------------------
  ingress {
    description = "VPC Internal All Traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"            # すべてのプロトコルを許可
    cidr_blocks = ["10.0.0.0/16"] # VPC内部のIPアドレスからの通信をすべて許可
  }

  # -------------------------------------------------------------------------------
  # インターネットへの外向き通信をすべて許可（重複を排除して1つにスッキリ整理）
  # -------------------------------------------------------------------------------
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# =================================================================================
# 2. SSH接続用のキーペアを自動生成
# =================================================================================
resource "tls_private_key" "keygen" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "keypair" {
  key_name   = "study-key"
  public_key = tls_private_key.keygen.public_key_openssh
}

# 生成された秘密鍵（Terra Termで使う.pemファイル）をローカルに保存
resource "local_file" "private_key" {
  content  = tls_private_key.keygen.private_key_pem
  filename = "${path.module}/study-key.pem"
}

# =================================================================================
# 3. AWSから自動で最新のAmazon Linux 2023 AMI IDを取得
# =================================================================================
data "aws_ssm_parameter" "amzn_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# =================================================================================
# 4. EC2インスタンスの作成（GitHubパブリック方式・完全自動化版）
# =================================================================================
resource "aws_instance" "app_server" {
  ami           = data.aws_ssm_parameter.amzn_linux_2023.value
  instance_type = "t3.small"

  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.keypair.key_name

  # ルートディスク容量を30GB（無料枠の最大値）に増やす設定
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name = "study-ec2-1"
  }

  # ===============================================================================
  # 【完全自動化】初期化シェルスクリプト（user_data）
  # ===============================================================================
  user_data = <<-EOF
    #!/bin/bash
    # エラーが発生したら即座にスクリプトを終了させる設定
    set -euo pipefail

    echo "=========================================================="
    echo "=== 1. GitHubから特定のディレクトリ（ENV_1011）のみを取得 ==="
    echo "=========================================================="
    dnf install -y git
    sleep 5

    mkdir -p /opt/deploy_data
    cd /opt/deploy_data

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

    # Docker Compose V2 のインストール
    mkdir -p /usr/local/lib/docker/cli-plugins/
    curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    echo "=========================================================="
    echo "=== 3. Grafana Labs公式「LGTMスタック」デモの実行 ==="
    echo "=========================================================="
    # すでにGit側で権限を付与していますが、念のため再付与して実行
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
  EOF
}

