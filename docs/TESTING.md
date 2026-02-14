# テスト戦略・実行ガイド

このドキュメントは、本プロジェクトのテスト体系（通常テスト + PropCheck）と、PBTの網羅範囲をまとめたものです。

## テストの構成

- ExUnit（通常のユニット/統合テスト）
- PropCheck（PBT）
  - ネガティブテスト
  - Stateful Property（StateM）
  - FSM Property（Finite State Machine）

## 実行コマンド

### 全体

```bash
mix test
mix precommit
```

### PBTのみ（主要）

```bash
mix test \
  test/helpdesk_commander/support/public_id_propcheck_test.exs \
  test/helpdesk_commander/accounts/user_state_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_status_fsm_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_status_negative_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_verification_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_authorization_propcheck_test.exs \
  test/helpdesk_commander/helpdesk/ticket_notification_propcheck_test.exs \
  --seed 0
```

### 補助

```bash
# PropCheck反例キャッシュのクリア（必要時）
MIX_ENV=test mix propcheck.clean
```

## PBT詳細（現行実装）

`numtests` 未指定のプロパティは PropEr/PropCheck のデフォルトで 100 サンプル実行されます。

### 1) PublicId（`test/helpdesk_commander/support/public_id_propcheck_test.exs`）

- `public_id generator property`
  - 生成器: `half in 1..32`（理論32パターン）
  - サンプル数: 100
  - 検証: 偶数長・hex文字列
- `public_id rejects odd lengths`
  - 生成器: `half in 0..32`（理論33パターン）
  - サンプル数: 100
  - 検証: 奇数長で `ArgumentError`
- `public_id rejects non-positive lengths`
  - 生成器: `len in -32..0`（理論33パターン）
  - サンプル数: 100
  - 検証: 非正数で `FunctionClauseError`

### 2) ユーザー状態遷移 StateM（`test/helpdesk_commander/accounts/user_state_propcheck_test.exs`）

- `user lifecycle follows the state model`
  - サンプル数: `numtests: 20`
  - サイズ: `max_size: 15`
  - 検証対象:
    - `create_user`
    - `suspend_user`
    - `anonymize_user`
  - 不変条件:
    - `suspend` 後の `status/password_hash/suspended_at`
    - `anonymize` 後の `status/email/display_name/login_id/password_hash/anonymized_at`

### 3) チケット状態遷移 FSM（`test/helpdesk_commander/helpdesk/ticket_status_fsm_propcheck_test.exs`）

- `ticket status transitions follow FSM`
  - サンプル数: `numtests: 15`
  - サイズ: `max_size: 20`
  - 検証対象:
    - `new -> triage/in_progress/waiting/resolved`
    - `triage -> in_progress/waiting/resolved`
    - `in_progress -> waiting/resolved`
    - `waiting -> in_progress/resolved`
    - `resolved -> in_progress/waiting/verified/closed`
  - 不変条件:
    - 遷移先ステータス一致
    - `first_response_at/resolved_at/verified_at/closed_at` の整合
  - 運用設定:
    - `store_counter_example: false`（反例を保存しない）
    - 失敗時は `when_fail` で履歴を出力（失敗自体は握りつぶさない）

### 4) チケット遷移のネガティブ/ポジティブ（`test/helpdesk_commander/helpdesk/ticket_status_negative_propcheck_test.exs`）

- `invalid status transitions are rejected`
  - 生成器: `@invalid_transition_pairs`（理論27組）
  - サンプル数: `numtests: 20`
  - 検証: 無効遷移で `{:error, _}`
- `valid status transitions are accepted`
  - 生成器: `@valid_transition_pairs`（理論15組）
  - サンプル数: `numtests: 20`
  - 検証: 有効遷移で `{:ok, updated}` + `updated.status == to`
  - 役割別 actor:
    - `verified/closed` は admin
    - その他は user

### 5) 検証フロー（`test/helpdesk_commander/helpdesk/ticket_verification_propcheck_test.exs`）

- `invalid verification results are rejected`
  - 生成器: `suffix <- utf8()`
  - サンプル数: 100
  - 検証: 無効 result を拒否
- `valid verification results set verified_at`
  - 生成器: `result in [passed, failed, needs_review]`
  - サンプル数: 100
  - 検証: 正常作成 + `verified_at` 付与
- `verification is rejected before resolved status`
  - 生成器: `status in [new, triage, in_progress, waiting, verified, closed]`（理論6組）
  - サンプル数: `numtests: 10`
  - 検証: `resolved` 以外では作成拒否

### 6) 権限制約（`test/helpdesk_commander/helpdesk/ticket_authorization_propcheck_test.exs`）

- `non-privileged users cannot set verified/closed`
  - 生成器: `role in [user, system]` × `target in [verified, closed]`（理論4組）
  - サンプル数: 100
  - 検証: 非特権ユーザーの `verified/closed` 遷移拒否

### 7) 通知既読（`test/helpdesk_commander/helpdesk/ticket_notification_propcheck_test.exs`）

- `mark_read sets read_at and is monotonic`
  - 生成器: `times in 1..3`（理論3組）
  - サンプル数: 100
  - 検証: `read_at` が設定され、連続呼び出し時に単調（`eq/gt`）

## 1回実行あたりの目安

- PropCheckプロパティ数: 12
- プロパティ実行サンプル総数（目安）: 約785
  - ただし StateM/FSM は 1 サンプル中に複数コマンドを含むため、実際の遷移検証回数はこれより多くなります。

## 反例と再現性

- 反例を握りつぶす実装（`try/rescue` で true を返す等）は採用していません。
- FSM 以外は反例保存を有効（デフォルト）のままです。
- 再現時は `--seed` を固定し、必要に応じて `mix propcheck.clean` を実行してください。

## CIでの推奨seed運用

PBTの特性上、CIで1つのseedだけを使うより、複数seedを回した方が探索範囲を広げられます。  
最低ラインとして `0, 1, 2` の3seed運用を推奨します。

ローカルでの同等実行例:

```bash
for seed in 0 1 2; do
  mix test \
    test/helpdesk_commander/support/public_id_propcheck_test.exs \
    test/helpdesk_commander/accounts/user_state_propcheck_test.exs \
    test/helpdesk_commander/helpdesk/ticket_status_fsm_propcheck_test.exs \
    test/helpdesk_commander/helpdesk/ticket_status_negative_propcheck_test.exs \
    test/helpdesk_commander/helpdesk/ticket_verification_propcheck_test.exs \
    test/helpdesk_commander/helpdesk/ticket_authorization_propcheck_test.exs \
    test/helpdesk_commander/helpdesk/ticket_notification_propcheck_test.exs \
    --seed "$seed"
done
```

運用目安:

- PR時: `seed = 0,1,2`
- 夜間/定期ジョブ: seed数を増やす（例: `0..9`）
