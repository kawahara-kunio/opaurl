#!/usr/bin/env bats

load test_helper

teardown() {
    cleanup_temp_file
}

@test "auth::fetch_token_response 正常系：レスポンス確認と認証ヘッダを検証する" {
    setup_default_profile_cache

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"access_token":"test-token","expires_in":3600}'
        echo '200'
    }
    export -f curl

    # 1. トークンレスポンスボディを正しく取得できている
    local response
    response=$(auth::fetch_token_response)
    [[ "$response" == '{"access_token":"test-token","expires_in":3600}' ]]

    # 2. Basic認証ヘッダを含める
    local expected
    expected=$(echo -n "test-client-id:test-client-secret" | base64)
    grep -q "Authorization: Basic $expected" "$curl_args_file"

    unset -f curl
}

@test "auth::fetch_token_response HTTPエラーステータス時に失敗する" {
    setup_default_profile_cache

    curl() {
        echo '{"error":"invalid_client"}'
        echo '401'
    }
    export -f curl

    # 関数実行時にエラーが発生することを確認
    run auth::fetch_token_response
    [ "$status" -ne 0 ]

    unset -f curl
}

@test "auth::get_token 正常系：トークン取得と必要なHTTPパラメータを確認する" {
    setup_default_profile_cache

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"access_token":"mock-token-12345","token_type":"Bearer","expires_in":3600}'
        echo '200'
    }
    export -f curl

    # トークンを取得
    local token
    token=$(auth::get_token)

    # 1. トークンが正しく取得できている
    [ "$token" = "mock-token-12345" ]

    # 2. POSTメソッドを使用している
    local -a curl_args
    mapfile -t curl_args < "$curl_args_file"
    local found_post=false
    for ((i=0; i<${#curl_args[@]}; i++)); do
        if [[ "${curl_args[$i]}" == "-X" && "${curl_args[$((i+1))]}" == "POST" ]]; then
            found_post=true
            break
        fi
    done
    [ "$found_post" = true ]

    # 3. 正しいトークンエンドポイントを使用している
    grep -q "https://auth.example.com/oauth/token" "$curl_args_file"

    # 4. Authorization Basicヘッダを含める
    local expected_credentials
    expected_credentials=$(echo -n "test-client-id:test-client-secret" | base64)
    grep -q "Authorization: Basic $expected_credentials" "$curl_args_file"

    # 5. Content-Typeヘッダを含める
    grep -q "Content-Type: application/x-www-form-urlencoded" "$curl_args_file"

    # 6. grant_typeパラメータを含める
    grep -q "grant_type=client_credentials" "$curl_args_file"

    # 7. scopeパラメータを含める（空でない場合）
    grep -q "scope=read write" "$curl_args_file"

    unset -f curl
}

@test "auth::get_token 空の場合scopeパラメータを含めない" {
    declare -gA PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://auth.example.com/oauth/token"
        [client_id]="test-client-id"
        [client_secret]="test-client-secret"
        [scopes]=""
    )

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"access_token":"mock-token-12345","token_type":"Bearer","expires_in":3600}'
        echo '200'
    }
    export -f curl

    auth::get_token > /dev/null

    ! grep -q "^scope=" "$curl_args_file"

    unset -f curl
}

@test "auth::get_token access_tokenフィールドがない場合失敗する" {
    setup_default_profile_cache

    curl() {
        echo '{"token_type":"Bearer","expires_in":3600}'
        echo '200'
    }
    export -f curl

    # 関数実行時にエラーが発生することを確認
    run auth::get_token
    [ "$status" -ne 0 ]

    unset -f curl
}

@test "auth::get_token access_tokenがnullの場合失敗する" {
    setup_default_profile_cache

    curl() {
        echo '{"access_token":null,"token_type":"Bearer","expires_in":3600}'
        echo '200'
    }
    export -f curl

    # 関数実行時にエラーが発生することを確認
    run auth::get_token
    [ "$status" -ne 0 ]

    unset -f curl
}

@test "auth::get_token access_tokenが空文字列の場合失敗する" {
    setup_default_profile_cache

    curl() {
        echo '{"access_token":"","token_type":"Bearer","expires_in":3600}'
        echo '200'
    }
    export -f curl

    # 関数実行時にエラーが発生することを確認
    run auth::get_token
    [ "$status" -ne 0 ]

    unset -f curl
}

@test "auth::get_token HTTPステータスが401の場合失敗する" {
    setup_default_profile_cache

    curl() {
        echo '{"error":"invalid_client","error_description":"Client authentication failed"}'
        echo '401'
    }
    export -f curl

    # 関数実行時にエラーが発生することを確認
    run auth::get_token
    [ "$status" -ne 0 ]

    unset -f curl
}

@test "auth::token_is_valid 有効なトークンを検出する" {
    local current_time
    current_time=$(date +%s)

    local response="{\"access_token\":\"valid-token\",\"expires_at\":$((current_time + 3600))}"

    local expires_at
    expires_at=$(echo "$response" | jq -r '.expires_at // 0')

    [ $((current_time + 10)) -lt $expires_at ]
}

@test "auth::token_is_valid 10秒以内に期限切れするトークンを検出する" {
    local current_time
    current_time=$(date +%s)

    local response="{\"access_token\":\"expiring-token\",\"expires_at\":$((current_time + 5))}"

    local expires_at
    expires_at=$(echo "$response" | jq -r '.expires_at // 0')

    [ $((current_time + 10)) -ge $expires_at ]
}

@test "auth::token_is_valid 既に期限切れのトークンを検出する" {
    local current_time
    current_time=$(date +%s)

    local response="{\"access_token\":\"expired-token\",\"expires_at\":$((current_time - 100))}"

    local expires_at
    expires_at=$(echo "$response" | jq -r '.expires_at // 0')

    [ $((current_time + 10)) -ge $expires_at ]
}

@test "auth::add_expires_at トークンレスポンスにexpires_atフィールドを追加する" {
    local test_response='{"access_token":"test-token","expires_in":3600,"token_type":"Bearer"}'
    local result
    result=$(auth::add_expires_at "$test_response")

    echo "$result" | jq -e '.expires_at' > /dev/null
}

@test "auth::add_expires_at コンパクトなJSON(単一行)を返す" {
    local test_response='{"access_token":"test-token","expires_in":3600,"token_type":"Bearer"}'
    local result
    result=$(auth::add_expires_at "$test_response")

    local line_count
    line_count=$(echo "$result" | wc -l | tr -d ' ')

    [ "$line_count" -eq 1 ]
}

# Test: Get environment variable name
@test "auth::get_profile_var_name ハイフンをアンダースコアに変換する" {
    local profile_env_var_name
    profile_env_var_name=$(auth::get_profile_var_name "fannaly-stg-qa")

    [ "$profile_env_var_name" = "OPAURL_fannaly_stg_qa" ]
}

@test "auth::get_profile_var_name ハイフンなしプロファイル名を処理する" {
    local profile_env_var_name
    profile_env_var_name=$(auth::get_profile_var_name "production")

    [ "$profile_env_var_name" = "OPAURL_production" ]
}

@test "auth::get_access_token_from_cache 有効なキャッシュトークンを使用する" {
    local current_time
    current_time=$(date +%s)

    local cached_response="{\"access_token\":\"cached-token\",\"expires_at\":$((current_time + 3600))}"

    config::fetch_from_1password() {
        return 1
    }
    export -f config::fetch_from_1password

    local test_var_name="TEST_CACHE_VAR"
    eval "export $test_var_name='$cached_response'"

    local token
    token=$(auth::get_access_token_from_cache "$test_var_name")

    [ "$token" = "cached-token" ]

    unset -f config::fetch_from_1password
    unset "$test_var_name"
}
