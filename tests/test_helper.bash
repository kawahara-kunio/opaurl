# test_helper.bash - Batsテスト共通設定

# プロジェクトルートディレクトリ
export PROJECT_ROOT="$BATS_TEST_DIRNAME/.."

# bin/opaurlから関数をロード
source "$PROJECT_ROOT/bin/opaurl"

# 共通の一時ファイル（テストディレクトリの直下）
TEST_TEMP_FILE="$BATS_TEST_DIRNAME/.test_temp"

# テスト用の一時ファイルを取得
get_temp_file() {
    echo "$TEST_TEMP_FILE"
}

# テスト用の一時ファイルをクリーンアップ
cleanup_temp_file() {
    [ -f "$TEST_TEMP_FILE" ] && rm -f "$TEST_TEMP_FILE"
    return 0
}

# 共通の設定キャッシュをセットアップ
setup_default_profile_cache() {
    declare -gA PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://auth.example.com/oauth/token"
        [client_id]="test-client-id"
        [client_secret]="test-client-secret"
        [scopes]="read write"
    )
}

# ユーザーエージェントを含むデフォルト設定キャッシュ
setup_default_profile_cache_with_user_agent() {
    declare -gA PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://auth.example.com/oauth/token"
        [client_id]="test-client-id"
        [client_secret]="test-client-secret"
        [scopes]="read write"
        [default_user_agent]="TestAgent/1.0"
    )
}

# ユーザーエージェントのみの設定キャッシュ
setup_profile_cache_with_user_agent() {
    declare -gA PROFILE_CACHE=(
        [default_user_agent]="TestAgent/1.0"
    )
}
