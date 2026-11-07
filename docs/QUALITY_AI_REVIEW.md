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

## チェックの必須化（GitHub Rulesets）

Pullfrog はチェックを PR に貼るだけで、必須化は GitHub 側で行う。このリポジトリは
Public のため branch protection ではなく **Ruleset** を使う。

2026-11-08 に `protect-main`（id は GitHub 側で管理）を作成済み。設定は次。

| 項目 | 値 |
| --- | --- |
| 対象ブランチ | `refs/heads/main` |
| 必須ステータスチェック | `pullfrog`、`Quality gate summary` |
| 必須レビュー承認数 | 0（Pullfrog の承認機能は無効のため） |
| push 時の承認取り消し | On |
| 帰属不明変更の追加承認 | Off（bot の PR で詰まらないように） |
| マージ方法 | squash / merge / rebase |

再適用（設定を変えたいとき）は **DELETE してから POST** する。`PATCH /repos/.../rulesets/{id}`
は この環境では 404 を返して使えなかった。

```bash
# 現状確認
gh api repos/divergen371/helpdesk_commander/rulesets --jq '.[] | {id, name}'

# 作り直し
RULESET_ID=$(gh api repos/divergen371/helpdesk_commander/rulesets --jq '.[0].id')
gh api "repos/divergen371/helpdesk_commander/rulesets/$RULESET_ID" --method DELETE
gh api repos/divergen371/helpdesk_commander/rulesets --method POST --input - <<'JSON'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
  "rules": [
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "required_status_checks": [
        {"context": "pullfrog"},
        {"context": "Quality gate summary"}
      ]
    }},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false,
      "require_extra_approval_for_unattributed_changes": false,
      "allowed_merge_methods": ["squash", "merge", "rebase"]
    }}
  ]
}
JSON
```

- `pullfrog` は Pullfrog の実行状態、`Quality gate summary` は CI の全ゲート集約ジョブ
- 必須化したため、**レビューが走る・CI が通るまで main にマージできない**
- 管理者による回避（bypass）は設定していない。緊急時は `gh api ... --method DELETE` で外す

## 検証状況（2026-11-07）

- コンソールでプロバイダ・モデルを設定後、検証 PR #1 でレビューが実行された。
- 1 回目: `mix hex.audit` が advisory 検出で exit 1 になり、allowlist ゲートの前に
  job が落ちる問題を指摘（妥当）。`hex.audit` を情報表示に変更して修正。
- 2 回目: 上記修正を確認し「No new issues」。同時に、CI の `mix precommit` が
  `mix format` の書き込みモードで format ゲートが効かない点を指摘（妥当）。
  `mix format --check-formatted` を CI に追加して修正。
- 3 回目: 修正後の差分を確認し「✅ No new issues found」。
- PR #1 は全 CI ゲートと Pullfrog レビューが成功した状態でマージ済み（710c9ab）。

レビューの指摘は実際の不具合 2 件を検出しており、導入の効果を確認できた。


## コンソール設定（貼り付け用）

以下は Pullfrog コンソールの各欄に貼る想定の文面。設定は Pullfrog 側に保存され、
リポジトリのファイルではない。変更したらこの節も更新する。

> **書くときの制約**: Pullfrog は指示文中のダブルダッシュ語をフラグとして解釈する。
> コマンドラインオプションをそのまま書くと不明なフラグとして怒られるため、
> オプション名は使わず処理の名前で書くこと。

### Review PRs → Custom instructions

```
このリポジトリのレビューでは、以下を重点的に確認してください。

- テナント境界: Ash の company_id / tenant / actor を迂回する読み書きがないか。会社をまたぐ参照、upsert、many_to_many / through の扱い。
- PII: email・会社名・表示名は cloak (AES.GCM) + HMAC hash で扱う。平文保存・ログ出力・外部送信を追加していないか。
- 添付: fail-closed を崩していないか。スキャナ未設定・失敗・タイムアウト・暗号化や上限超過は failed として隔離し、公開しない。ダウンロード可否は clean / skipped のみ。
- migration と Ash リソースの整合: priv/repo/migrations とリソース定義が一致するか。コード生成の差分検証で失敗しないか。
- 認可: 管理者・リーダー限定の操作、外部ユーザーの参照範囲、監査イベントの記録。
- テスト: 新しい分岐や失敗経路（拒否・隔離・タイムアウト・権限）にテストがあるか。テストを弱めて通していないか。
- 依存: 新しい外部依存やバージョン変更は正当化されているか。特に downgrade は理由を確認する。
- 秘密情報: API キー・実データ・本番接続情報がコミットされていないか。

スタイル・整形・命名の指摘は不要です（CI の format / credo が担当）。
指摘は「欠陥か・影響は何か・修正案」をセットで、重要度を付けてください。
```

### Agent → Standing instructions（全 Run 共通）

```
- 変更前後で `mix quality` を実行する（コンパイル警告エラー化 / format / credo strict / test / codegen 差分検証 / dialyzer）。
- カバレッジは `mix quality.coverage` で確認する。基準は 82.0%、絶対下限は 80%。基準を下げない。
- セキュリティは `mix sobelow`、依存は `mix hex.audit` / `mix deps.audit` を確認する。
- 既存の設計・命名・テストの書き方に合わせる。無関係なリファクタや整形を混ぜない。
- 秘密情報・実データをコミットしない。`.env` を読んだり出力したりしない。
- PR は小さく保ち、コミットメッセージは変更の理由が分かるように書く。
- テストを削除・弱体化して通さない。失敗したら原因を直す。
```

### Model → Smart → Custom instructions

```
Deep:
- lib/helpdesk_commander/accounts/**
- lib/helpdesk_commander/attachments/**
- lib/helpdesk_commander/helpdesk/attachments.ex
- lib/helpdesk_commander/authorization.ex
- priv/repo/migrations/**
- 認可・テナント・PII・添付スキャンに関わる差分は、パスにかかわらず常に Deep

Standard:
- その他の lib/**
- test/**

Minimal:
- docs/**
- ルートの *.md（README など）
- backlog/ のタスク・ドキュメント
- .github/workflows/** のコメントや文言のみの変更
```

### Automations → Build → Custom instructions

```
- 実装後は `mix quality` と `mix quality.coverage` を通す。
- 失敗するテストを残さない。テストを弱めて通さない。
- 変更は最小限にし、無関係な整形・リファクタを混ぜない。
- migration が必要なら `mix ash.codegen <name>` で生成し、内容を確認してからコミットする。
- 認可・PII・添付に関わる変更は、影響と検証方法を PR 本文に書く。
```

### 推奨する運用設定

| 設定 | 推奨 | 理由 |
| --- | --- | --- |
| Allow Pullfrog to approve PRs | まず Off のまま | 誤承認のリスクを観察してから有効化する |
| チェックの出力 | コンソールの **Add Pullfrog's run status as a Check on pull requests**（既定 On）。Pullfrog 側はここまで | Pullfrog の実行状態が PR に表示される |
| チェックの必須化 | Pullfrog ではなく GitHub の **Rulesets**（上記のコマンド参照）。Public のため branch protection は使えない | レビュー未完了・CI 失敗のままマージできないようにする |
| Fix CI failures on non-Pullfrog PRs | 当面 Off | AI が人の PR に push する範囲を絞る |
| Auto-merge approved PRs | Off | 実験的機能。まずは人手でマージする |
