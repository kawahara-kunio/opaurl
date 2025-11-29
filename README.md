## 概要

`opaurl`は、1Passwordに保存された認証情報を使用してOAuth 2.0アクセストークンを自動取得し、認証が必要なHTTP APIへのリクエストを簡単に実行できるコマンドラインツールです。

### 主な特徴

- **OAuth 2.0 Client Credentials Grant対応**: トークン取得からAPIリクエストまでを自動化
- **1Password統合**: 認証情報を1Passwordで一元管理、安全性を確保
- **トークンキャッシュ**: 環境変数にトークンをキャッシュし、有効期限を自動チェック（期限10秒前に自動再取得）
- **複数プロファイル対応**: 開発・ステージング・本番など、複数のプロファイルを簡単に切り替え
- **curlベース**: 使い慣れたcurlのオプションをそのまま利用可能
- **デバッグモード**: トラブルシューティングに便利な詳細ログ出力

## 前提条件

- bash 4.0以上
- [1Password CLI](https://developer.1password.com/docs/cli) (op コマンド)
- curl
- jq

## インストール

bin/opaurl をパスの通った場所に配置してください。

## 1Passwordの設定

1Password に以下の形式で設定を保存してください：

### 設定手順

1. 1Passwordで新しいアイテムを作成（推奨：Secure Note）
2. アイテム名を `opaurl profiles` とする（環境変数 `OPAURL_ITEM_NAME` で変更可能）
3. notesフィールドにINI形式で環境設定を記載

### 設定フォーマット

```ini
[profile-name-1]
auth_server_token_endpoint = https://your-auth-server.com/oauth/token
client_id = your-client-id
client_secret = your-client-secret
scopes = your-scope
default_content_type = application/json
default_user_agent = opaurl/1.0

[profile-name-2]
auth_server_token_endpoint = https://another-server.com/oauth/token
client_id = another-client-id
client_secret = another-client-secret
scopes = another-scope
default_content_type = application/json
```

#### 設定項目の説明

| 項目                         | 必須 | 説明                               | デフォルト値       |
| ---------------------------- | ---- | ---------------------------------- | ------------------ |
| `auth_server_token_endpoint` | ✓    | トークンエンドポイントのURL        | -                  |
| `client_id`                  | ✓    | クライアントID                     | -                  |
| `client_secret`              | ✓    | クライアントシークレット           | -                  |
| `scopes`                     |      | 要求するスコープ（スペース区切り） | （空）             |
| `default_content_type`       |      | デフォルトのContent-Typeヘッダー   | `application/json` |
| `default_user_agent`         |      | デフォルトのUser-Agentヘッダー     | `opaurl/1.0`       |

### 1Password CLIでアイテムを作成する例

```bash
# 設定ファイルを作成
cat > opaurl_profiles.ini << 'EOF'
[production]
auth_server_token_endpoint = https://auth.example.com/oauth/token
client_id = prod-client-id
client_secret = prod-client-secret
scopes = api:read api:write
EOF

# 1Passwordにアイテムを作成
op item create --category "Secure Note" \
  --title "opaurl profiles" \
  --vault "Employee" \
  "notesPlain=$(cat opaurl_profiles.ini)"
```

## 使用方法

### 基本的な使い方

```bash
# プロファイル一覧を確認
opaurl --list-profiles

# GETリクエスト
opaurl -p production https://api.example.com/users

# POSTリクエスト
opaurl -p production -X POST -d '{"name":"test"}' https://api.example.com/users

# ファイルからリクエストボディを指定
opaurl -p production -X POST -d @request.json https://api.example.com/users

# 標準入力からリクエストボディを指定
echo '{"name":"test"}' | opaurl -p production -X POST -d @- https://api.example.com/users

# カスタムヘッダーを追加
opaurl -p production -H "X-Custom-Header: value" https://api.example.com/data

# デバッグモードで実行
opaurl -p production --debug https://api.example.com/users
```

### オプション一覧

#### opaurl固有のオプション

| オプション              | 説明                                                  |
| ----------------------- | ----------------------------------------------------- |
| `-p, --profile PROFILE` | 使用するプロファイルを指定                            |
| `-X, --request METHOD`  | HTTPメソッド（GET, POST, PUT, PATCH, DELETE）         |
| `-d, --data DATA`       | リクエストボディ（`@`でファイル指定、`@-`で標準入力） |
| `-H, --header HEADER`   | カスタムヘッダー（複数指定可能）                      |
| `--get-token`           | トークンを環境変数形式で出力（eval用）                |
| `--list-profiles`       | 利用可能なプロファイル一覧を表示                      |
| `--debug`               | デバッグモード（詳細ログを出力）                      |
| `-h, --help`            | ヘルプを表示                                          |

#### curlオプションのパススルー

上記以外のオプション（`-v`, `-i`, `--compressed`, `--max-time`等）はcurlに直接渡されます。

```bash
# 詳細表示（リクエスト/レスポンスヘッダーを表示）
opaurl -p production -v https://api.example.com/users

# レスポンスヘッダーを含めて表示
opaurl -p production -i https://api.example.com/users

# タイムアウト設定（30秒）
opaurl -p production --max-time 30 https://api.example.com/users

# 圧縮を有効化
opaurl -p production --compressed https://api.example.com/users
```

### トークンキャッシュ機能

opaurlは環境変数を使ったトークンキャッシュ機能を提供しています。これにより、複数回のAPIコールで1Passwordへのアクセスを最小限に抑えることができます。

#### トークンを環境変数にキャッシュ

```bash
# トークンを取得して環境変数に保存
eval "$(opaurl -p production-qa --get-token)"

# 保存されたトークンを確認（プロファイル名のハイフンはアンダースコアに変換されます）
echo $OPAURL_production_qa | jq

# 出力例:
# {
#   "access_token": "eyJhbGc...",
#   "token_type": "Bearer",
#   "expires_in": 3600,
#   "expires_at": 1764491289,
#   "default_content_type": "application/json",
#   "default_user_agent": "opaurl/1.0"
# }
```

#### キャッシュを使ったAPI呼び出し

```bash
# 一度キャッシュすれば、以降のopaurlコマンドは自動的にキャッシュを使用
# （1Passwordへのアクセスが不要になり、高速化します）
# キャッシュにはトークン情報だけでなく、default_content_typeとdefault_user_agentも含まれます
opaurl -p production https://api.example.com/users
opaurl -p production https://api.example.com/posts
opaurl -p production https://api.example.com/comments
```

**重要**: トークンの有効期限が切れた場合、opaurlは1Passwordから新しいトークンを自動取得しますが、環境変数のキャッシュは**自動更新されません**。キャッシュを更新するには、再度`--get-token`オプションを使用してください。

```bash
# トークンが期限切れになった場合、トークン再取得は行われるがキャッシュは更新されない
opaurl -p production https://api.example.com/users

# キャッシュを更新する場合は、明示的に--get-tokenを実行
eval "$(opaurl -p production --get-token)"
```

#### トークンを他のツールで使用

```bash
# access_tokenを抽出
TOKEN=$(echo $OPAURL_production | jq -r '.access_token')

# curlで直接使用
curl -H "Authorization: Bearer $TOKEN" https://api.example.com/data

# 他のツールで使用
http GET https://api.example.com/data "Authorization: Bearer $TOKEN"
```

#### キャッシュトークンに含まれる情報

- `access_token`: アクセストークン
- `token_type`: トークンタイプ（通常は "Bearer"）
- `expires_in`: 有効期限までの秒数（トークンエンドポイントのレスポンスに含まれる値）
- `expires_at`: 有効期限のUNIXタイムスタンプ（opaurlが自動計算）
- `default_content_type`: デフォルトのContent-Typeヘッダー（1Password設定から取得）
- `default_user_agent`: デフォルトのUser-Agentヘッダー（1Password設定から取得）

#### トークンの有効期限管理

- opaurlは環境変数のキャッシュをチェックし、有効期限まで残り10秒以内の場合は1Passwordから新規トークンを取得
- **注意**: 新規取得したトークンは環境変数のキャッシュには保存されません
- デバッグモード（`--debug`）で有効期限チェックの詳細を確認可能

```bash
# デバッグモードで有効期限チェックの動作を確認
opaurl -p production --debug https://api.example.com/users

# 出力例（有効なキャッシュがある場合）:
# [DEBUG] キャッシュされたトークンは有効です（残り345秒）

# 出力例（キャッシュが期限切れの場合）:
# [DEBUG] キャッシュされたトークンは期限切れまたは期限切れ間近です
# [DEBUG] キャッシュミスのため、1Passwordから設定を取得します
```

### 環境変数

| 環境変数                  | 説明                     | デフォルト値                          |
| ------------------------- | ------------------------ | ------------------------------------- |
| `OPAURL_ITEM_NAME`        | 1Passwordのアイテム名    | `opaurl profiles`                     |
| `OPAURL_VAULT`            | 1PasswordのVault名       | （未設定の場合はすべてのVaultを検索） |
| `OPAURL_{プロファイル名}` | キャッシュされたトークン | -                                     |

#### 環境変数の使用例

```bash
# 特定のVaultを指定してアイテムを検索
export OPAURL_VAULT="Private"
opaurl -p production https://api.example.com/users

# カスタムアイテム名を使用
export OPAURL_ITEM_NAME="my-api-profile"
opaurl -p production https://api.example.com/users

# 両方を組み合わせて使用
export OPAURL_VAULT="Work"
export OPAURL_ITEM_NAME="team-api-profile"
opaurl -p production https://api.example.com/users
```

**注意**: プロファイル名にハイフンが含まれる場合、プロファイル環境変数名(`OPAURL_{プロファイル名}`)ではアンダースコアに変換されます。
例: `my-env` → `OPAURL_my_env`

## 実践的な使用例

### トークンをキャッシュして高速化

```bash
# 朝一番でトークンを取得
eval "$(opaurl -p production --get-token)"

# 以降は1Passwordへのアクセスなしで高速実行
opaurl -p production https://api.example.com/endpoint1
opaurl -p production https://api.example.com/endpoint2
opaurl -p production https://api.example.com/endpoint3

# トークンが期限切れになっても自動的に再取得されます。ただし、キャッシュはされません。
# 再度キャッシュする場合は、--get-tokenオプションを使用してください。
```

### デバッグとトラブルシューティング

```bash
# デバッグモードで詳細なログを確認
opaurl -p production --debug https://api.example.com/users

# レスポンスヘッダーを確認
opaurl -p production -i https://api.example.com/users
```

## トラブルシューティング

### 1Password CLIにサインインできない

```bash
# 1Password CLIのサインイン状態を確認
op whoami

# サインインしていない場合
op signin

# または環境変数を使用
eval $(op signin)
```

### プロファイルが見つからない

```bash
# 利用可能なプロファイルを確認
opaurl --list-profiles

# カスタムアイテム名を使用している場合
export OPAURL_ITEM_NAME="my-custom-profile"
opaurl --list-profiles
```

### トークン取得に失敗する

```bash
# デバッグモードで詳細を確認
opaurl -p production --debug --get-token

# 設定内容を確認（1Password CLIで）
op item get "opaurl profiles" --field notesPlain

# 必須項目が揃っているか確認:
# - auth_server_token_endpoint
# - client_id
# - client_secret
```

### curlオプションが認識されない

```bash
# opaurlのオプションとcurlのオプションを混在させる場合、
# opaurlのオプションを先に指定してください

# 正しい例
opaurl -p production -X POST -d '{"test":"data"}' -v https://api.example.com/users

# 誤った例（-vが-dの値として解釈される可能性）
opaurl -p production -X POST -v -d '{"test":"data"}' https://api.example.com/users
```

## テスト

このプロジェクトでは、[Bats (Bash Automated Testing System)](https://github.com/bats-core/bats-core)を使用してテストを実装しています。

### Batsのインストール

```bash
# Homebrewを使用（macOS/Linux）
brew install bats-core

# または、GitHubから直接インストール
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

### テストの実行

```bash
# すべてのテストを実行
bats tests/*.bats

# 特定のテストファイルのみ実行
bats tests/config_tests.bats

# 詳細表示で実行
bats -t tests/*.bats
```

## セキュリティに関する注意事項

1. **トークンキャッシュ**: 環境変数にトークンがキャッシュされるため、共有端末では使用後にシェルセッションを終了してください
2. **デバッグモード**: デバッグモードではトークンを含む詳細情報がログに出力される可能性があります。本番環境では注意して使用してください
