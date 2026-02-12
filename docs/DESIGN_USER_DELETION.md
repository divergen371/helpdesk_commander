# ユーザー削除ポリシー設計ノート

## 背景

ユーザーを削除する運用要件がある一方、ユーザーはシステム全体で広く参照されており、
物理削除は監査ログや過去データの整合性を破壊する。
論理削除（soft delete）も UNIQUE 制約の衝突やクエリ漏れ等の典型的な問題を抱える。

## 現状の User FK 参照マップ

```
users.id ──┬── tickets.requester_id        (NOT NULL)
            ├── tickets.assignee_id         (nullable)
            ├── tickets.visibility_decided_by_id (nullable)
            ├── ticket_events.actor_id      (NOT NULL)
            ├── ticket_links.created_by_id  (nullable)
            ├── conversations.created_by_id (nullable)
            ├── conversation_messages.sender_id (NOT NULL)
            ├── inquiries.requester_id      (NOT NULL)
            ├── tasks.assignee_id           (nullable)
            └── task_events.actor_id        (NOT NULL)
```

NOT NULL の参照が 4 箇所あるため、物理削除は FK 制約違反で不可能。
ON DELETE SET NULL にしても監査性が完全に失われる。

## 方針: ステータスベースの無効化 + 遅延匿名化

物理削除（`DELETE FROM users`）は行わない。
`deleted_at` カラムも追加しない（WHERE 漏れリスクを排除）。
既存の `status` カラムに `suspended` と `anonymized` を追加して制御する。

### ステータス遷移

```
pending ──→ active ──→ suspended ──→ anonymized
                 │
                 └──→ suspended（管理者による即時停止も可）
```

- `pending`: 承認待ち（既存）
- `active`: 通常利用（既存）
- `suspended`: 無効化済み。ログイン不可、新規操作不可。過去データは名前付きで閲覧可能
- `anonymized`: 個人情報除去済み。行は残るが個人を特定できない

### Phase 1: 即時無効化（active → suspended）

管理者が `suspend` アクションを実行すると即座に適用。

変更内容:
- `status` を `"suspended"` に設定
- `suspended_at` タイムスタンプを記録（新規カラム）
- `password_hash` を NULL に設定（即時ログイン不可）
- 既存セッションはセッションチェック時に弾く（`ensure_active` が `:inactive` を返す）

影響:
- チケット一覧等での表示名は維持（「山田太郎（無効）」のように表示）
- 担当者に割り当てられている場合はアサイン解除を推奨する警告を表示
- 新規チケットの requester/assignee には選択肢に出さない

### Phase 2: 遅延匿名化（suspended → anonymized）

猶予期間（30 日）経過後に匿名化ジョブを実行。
即時匿名化も管理者操作で可能（確認ダイアログ付き）。

変更内容:
- `email` → `"deleted-{id}@anonymized.local"`
- `display_name` → `"削除済みユーザー"`
- `login_id` → NULL
- `password_hash` → NULL（suspended 時点で NULL のはず）
- `anonymized_at` タイムスタンプを記録（新規カラム）

影響:
- UNIQUE 制約（company_id + email）の衝突が解消される（同じメールで再登録可能）
- 過去データの FK 参照は維持。「削除済みユーザー（ID: 123）」として表示
- 会話ログやイベントの送信者は「削除済みユーザー」表記に統一

### 論理削除の典型デメリットへの対策

WHERE 漏れ:
  `deleted_at` を使わない。`status` で制御するため、既存のフィルタ（`ensure_active`、
  ユーザー選択のクエリ等）と自然に統合される。

UNIQUE 衝突:
  匿名化時に email/login_id を一意な無効値に書き換える。
  suspended 段階では元の email を維持（復帰の余地を残す）。

個人情報保護:
  匿名化で PII を除去。行自体は残すが個人を特定できない。
  GDPR の「忘れられる権利」にも対応可能。

テーブル肥大:
  ユーザーテーブルは通常数千〜数万行程度。実害なし。

## 実装スコープ

### DB変更（マイグレーション）

- `users` に `suspended_at` (`utc_datetime_usec`, nullable) を追加
- `users` に `anonymized_at` (`utc_datetime_usec`, nullable) を追加
- `users.status` の制約は Ash 側で regex/enum として管理（DB 制約は追加しない）

### Ash リソース変更（user.ex）

- `suspended_at`, `anonymized_at` 属性を追加
- `suspend` アクション: status→suspended, password_hash→nil, suspended_at を記録
- `anonymize` アクション: PII 書き換え、status→anonymized, anonymized_at を記録
- `defaults` から `:destroy` を除去（物理削除の禁止）
- `status` の制約を `~r/^(pending|active|suspended|anonymized)$/` に変更

### 認証・セッション（auth.ex / current_user.ex）

- `ensure_active` に `suspended` / `anonymized` の明示的なハンドリングを追加
- ユーザー選択クエリで `status == "active"` のフィルタを追加

### UI 表示

- suspended ユーザーの表示名に「（無効）」を付与するヘルパー
- anonymized ユーザーは「削除済みユーザー」固定表示
- ユーザー選択ドロップダウンから suspended/anonymized を除外

### Oban ジョブ（将来）

- `AnonymizeExpiredUsersWorker`: 30日経過した suspended ユーザーを自動匿名化
- Oban Cron プラグインで日次実行（03:00 UTC）
- 管理者の手動匿名化も可能（`anonymize` アクションを直接呼び出し）

## 対象外（この設計では扱わない）

- 会社（Company）の削除: 別途検討が必要（所属ユーザー全員の処理が必要）
- ユーザーデータのエクスポート（GDPR ポータビリティ権）: 将来要件
- 匿名化の取り消し: 不可逆とする（復帰は新規作成で対応）
