# Phoenix セキュリティ静的解析（Sobelow）— HC-37

`mix sobelow` を CI と夜間ジョブで実行し、Phoenix 固有の脆弱性パターン
（XSS・SQL インジェクション・設定漏れ・パストラバーサル等）の回帰を防ぐ。

## 実行

```bash
mix sobelow          # .sobelow-conf を使用（skip: true）
mix sobelow --verbose
```

- 設定: `.sobelow-conf`（`exit: "low"`、`skip: true`）
- CI: `.github/workflows/ci.yml` の precommit job
- 夜間: `.github/workflows/quality-nightly.yml`

## 対応方針

1. `high` / `medium` の指摘は原則修正する。
2. 修正が難しい場合は、影響を確認したうえで関数に `# sobelow_skip ["<check>"]` を付け、
   理由をコメントとこの文書に残す。
3. `low` の指摘は、入力経路を確認して false positive と判断できたものだけ skip する。
4. skip を増やすときは、なぜ安全と言えるかを必ず書く。判断できないものは残す。

## 初回トリアージ（2026-11-07）

| 指摘 | 対応 |
| --- | --- |
| `Config.CSP`（router） | `put_secure_browser_headers` に CSP を追加して修正 |
| `XSS.ContentType`（attachment_controller） | `content_type` はアップロード時に許可リストと照合済み。skip（理由コメント付き） |
| `Traversal.SendFile`（attachment_controller） | パスは Storage の検証済みキーから生成。skip |
| `Traversal.FileModule`（storage / clamd / magic_bytes） | パスは整数 ID・検証済みキー・Plug の一時ファイル。ユーザー入力のファイル名は使わない。skip |
| `CI.System`（command_runner） | コマンドは運用設定（信頼済み）、引数は argv 配列でシェル補間なし。skip |

- CSP の内容: `default-src 'self'`、外部スクリプトと `object` を禁止、LiveView 用に
  `connect-src 'self' ws: wss:` とインラインスタイルを許可。
- skip はすべて関数単位。`--skip` を有効にするため `.sobelow-conf` の `skip: true` が必須。

## 注意

- Sobelow は「テストが通る」ことの代替ではない。動的な検証（テスト・Realtime の認可）と併用する。
- skip の一覧が増えた場合は、この文書の表を更新する。
