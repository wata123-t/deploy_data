from locust import HttpUser, task, between, LoadTestShape

# ==========================================================
# 📊 負荷シミュレーションの条件設定（変数化）
# ==========================================================
# テスト時は短く（60秒など）、本番（ポートフォリオ）は長く（600秒など）調整してください
CYCLE_DURATION_SEC = 60   # 1周期の長さ（秒）
PEAK_TIME_SEC = 30         # アクセスがピークに達するまでの時間（秒）
MAX_USERS = 30             # ピーク時の最大同時アクセスユーザー数
MIN_WAIT_INTERVAL = 1      # 各ユーザーの最小アクセス間隔（秒）
MAX_WAIT_INTERVAL = 3      # 各ユーザーの最大アクセス間隔（秒）
# ==========================================================

class DiceUser(HttpUser):
    # 各ユーザーは設定された変数の範囲でランダムに待機してアクセスします
    wait_time = between(MIN_WAIT_INTERVAL, MAX_WAIT_INTERVAL)

    @task
    def roll_dice(self):
        """通常アクセス（サイコロを振る）"""
        self.client.get("/rolldice?player=LocustBot")

    @task(3)
    def trigger_error(self):
        """エラーアクセス（Grafanaのエラー率グラフを変動させるため）"""
        self.client.get("/error")


class TimeVaryingShape(LoadTestShape):
    """時間経過とともにユーザー数を山なりに変調させるクラス"""
    
    def tick(self):
        run_time = self.get_run_time()
        
        # 現在の周期内での経過時間を計算
        cycle_time = (run_time % CYCLE_DURATION_SEC)
        
        if cycle_time < PEAK_TIME_SEC:
            # 💡 前半：徐々にアクセス（ユーザー数）を増やしていくフェーズ
            progress = cycle_time / PEAK_TIME_SEC
            users = int(progress * (MAX_USERS - 1)) + 1
        else:
            # 💡 後半：徐々にアクセス（ユーザー数）を減らしていくフェーズ
            time_since_peak = cycle_time - PEAK_TIME_SEC
            cooldown_duration = CYCLE_DURATION_SEC - PEAK_TIME_SEC
            
            # ゼロ除算を防ぐ安全処理
            if cooldown_duration <= 0:
                cooldown_duration = 1
                
            progress = time_since_peak / cooldown_duration
            users = int((1 - progress) * (MAX_USERS - 1)) + 1
            
        # 安全のためにユーザー数が1未満にならないようにガード
        users = max(1, users)
            
        # (現在の同時ユーザー数, 1秒あたりに増減していいユーザー数) を返す
        return (users, 2)

