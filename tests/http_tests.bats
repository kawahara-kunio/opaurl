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

# curlは同名の-Hを後勝ちで上書きせず両方送るため、
# オーバーライド時はカスタムヘッダが「ちょうど1つだけ」渡ることを確認する
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
    [ "$count" -eq 1 ]
    grep -q "Content-Type: text/plain" "$curl_args_file"

    # 2. User-Agentヘッダのオーバーライド
    http::request "https://api.example.com/data" "token-xyz" "GET" "" -H "User-Agent: CustomAgent/2.0" > /dev/null

    count=$(grep -c "^User-Agent:" "$curl_args_file" || true)
    [ "$count" -eq 1 ]
    grep -q "User-Agent: CustomAgent/2.0" "$curl_args_file"

    unset -f curl
}

# ヘッダ名は大文字小文字を区別せず、前後の空白やcurlの「名前;」記法でも
# デフォルトヘッダを積まないことを確認する
@test "http::request ヘッダオーバーライド：表記ゆれがあってもデフォルトのContent-Typeを送らない" {
    declare -A PROFILE_CACHE=(
        [default_user_agent]="DefaultAgent/1.0"
    )

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    local count

    # 1. ヘッダ名が小文字
    http::request "https://api.example.com/data" "token-xyz" "PATCH" '{"a":1}' -H "content-type: application/merge-patch+json" > /dev/null

    grep -q "content-type: application/merge-patch+json" "$curl_args_file"
    count=$(grep -c "^Content-Type: application/json$" "$curl_args_file" || true)
    [ "$count" -eq 0 ]

    # 2. ヘッダ名の前後に空白
    http::request "https://api.example.com/data" "token-xyz" "PATCH" '{"a":1}' -H "  Content-Type  : application/merge-patch+json" > /dev/null

    grep -q "Content-Type  : application/merge-patch+json" "$curl_args_file"
    count=$(grep -c "^Content-Type: application/json$" "$curl_args_file" || true)
    [ "$count" -eq 0 ]

    # 3. curlの「名前;」記法（値が空のヘッダを送る）
    http::request "https://api.example.com/data" "token-xyz" "PATCH" '{"a":1}' -H "Content-Type;" > /dev/null

    grep -q "Content-Type;" "$curl_args_file"
    count=$(grep -c "^Content-Type: application/json$" "$curl_args_file" || true)
    [ "$count" -eq 0 ]

    unset -f curl
}

@test "http::request ヘッダオーバーライド：Authorizationをオーバーライドできる" {
    declare -A PROFILE_CACHE=(
        [default_user_agent]="DefaultAgent/1.0"
    )

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    http::request "https://api.example.com/data" "token-xyz" "GET" "" -H "Authorization: Basic dXNlcjpwYXNz" > /dev/null

    local count
    count=$(grep -c "^Authorization:" "$curl_args_file" || true)
    [ "$count" -eq 1 ]
    grep -q "Authorization: Basic dXNlcjpwYXNz" "$curl_args_file"
    count=$(grep -c "^Authorization: Bearer token-xyz$" "$curl_args_file" || true)
    [ "$count" -eq 0 ]

    unset -f curl
}

@test "http::request ヘッダオーバーライド：無関係なカスタムヘッダはデフォルトヘッダを残す" {
    declare -A PROFILE_CACHE=(
        [default_user_agent]="DefaultAgent/1.0"
    )

    local curl_args_file=$(get_temp_file)

    curl() {
        printf '%s\n' "$@" > "$curl_args_file"
        echo '{"result":"ok"}'
    }
    export -f curl

    http::request "https://api.example.com/data" "token-xyz" "GET" "" -H "X-Request-Id: abc123" > /dev/null

    grep -q "X-Request-Id: abc123" "$curl_args_file"
    grep -q "Authorization: Bearer token-xyz" "$curl_args_file"
    grep -q "Content-Type: application/json" "$curl_args_file"
    grep -q "User-Agent: DefaultAgent/1.0" "$curl_args_file"

    unset -f curl
}

