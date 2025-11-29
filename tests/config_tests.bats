#!/usr/bin/env bats

load test_helper

teardown() {
    cleanup_temp_file
}

@test "config::extract_profiles 2つのプロファイルを抽出する" {
    local test_profile="[env1]
key1 = value1

[env2]
key2 = value2"

    config::extract_profiles "$test_profile"

    [ "${#AVAILABLE_PROFILES[@]}" -eq 2 ]
    [ "${AVAILABLE_PROFILES[0]}" = "env1" ]
    [ "${AVAILABLE_PROFILES[1]}" = "env2" ]
}

@test "config::extract_profiles 様々なキーを持つ複数のプロファイルを抽出する" {
    local test_profile="[production]
auth_server_token_endpoint = https://prod.example.com

[staging]
auth_server_token_endpoint = https://stg.example.com

[development]
auth_server_token_endpoint = https://dev.example.com"

    config::extract_profiles "$test_profile"

    [ "${#AVAILABLE_PROFILES[@]}" -eq 3 ]
    [ "${AVAILABLE_PROFILES[0]}" = "production" ]
    [ "${AVAILABLE_PROFILES[1]}" = "staging" ]
    [ "${AVAILABLE_PROFILES[2]}" = "development" ]
}

@test "config::parse_profile test-envを正しく解析する" {
    # Initialize PROFILE_CACHE globally for the function to use
    eval "unset PROFILE_CACHE; declare -gA PROFILE_CACHE"

    local test_profile="[production]
auth_server_token_endpoint = https://prod.example.com/token
client_id = prod-client
client_secret = prod-secret
scopes = admin
default_content_type = application/xml

[test-env]
auth_server_token_endpoint = https://example.com/token
client_id = test-client
client_secret = test-secret
scopes = read write
default_content_type = application/json

[development]
auth_server_token_endpoint = https://dev.example.com/token
client_id = dev-client
client_secret = dev-secret
scopes = read"

    config::parse_profile "$test_profile" "test-env"

    [ "${PROFILE_CACHE[auth_server_token_endpoint]}" = "https://example.com/token" ]
    [ "${PROFILE_CACHE[client_id]}" = "test-client" ]
    [ "${PROFILE_CACHE[client_secret]}" = "test-secret" ]
    [ "${PROFILE_CACHE[scopes]}" = "read write" ]
    [ "${PROFILE_CACHE[default_content_type]}" = "application/json" ]
}

@test "config::parse_profile 値のスペースを正しく処理する" {
    # Initialize PROFILE_CACHE globally for the function to use
    eval "unset PROFILE_CACHE; declare -gA PROFILE_CACHE"

    local test_profile="[test]
scopes = read write admin
description = test environment with spaces"

    config::parse_profile "$test_profile" "test"

    [ "${PROFILE_CACHE[scopes]}" = "read write admin" ]
    [ "${PROFILE_CACHE[description]}" = "test environment with spaces" ]
}

@test "config::validate 完全な設定で成功する" {
    declare -A PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://example.com/token"
        [client_id]="test-client"
        [client_secret]="test-secret"
        [scopes]="read"
    )

    config::validate
}

@test "config::validate 不完全な設定で失敗する" {
    declare -A PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://example.com/token"
        [client_id]="test-client"
    )

    # 関数実行時にエラーが発生することを確認
    run config::validate
    [ "$status" -ne 0 ]
}

@test "config::validate 空のscopesで成功する" {
    declare -A PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://example.com/token"
        [client_id]="test-client"
        [client_secret]="test-secret"
        [scopes]=""
    )

    config::validate
}

@test "config::validate auth_server_token_endpointがない場合失敗する" {
    declare -A PROFILE_CACHE=(
        [client_id]="test-client"
        [client_secret]="test-secret"
        [scopes]="read"
    )

    # 関数実行時にエラーが発生することを確認
    run config::validate
    [ "$status" -ne 0 ]
}

@test "config::validate client_idがない場合失敗する" {
    declare -A PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://example.com/token"
        [client_secret]="test-secret"
        [scopes]="read"
    )

    # 関数実行時にエラーが発生することを確認
    run config::validate
    [ "$status" -ne 0 ]
}

@test "config::validate client_secretがない場合失敗する" {
    declare -A PROFILE_CACHE=(
        [auth_server_token_endpoint]="https://example.com/token"
        [client_id]="test-client"
        [scopes]="read"
    )

    # 関数実行時にエラーが発生することを確認
    run config::validate
    [ "$status" -ne 0 ]
}

@test "config::list_profiles 利用可能なプロファイルを表示する" {
    # Mock the op command
    op() {
        if [[ "$2" == "get" ]]; then
            echo "[production]
auth_server_token_endpoint = https://prod.example.com
[staging]
auth_server_token_endpoint = https://stg.example.com
[development]
auth_server_token_endpoint = https://dev.example.com"
        fi
    }
    export -f op

    local test_output
    test_output=$(config::list_profiles "test-item" "" 2>&1)

    [[ "$test_output" =~ "利用可能なプロファイル:" ]]
    [[ "$test_output" =~ "production" ]]
    [[ "$test_output" =~ "staging" ]]
    [[ "$test_output" =~ "development" ]]

    unset -f op
}

@test "config::list_profiles Vault名を指定してプロファイルを表示する" {
    # Mock the op command
    op() {
        # vault引数が正しく渡されているか確認
        local has_vault=false
        for arg in "$@"; do
            if [[ "$arg" == "--vault" ]]; then
                has_vault=true
                break
            fi
        done

        if [[ "$2" == "get" && "$has_vault" == true ]]; then
            echo "[production]
auth_server_token_endpoint = https://prod.example.com"
        fi
    }
    export -f op

    local test_output
    test_output=$(config::list_profiles "test-item" "MyVault" 2>&1)

    [[ "$test_output" =~ "利用可能なプロファイル:" ]]
    [[ "$test_output" =~ "production" ]]

    unset -f op
}
