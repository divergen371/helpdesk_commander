# AI コードレビュー（Pullfrog）— HC-35

PR のレビュー観点の抜けを補うため、Pullfrog による AI コードレビューを導入する。
2026-11-07 のユーザー判断により、このリポジトリは Public のためコードの外部送信を承認済み。

## 候補比較

| 候補 | 方式 | コスト | 権限・コード送出し | 判定 |
| --- | --- | --- | --- | --- |
| **Pullfrog** | GitHub Actions + BYOK | プラットフォーム無料、モデル課金はコンソール | コードは Actions 上で処理。`AGENTS.md` をレビュー基準にする | **採用** |
| CodeRabbit | SaaS | 無料枠は 1 PR/時間（開発者ごと） | コードを SaaS へ送信 | 不採用（枠不足） |
| GitHub Copilot code review | GitHub 統合 | 有料プラン | GitHub 内 | 不採用（このリポジトリの運用・BYOK と合わない） |
| セルフホスト型 | 自前の LLM | インフラと運用コスト | 外部送信なし | 将来の代替候補 |

採用理由は、レビュー件数枠がなく、GitHub Actions 上で実行が可視化され、`AGENTS.md` を
基準にできる点。secret は GitHub Secrets に置き、リポジトリへはコミットしない。

## 構成

- `.github/workflows/pullfrog.yml` — Pullfrog の公式ワークフロー。
- モデルの課金・購読は [Pullfrog コンソール](https://pullfrog.com/console) で設定する。
- API キーは GitHub の Secrets（例: `DEEPSEEK_API_KEY`）に登録する。

## 導入手順（リポジトリ管理者の作業）

1. Pullfrog コンソールでこのリポジトリを接続し、購読または BYOK を設定する。
2. GitHub の Settings → Secrets and variables → Actions に、利用するプロバイダの
   API キーを追加する（例: `DEEPSEEK_API_KEY`）。
3. 検証用の PR を作成し、Pullfrog のレビューが実行されることを確認する。
4. 指摘が `AGENTS.md` の規約（検証・品質ゲート）に沿っているか確認する。

## 秘密情報・PII の扱い

- リポジトリは Public。秘密情報・実データはコミットしない（`.env` は gitignore 済み）。
- レビュー対象は PR の差分とリポジトリのコードのみ。本番 DB・ログ・添付ファイルは送らない。
- API キーは Secrets のみ。ワークフローに直書きしない。
- 外部送信が許容できない変更（顧客データ等）を扱う場合は、PR を作る前に人間が判断する。

## 検証状況

- ワークフロー YAML の構文確認済み。
- **未検証**: コンソール接続・secret 登録後に検証 PR でレビュー実行を確認する。
  それまでは HC-35 を完了にしない。
