#!/usr/bin/env bats

load test_helper

teardown() {
    cleanup_temp_file
}

# Test: CLI argument validation
@test "main -pオプションが指定されていない場合エラーを表示する" {
    run main https://api.example.com
    [ "$status" -ne 0 ]
    [[ "$output" == *"プロファイル名が必要です"* ]]
}

@test "main --list-profilesでプロファイルリストを出力する" {
    op() {
        if [[ "$2" == "get" ]]; then
            echo "[production]
auth_server_token_endpoint=https://prod.example.com
[staging]
auth_server_token_endpoint=https://stg.example.com"
        fi
    }
    export -f op

    run main --list-profiles
    [ "$status" -eq 0 ]
    [[ "$output" == *"production"* ]]
    [[ "$output" == *"staging"* ]]

    unset -f op
}

@test "main -hオプションでヘルプを表示する" {
    run main -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "main 正常系：プロファイルを指定してAPIリクエストを実行する" {
    # Initialize PROFILE_CACHE
    eval "unset PROFILE_CACHE; declare -gA PROFILE_CACHE"

    config::fetch_from_1password() {
        echo "[development]
auth_server_token_endpoint=https://auth.example.com/oauth/token
client_id=dev-client
client_secret=dev-secret
scopes=read
default_user_agent=TestAgent/1.0

[production]
auth_server_token_endpoint=https://auth.example.com/oauth/token
client_id=prod-client
client_secret=prod-secret
scopes=read write
default_user_agent=TestAgent/1.0"
    }
    export -f config::fetch_from_1password

    curl() {
        # 引数を確認して、URL に基づいて異なるレスポンスを返す
        local url=""
        for arg in "$@"; do
            # https:// で始まるURLを探す
            if [[ "$arg" =~ ^https?:// ]]; then
                url="$arg"
                break
            fi
        done

        case "$url" in
            # Token endpoint request
            *oauth/token*)
                echo '{"access_token":"test-token-123","token_type":"Bearer","expires_in":3600}'
                echo '200'
                ;;
            # API request
            *)
                echo '{"result":"success","data":"test"}'
                echo '200'
                ;;
        esac
    }
    export -f curl

    # Execute main with environment and API endpoint
    run main -p production https://api.example.com/users

    [ "$status" -eq 0 ]
    [[ "$output" == *"result"* ]] || [[ "$output" == *"success"* ]]

    unset -f config::fetch_from_1password
    unset -f curl
}

@test "main 正常系：キャッシュトークンを使用する" {
    # PROFILE_CACHEを初期化
    eval "unset PROFILE_CACHE; declare -gA PROFILE_CACHE"
    local curl_args_file_1=$(get_temp_file).cache_test_1
    local curl_args_file_2=$(get_temp_file).cache_test_2
    local curl_args_file_3=$(get_temp_file).cache_test_3
    local token_call_counter=$(get_temp_file).cache_counter
    local op_call_counter=$(get_temp_file).op_counter

    # 前回のテストファイルをクリーンアップして初期化
    rm -f "$curl_args_file_1" "$curl_args_file_2" "$curl_args_file_3"
    echo "0" > "$token_call_counter"
    echo "0" > "$op_call_counter"

    config::fetch_from_1password() {
        # 1Password呼び出しをカウント
        local count=$(cat "$op_call_counter")
        count=$((count + 1))
        echo "$count" > "$op_call_counter"

        echo "[staging]
auth_server_token_endpoint=https://auth.example.com/oauth/token
client_id=stg-client
client_secret=stg-secret
scopes=read
default_content_type=application/xml
default_user_agent=TestAgent/1.0"
    }
    export -f config::fetch_from_1password
    export op_call_counter

    curl() {
        # 引数を確認して、URLに基づいて異なるレスポンスを返す
        local url=""
        for arg in "$@"; do
            if [[ "$arg" =~ ^https?:// ]]; then
                url="$arg"
                break
            fi
        done

        case "$url" in
            # トークンエンドポイントへのリクエスト
            *oauth/token*)
                local count=$(cat "$token_call_counter")
                count=$((count + 1))
                echo "$count" > "$token_call_counter"
                echo '{"access_token":"cached-token-456","token_type":"Bearer","expires_in":3600}'
                echo '200'
                ;;
            # APIリクエスト - 引数をファイルに保存
            *)
                # ファイルの存在確認で何回目のAPIコールかを判定
                if [ ! -f "$curl_args_file_1" ] || [ ! -s "$curl_args_file_1" ]; then
                    # 1回目のAPIコール（トークン取得後）
                    printf '%s\n' "$@" > "$curl_args_file_1"
                elif [ ! -f "$curl_args_file_2" ] || [ ! -s "$curl_args_file_2" ]; then
                    # 2回目のAPIコール（キャッシュから）
                    printf '%s\n' "$@" > "$curl_args_file_2"
                else
                    # 3回目のAPIコール（キャッシュから、カスタムヘッダー付き）
                    printf '%s\n' "$@" > "$curl_args_file_3"
                fi
                echo '{"cached":true}'
                echo '200'
                ;;
        esac
    }
    export -f curl
    export curl_args_file_1
    export curl_args_file_2
    export curl_args_file_3
    export token_call_counter

    # 1回目のリクエスト - トークンエンドポイントから取得
    run main -p staging https://api.example.com/data
    [ "$status" -eq 0 ]
    local first_token_calls=$(cat "$token_call_counter")
    local first_op_calls=$(cat "$op_call_counter")

    # 1回目のリクエストで1Passwordが呼ばれることを検証
    [ "$first_op_calls" -eq 1 ]

    # 1回目のリクエストがPROFILE_CACHEから正しいヘッダーを使用することを検証
    [ -f "$curl_args_file_1" ]
    grep -q "Content-Type: application/xml" "$curl_args_file_1"
    grep -q "User-Agent: TestAgent/1.0" "$curl_args_file_1"

    # キャッシュ用にトークンを抽出してエクスポート
    # main関数はOPAURL_stagingにトークンを設定するはずだが、
    # runがサブシェルを作成するため、テスト内で手動設定が必要
    export OPAURL_staging='{"access_token":"cached-token-456","token_type":"Bearer","expires_in":3600,"expires_at":'$(($(date +%s) + 3600))',"default_content_type":"application/xml","default_user_agent":"TestAgent/1.0"}'

    # 2回目のリクエスト - キャッシュされたトークンを使用（トークンエンドポイントも1Passwordも呼ばない）
    run main -p staging https://api.example.com/data
    [ "$status" -eq 0 ]

    # 2回目のリクエストでトークンエンドポイントが呼ばれていないことを検証
    [ "$(cat "$token_call_counter")" -eq "$first_token_calls" ]

    # 2回目のリクエストで1Passwordが呼ばれていないことを検証（キャッシュヒット）
    [ "$(cat "$op_call_counter")" -eq "$first_op_calls" ]

    # 2回目のリクエストもキャッシュから取得した設定で正しいヘッダーを使用することを検証
    [ -f "$curl_args_file_2" ]
    grep -q "Content-Type: application/xml" "$curl_args_file_2"
    grep -q "User-Agent: TestAgent/1.0" "$curl_args_file_2"

    # 3回目のリクエスト - カスタムヘッダーを指定してリクエストの値が優先されることを検証
    run main -p staging -H "Content-Type: application/json" -H "User-Agent: CustomAgent/2.0" https://api.example.com/data
    [ "$status" -eq 0 ]

    # 3回目のリクエストでトークンエンドポイントが呼ばれていないことを検証
    [ "$(cat "$token_call_counter")" -eq "$first_token_calls" ]

    # 3回目のリクエストでも1Passwordが呼ばれていないことを検証（キャッシュヒット）
    [ "$(cat "$op_call_counter")" -eq "$first_op_calls" ]

    # 3回目のリクエストでカスタムヘッダーが使用されていることを検証
    [ -f "$curl_args_file_3" ]
    grep -q "Content-Type: application/json" "$curl_args_file_3"
    grep -q "User-Agent: CustomAgent/2.0" "$curl_args_file_3"

    # クリーンアップ
    rm -f "$curl_args_file_1" "$curl_args_file_2" "$curl_args_file_3" "$token_call_counter" "$op_call_counter"

    unset -f config::fetch_from_1password
    unset -f curl
}
