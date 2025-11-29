#!/usr/bin/env bats

load test_helper

teardown() {
    cleanup_temp_file
}

@test "http::request 正常系：基本的なHTTPパラメータを確認する" {
    setup_profile_cache_with_user_agent

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    # 基本的なGETリクエスト
    http::request "https://api.example.com/users" "test-token-123" "GET" "" > /dev/null

    # 1. サイレントモード用の-sオプション
    grep -q "^-s$" "$curl_args_file"

    # 2. HTTPメソッド
    grep -A1 "^-X$" "$curl_args_file" | grep -q "^GET$"

    # 3. Authorizationヘッダ
    grep -q "Authorization: Bearer test-token-123" "$curl_args_file"

    # 4. Content-Typeヘッダ
    grep -q "Content-Type: application/json" "$curl_args_file"

    # 5. User-Agentヘッダ
    grep -q "User-Agent: TestAgent/1.0" "$curl_args_file"

    # 6. URLを含める
    grep -q "https://api.example.com/users" "$curl_args_file"

    unset -f curl

    # 7. POSTデータを含める（別のリクエスト）
    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    http::request "https://api.example.com/users" "test-token-123" "POST" '{"name":"test"}' > /dev/null

    grep -q '{"name":"test"}' "$curl_args_file"

    unset -f curl
}

@test "http::request カスタムヘッダを含める" {
    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    declare -A PROFILE_CACHE=(
        [default_user_agent]="TestAgent/1.0"
    )

    http::request "https://api.example.com/users" "test-token-123" "POST" '{"name":"test"}' -H "X-Custom: value" > /dev/null

    grep -q "X-Custom: value" "$curl_args_file"

    unset -f curl
}

@test "http::request 詳細モード用の-vオプションを渡す" {
    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    declare -A PROFILE_CACHE=(
        [default_user_agent]="TestAgent/1.0"
    )

    http::request "https://api.example.com/users" "test-token-123" "POST" '{"name":"test"}' -v > /dev/null

    grep -q "^-v$" "$curl_args_file"

    unset -f curl
}

@test "http::request レスポンスヘッダを含める-iオプションを渡す" {
    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    declare -A PROFILE_CACHE=(
        [default_user_agent]="TestAgent/1.0"
    )

    http::request "https://api.example.com/users" "test-token-123" "POST" '{"name":"test"}' -i > /dev/null

    grep -q "^-i$" "$curl_args_file"

    unset -f curl
}

# Test: Curl options with arguments
@test "http::request Curlオプション：--max-time、--compressed、-Lを渡す" {
    declare -A PROFILE_CACHE=(
        [default_user_agent]="TestAgent/1.0"
    )

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    # 1. --max-timeオプション
    http::request "https://api.example.com/data" "token-abc" "GET" "" --max-time 30 > /dev/null

    grep -A1 "^--max-time$" "$curl_args_file" | grep -q "^30$"

    # 2. --compressedオプション
    http::request "https://api.example.com/data" "token-abc" "GET" "" --compressed > /dev/null

    grep -q "^--compressed$" "$curl_args_file"

    # 3. リダイレクト用の-Lオプション
    http::request "https://api.example.com/data" "token-abc" "GET" "" -L > /dev/null

    grep -q "^-L$" "$curl_args_file"

    unset -f curl
}

@test "http::request ヘッダオーバーライド：Content-TypeとUser-Agentのオーバーライドを許可する" {
    declare -A PROFILE_CACHE=(
        [default_user_agent]="DefaultAgent/1.0"
    )

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    # 1. Content-Typeヘッダのオーバーライド
    http::request "https://api.example.com/data" "token-xyz" "GET" "" -H "Content-Type: text/plain" > /dev/null

    local count
    count=$(grep -c "^Content-Type:" "$curl_args_file" || true)
    [ "$count" -ge 1 ]
    grep -q "Content-Type: text/plain" "$curl_args_file"

    # 2. User-Agentヘッダのオーバーライド
    http::request "https://api.example.com/data" "token-xyz" "GET" "" -H "User-Agent: CustomAgent/2.0" > /dev/null

    count=$(grep -c "^User-Agent:" "$curl_args_file" || true)
    [ "$count" -ge 1 ]
    grep -q "User-Agent: CustomAgent/2.0" "$curl_args_file"

    unset -f curl
}

