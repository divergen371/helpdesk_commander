# DBスキーマ案（効率・拡張性重視）

本ドキュメントは、Helpdesk Commander のMVP〜将来拡張（Incident、監視/チャット/SSO連携、分析）までを見据えた Postgres テーブル設計案です。

設計の主眼は以下です。
- 競合を減らす：更新が集中する「Ticket本体」を薄くし、履歴/会話は append-only（追記型）に寄せる
- 追跡可能性：重要操作はイベントログ化して監査・ふりかえり・Incidentタイムラインに流用できる
- 検索と性能：一覧に必要な集計/並び替えは Ticket の列＋適切なインデックスで高速化、チャット/イベントはページング前提
- 将来連携：Conversation を抽象化し、外部チャット連携やメールスレッド等にも拡張可能にする

## 共通方針
- 主キー：uuidv7（`uuid_generate_v7()` をデフォルトにし、時系列ソートしやすくする）
- 人間向け番号：`number bigint generated always as identity`（チケット番号/タスク番号）を別で持つ（運用・検索・参照のため）
- 競合検知：更新が起きる行（tickets/tasks/incidents等）に `lock_version int not null default 1` を持たせ、楽観ロックで検知できる余地を作る
- 履歴/会話：可能な限り「新規行追加」で表現（編集は最小限、削除は論理削除/リダクション）

## 1. users（ユーザー）
> AshAuthentication導入後に定義される想定。ここでは参照先として最低限を想定。

- `users`
  - `id uuid pk`
  - `email text unique not null`
  - `name text not null`
  - `role text not null`（admin/leader/agent/user 等。まずは text+CHECK で十分）
  - `inserted_at timestamptz not null`
  - `updated_at timestamptz not null`

推奨インデックス
- `unique(email)`

## 2. inquiries（Webフォーム受付）
- `inquiries`
  - `id uuid pk`
  - `ticket_id uuid null fk(tickets.id)`（生成後に紐付く）
  - `requester_id uuid not null fk(users.id)`（未ログイン受付は許容しない）
  - `subject text not null`
  - `body text not null`
  - `source text not null default 'web'`
  - `inserted_at timestamptz not null`

推奨インデックス
- `index(ticket_id)`
- `index(requester_id)`

## 3. tickets（運用の基本単位）
「一覧で必要な情報」だけを tickets に保持し、会話/履歴/検証などは別テーブルに分離します。

- `tickets`
  - `id uuid pk default uuid_generate_v7()`
  - `number bigint unique generated always as identity`（人間向け）
  - `subject text not null`
  - `description text null`（要点/サマリ用。チャット本文を蓄積しない）
  - `type text not null`（question/request/bug/incident_candidate 等）
  - `status text not null`（new/triage/in_progress/waiting/resolved/verified/closed 等）
  - `priority text not null`（p1/p2/p3/p4 等）
  - `impact text null`
  - `urgency text null`
  - `requester_id uuid not null fk(users.id)`
  - `assignee_id uuid null fk(users.id)`（現在担当者。履歴は ticket_assignments）
  - `first_response_at timestamptz null`
  - `resolved_at timestamptz null`
  - `verified_at timestamptz null`
  - `closed_at timestamptz null`
  - `latest_message_at timestamptz null`（一覧を会話更新順で並べる用）
  - `lock_version int not null default 1`
  - `inserted_at timestamptz not null`
  - `updated_at timestamptz not null`

推奨インデックス（運用効率に直結）
- `index(status)`
- `index(priority)`
- `index(assignee_id, status)`（担当者の未処理一覧）
- `index(requester_id)`
- `index(latest_message_at desc)`
- （必要なら）`partial index`：openチケット用（例：`where status not in ('verified','closed')`）

## 4. ticket_events（監査・履歴・タイムライン基盤）
- `ticket_events`
  - `id uuid pk default uuid_generate_v7()`
  - `ticket_id uuid not null fk(tickets.id)`
  - `actor_id uuid null fk(users.id)`（システム操作の場合 null も許容）
  - `event_type text not null`（status_changed/assigned/priority_changed/…）
  - `data jsonb not null default '{}'`（from/to、理由など）
  - `inserted_at timestamptz not null`

推奨インデックス
- `index(ticket_id, id)`（チケット内の時系列ページング。uuidv7ならid昇順で良い）
- `index(event_type)`（運用分析で使うなら）

## 5. ticket_assignments（担当履歴）
- `ticket_assignments`
  - `id uuid pk default uuid_generate_v7()`
  - `ticket_id uuid not null fk(tickets.id)`
  - `assignee_id uuid not null fk(users.id)`
  - `assigned_by_id uuid null fk(users.id)`
  - `assigned_at timestamptz not null`

推奨インデックス
- `index(ticket_id, assigned_at desc)`
- `index(assignee_id, assigned_at desc)`

## 6. conversations（チケット紐づきチャットの抽象）
外部チャット連携に備えて「会話（Conversation）」を独立させます。
MVPでは ticket に対して内部チャット1つ、が最小。

- `conversations`
  - `id uuid pk default uuid_generate_v7()`
  - `ticket_id uuid not null fk(tickets.id)`
  - `kind text not null`（MVP: internal_public / internal_private。将来: slack / teams / email_thread 等に拡張）
  - `created_by_id uuid null fk(users.id)`
  - `external_provider text null`
  - `external_ref text null`（channel_idやthread_idなど、プロバイダ依存の参照を格納）
  - `inserted_at timestamptz not null`

制約案
- MVPは `unique(ticket_id, kind)`（ticket×internal_public は1つ、ticket×internal_private は1つ）

推奨インデックス
- `index(ticket_id)`
- `index(external_provider, external_ref)`（外部連携時）

### 6.1 conversation_members（参加者/閲覧者）
通知やアクセス制御、後日の検索・参加履歴に使える。

- `conversation_members`
  - `conversation_id uuid fk(conversations.id)`
  - `user_id uuid fk(users.id)`
  - `role text not null default 'participant'`（participant/watcher 等）
  - `inserted_at timestamptz not null`
  - `primary key (conversation_id, user_id)`

## 7. conversation_messages（チャットメッセージ）
チャットは append-only を基本にし、更新競合を避けます。

- `conversation_messages`
  - `id uuid pk default uuid_generate_v7()`
  - `conversation_id uuid not null fk(conversations.id)`
  - `sender_id uuid null fk(users.id)`（システムメッセージの場合 null）
  - `message_type text not null default 'message'`（message/system/note などに拡張）
  - `body text not null`
  - `body_format text not null default 'plain'`（plain/markdown 等）
  - `meta jsonb not null default '{}'`（将来：引用、bot、外部参照など）
  - `deleted_at timestamptz null`（誤記訂正等で論理削除をしたい場合）
  - `inserted_at timestamptz not null`

推奨インデックス
- `index(conversation_id, id)`（会話内ページング）
- `index(sender_id, inserted_at desc)`（投稿分析）
- （将来）全文検索：`tsvector`+GIN、または `pg_trgm`

運用最適化（推奨）
- メッセージ追加時に `tickets.latest_message_at` を更新（一覧のソートが軽くなる）

## 8. ticket_verifications（検証）と ticket_approvals（最終承認）
検証は複数回起き得るため、履歴として持つ。

- `ticket_verifications`
  - `id uuid pk default uuid_generate_v7()`
  - `ticket_id uuid not null fk(tickets.id)`
  - `verifier_id uuid not null fk(users.id)`（一般ユーザー可）
  - `result text not null`（pass/fail/needs_more_info 等）
  - `notes text null`
  - `inserted_at timestamptz not null`

- `ticket_approvals`
  - `id uuid pk default uuid_generate_v7()`
  - `ticket_id uuid not null fk(tickets.id)`
  - `approver_id uuid not null fk(users.id)`（leader/adminのみ）
  - `decision text not null`（approved/rejected）
  - `notes text null`
  - `inserted_at timestamptz not null`

推奨インデックス
- `ticket_verifications`: `index(ticket_id, inserted_at desc)`
- `ticket_approvals`: `unique(ticket_id) where decision='approved'` のような運用制約（必要なら）

## 9. incidents（障害）と incident_events（タイムライン）
Ticket を基点に Incident を1:0..1 で紐付け、障害運用の専用項目を別テーブルに置く。

- `incidents`
  - `id uuid pk default uuid_generate_v7()`
  - `ticket_id uuid not null unique fk(tickets.id)`
  - `sev int not null`（1〜3等）
  - `status text not null`（declared/investigating/mitigating/monitoring/resolved/postmortem/closed）
  - `declared_by_id uuid not null fk(users.id)`
  - `declared_at timestamptz not null`
  - `mitigated_at timestamptz null`
  - `resolved_at timestamptz null`
  - `summary text null`
  - `impact_summary text null`
  - `lock_version int not null default 1`
  - `inserted_at timestamptz not null`
  - `updated_at timestamptz not null`

- `incident_events`
  - `id uuid pk default uuid_generate_v7()`
  - `incident_id uuid not null fk(incidents.id)`
  - `actor_id uuid null fk(users.id)`
  - `event_type text not null`（declared/status_changed/update 等）
  - `body text null`
  - `data jsonb not null default '{}'`
  - `inserted_at timestamptz not null`

推奨インデックス
- `incident_events`: `index(incident_id, id)`

## 10. tasks（タスク）と ticket_task_links（関連付け）
- `tasks`
  - `id uuid pk default uuid_generate_v7()`
  - `number bigint unique generated always as identity`
  - `title text not null`
  - `description text null`
  - `status text not null`（todo/doing/done 等）
  - `priority text not null`（low/medium/high 等）
  - `due_date date null`
  - `assignee_id uuid null fk(users.id)`
  - `lock_version int not null default 1`
  - `inserted_at timestamptz not null`
  - `updated_at timestamptz not null`

- `ticket_task_links`
  - `ticket_id uuid fk(tickets.id)`
  - `task_id uuid fk(tasks.id)`
  - `relation_type text not null default 'related'`（follow_up/root_cause 等）
  - `inserted_at timestamptz not null`
  - `primary key (ticket_id, task_id)`

## 11. tags / services（将来：分類・影響範囲マップ）
将来、影響範囲マップや分析を行うなら「サービス」を先に入れると効く。

- `tags` / `ticket_tags`
- `services` / `ticket_services` / `incident_services`

（※MVPでは後回しでも良いが、追加は容易）

## 12. attachments（添付）
ポリモーフィック参照（entity_type/entity_id）だとFKで整合性を担保できないため、
「添付先ごとの中間テーブル」を推奨。

- `attachments`
  - `id uuid pk default uuid_generate_v7()`
  - `uploader_id uuid not null fk(users.id)`
  - `filename text not null`
  - `content_type text not null`
  - `byte_size bigint not null`
  - `storage_key text not null`（S3等のキー）
  - `sha256 bytea null`（重複排除や検証用）
  - `inserted_at timestamptz not null`

- 例：`conversation_message_attachments`
  - `message_id uuid fk(conversation_messages.id)`
  - `attachment_id uuid fk(attachments.id)`
  - `primary key (message_id, attachment_id)`

## 13. 巨大化への備え（将来）
- `conversation_messages` / `ticket_events` / `incident_events` が巨大化する可能性が高い。
  - まずは `index(parent_id, id)` でページング
  - さらに必要になったら月次パーティション（inserted_at）を検討

関連ER図：`docs/ERD.md` を参照。
