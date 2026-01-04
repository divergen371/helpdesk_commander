# ERD

以下は DB スキーマ案（`docs/DB_SCHEMA.md`）のER図です（Mermaid）。

```mermaid
erDiagram
  users {
    uuid id PK
    text email
    text name
    text role
    timestamptz inserted_at
    timestamptz updated_at
  }

  inquiries {
    uuid id PK
    uuid ticket_id FK
    uuid requester_id FK
    text subject
    text body
    text source
    timestamptz inserted_at
  }

  tickets {
    uuid id PK
    bigint number
    text subject
    text description
    text type
    text status
    text priority
    text impact
    text urgency
    uuid requester_id FK
    uuid assignee_id FK
    timestamptz first_response_at
    timestamptz resolved_at
    timestamptz verified_at
    timestamptz closed_at
    timestamptz latest_message_at
    int lock_version
    timestamptz inserted_at
    timestamptz updated_at
  }

  ticket_events {
    uuid id PK
    uuid ticket_id FK
    uuid actor_id FK
    text event_type
    jsonb data
    timestamptz inserted_at
  }

  ticket_assignments {
    uuid id PK
    uuid ticket_id FK
    uuid assignee_id FK
    uuid assigned_by_id FK
    timestamptz assigned_at
  }

  conversations {
    uuid id PK
    uuid ticket_id FK
    text kind
    uuid created_by_id FK
    text external_provider
    text external_ref
    timestamptz inserted_at
  }

  conversation_members {
    uuid conversation_id FK
    uuid user_id FK
    text role
    timestamptz inserted_at
  }

  conversation_messages {
    uuid id PK
    uuid conversation_id FK
    uuid sender_id FK
    text message_type
    text body
    text body_format
    jsonb meta
    timestamptz deleted_at
    timestamptz inserted_at
  }

  ticket_verifications {
    uuid id PK
    uuid ticket_id FK
    uuid verifier_id FK
    text result
    text notes
    timestamptz inserted_at
  }

  ticket_approvals {
    uuid id PK
    uuid ticket_id FK
    uuid approver_id FK
    text decision
    text notes
    timestamptz inserted_at
  }

  incidents {
    uuid id PK
    uuid ticket_id FK
    int sev
    text status
    uuid declared_by_id FK
    timestamptz declared_at
    timestamptz mitigated_at
    timestamptz resolved_at
    text summary
    text impact_summary
    int lock_version
    timestamptz inserted_at
    timestamptz updated_at
  }

  incident_events {
    uuid id PK
    uuid incident_id FK
    uuid actor_id FK
    text event_type
    text body
    jsonb data
    timestamptz inserted_at
  }

  tasks {
    uuid id PK
    bigint number
    text title
    text description
    text status
    text priority
    date due_date
    uuid assignee_id FK
    int lock_version
    timestamptz inserted_at
    timestamptz updated_at
  }

  ticket_task_links {
    uuid ticket_id FK
    uuid task_id FK
    text relation_type
    timestamptz inserted_at
  }

  users ||--o{ tickets : requester
  users ||--o{ tickets : assignee
  users ||--o{ inquiries : requester

  inquiries }o--|| tickets : creates

  tickets ||--o{ ticket_events : has
  users ||--o{ ticket_events : actor

  tickets ||--o{ ticket_assignments : history
  users ||--o{ ticket_assignments : assignee

  tickets ||--o{ conversations : has
  conversations ||--o{ conversation_members : members
  users ||--o{ conversation_members : user

  conversations ||--o{ conversation_messages : has
  users ||--o{ conversation_messages : sender

  tickets ||--o{ ticket_verifications : has
  users ||--o{ ticket_verifications : verifier

  tickets ||--o{ ticket_approvals : has
  users ||--o{ ticket_approvals : approver

  tickets ||--o| incidents : may_have
  incidents ||--o{ incident_events : has
  users ||--o{ incident_events : actor

  tickets ||--o{ ticket_task_links : links
  tasks ||--o{ ticket_task_links : links
  users ||--o{ tasks : assignee
```

補足
- 主キーは uuidv7 を想定（DBでは `uuid_generate_v7()` をデフォルトに設定）。
- `conversations.kind` はMVPで `internal_public` / `internal_private`（2系統）を用意し、将来は `slack/teams/email_thread` 等の外部連携に拡張できます。
- チャット・イベントは `index(parent_id, id)` 前提でページングし、巨大化したらパーティションを検討します。
