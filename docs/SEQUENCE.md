# シーケンス図（MVP中心）

本書は Helpdesk Commander の主要ユースケースにおける処理の流れを、Mermaid のシーケンス図で整理する。

前提
- UI: Phoenix LiveView
- ドメイン/データ: Ash Resource（将来実装） + Postgres
- リアルタイム: Phoenix PubSub
- チャット: チケット紐づきの2系統（公開/非公開）
## 0. 会社作成（社内のみ）
```mermaid
sequenceDiagram
  autonumber
  actor A as Admin/Leader
  participant B as Browser
  participant LV as LiveView(CompanyForm)
  participant A2 as Ash Domain/Resource
  participant DB as Postgres

  A->>B: 会社作成フォーム入力
  B->>LV: phx-submit(company.create)
  LV->>A2: Company.create(name, company_code_plain)
  A2->>A2: company_code を正規化して HMAC-SHA256
  A2->>DB: INSERT companies
  DB-->>A2: company
  LV-->>B: 会社一覧/詳細に遷移
```

## 0.1 顧客ユーザー仮作成（承認待ち）
```mermaid
sequenceDiagram
  autonumber
  actor A as Admin/Leader
  participant B as Browser
  participant LV as LiveView(UserProvision)
  participant A2 as Ash Domain/Resource
  participant DB as Postgres

  A->>B: 顧客のメールを登録
  B->>LV: phx-submit(user.provision)
  LV->>A2: User.create(company_id, email, display_name=email, status=pending)
  A2->>DB: INSERT users
  DB-->>A2: user(pending)
  LV-->>B: 仮ユーザー作成完了
```

## 0.2 顧客サインアップ（会社ID + login_id/email + パスワード）
```mermaid
sequenceDiagram
  autonumber
  actor U as Customer
  participant B as Browser
  participant LV as LiveView(SignUp)
  participant A2 as Ash Domain/Resource
  participant DB as Postgres

  U->>B: 会社ID + login_id/email + パスワード入力
  B->>LV: phx-submit(signup)
  LV->>A2: Company.lookup(company_code_plain -> hash)
  A2->>DB: SELECT companies WHERE company_code_hash = ...
  DB-->>A2: company
  LV->>A2: User.set_password(user, password)
  A2->>DB: UPDATE users SET password_hash=...
  LV-->>B: 申請完了（承認待ち）
```

## 0.3 管理者承認 → 有効化
```mermaid
sequenceDiagram
  autonumber
  actor A as Admin/Leader
  participant B as Browser
  participant LV as LiveView(UserApproval)
  participant A2 as Ash Domain/Resource
  participant DB as Postgres

  A->>B: 承認操作
  B->>LV: phx-click(user.approve)
  LV->>A2: User.update(status=active)
  A2->>DB: UPDATE users SET status='active'
  LV-->>B: 承認完了
```

## 0.4 ログイン/ログアウト
```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant B as Browser
  participant LV as LiveView(Login)
  participant A2 as Ash Domain/Resource
  participant DB as Postgres

  U->>B: 会社ID + login_id/email + パスワード入力
  B->>LV: phx-submit(login)
  LV->>A2: Company.lookup(company_code_plain -> hash)
  A2->>DB: SELECT company
  LV->>A2: User.authenticate(company_id, login_id/email, password)
  A2->>DB: SELECT users WHERE company_id=... AND (login_id or email)
  A2-->>LV: auth result
  LV-->>B: セッション作成

  U->>B: ログアウト
  B->>LV: phx-click(logout)
  LV-->>B: セッション破棄
```

## 1. 問い合わせ作成（ログイン必須）→ Ticket自動生成 → Conversation（公開/非公開）作成
```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant B as Browser
  participant LV as LiveView(InquiryForm)
  participant A as Ash Domain/Resource
  participant DB as Postgres

  U->>B: 問い合わせフォーム入力
  B->>LV: phx-submit(inquiry.create)

  LV->>A: Inquiry.create(requester_id, subject, body)
  A->>DB: INSERT inquiries
  DB-->>A: inquiry

  LV->>A: Ticket.create(from inquiry)
  A->>DB: INSERT tickets
  DB-->>A: ticket

  note over LV,A: MVP要件: チケットに紐づくチャット（公開/非公開）を必ず作る

  LV->>A: Conversation.create(ticket_id, kind=internal_public)
  A->>DB: INSERT conversations
  DB-->>A: conversation(public)

  LV->>A: Conversation.create(ticket_id, kind=internal_private)
  A->>DB: INSERT conversations
  DB-->>A: conversation(private)

  LV->>A: TicketEvent.append(type=ticket_created)
  A->>DB: INSERT ticket_events

  LV-->>B: 画面遷移（チケット詳細へ）
  B-->>U: チケット詳細表示
```

## 2. チケット詳細表示（初期ロード）
```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant B as Browser
  participant LV as LiveView(TicketShow)
  participant A as Ash Domain/Resource
  participant DB as Postgres

  U->>B: チケット詳細へアクセス
  note over U,B: URLは推測耐性のため public_id を使う
  B->>LV: mount(ticket_public_id)

  LV->>A: Ticket.get_by_public_id(ticket_public_id)
  A->>DB: SELECT tickets WHERE public_id = ...
  DB-->>A: ticket

  LV->>A: Conversation.read_by_ticket(ticket_id)
  A->>DB: SELECT conversations
  DB-->>A: [public, private]

  LV->>A: ConversationMessage.list(conversation_id, limit=50)
  A->>DB: SELECT conversation_messages (paged)
  DB-->>A: messages

  LV-->>B: render（streamで表示）
```

## 3. 公開/非公開チャット投稿（append-only + PubSubでリアルタイム反映）
```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant B as Browser
  participant LV as LiveView(TicketShow)
  participant PS as Phoenix PubSub
  participant A as Ash Domain/Resource
  participant DB as Postgres

  U->>B: チャット送信
  B->>LV: phx-submit(message.create)

  LV->>A: ConversationMessage.create(conversation_id, sender_id, body)
  A->>DB: INSERT conversation_messages
  DB-->>A: message

  note over A,DB: 大量化前提のためメッセージは独立テーブルに追記

  A->>DB: UPDATE tickets.latest_message_at
  DB-->>A: ok

  LV->>A: TicketEvent.append(type=message_posted)
  A->>DB: INSERT ticket_events

  A->>PS: broadcast(ticket_id, message_created)
  PS-->>LV: message_created

  LV-->>B: stream_insert（差分追加）
  B-->>U: 新規メッセージ表示
```

## 4. ステータス更新（競合検知を想定）
```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant B as Browser
  participant LV as LiveView(TicketShow)
  participant A as Ash Domain/Resource
  participant DB as Postgres
  participant PS as Phoenix PubSub

  U->>B: status変更（例: triage→in_progress）
  B->>LV: phx-click(ticket.set_status)

  LV->>A: Ticket.set_status(ticket_id, to_status, expected_lock_version?)
  A->>DB: UPDATE tickets SET status=..., lock_version=lock_version+1 WHERE id=? AND lock_version=?

  alt stale update（競合）
    DB-->>A: 0 rows updated
    A-->>LV: error(stale_update)
    LV-->>B: 「更新競合。再読み込みしてください」
  else success
    DB-->>A: ticket(updated)
    A->>DB: INSERT ticket_events(status_changed)
    A->>PS: broadcast(ticket_id, status_changed)
    PS-->>LV: status_changed
    LV-->>B: 表示更新
  end
```

## 5. 対応完了（resolved）→ 検証（一般ユーザー可）→ 最終承認（リーダー/管理者のみ）
```mermaid
sequenceDiagram
  autonumber
  actor AG as Agent
  actor V as Verifier(User)
  actor L as Leader/Admin
  participant B as Browser
  participant LV as LiveView(TicketShow)
  participant A as Ash Domain/Resource
  participant DB as Postgres

  AG->>B: 対応完了にする
  B->>LV: ticket.set_status(resolved)
  LV->>A: Ticket.set_status(resolved)
  A->>DB: UPDATE tickets
  A->>DB: INSERT ticket_events(resolved)

  V->>B: 検証結果を入力
  B->>LV: ticket.verify(result, notes)
  LV->>A: TicketVerification.create(ticket_id, verifier_id, result, notes)
  A->>DB: INSERT ticket_verifications
  A->>DB: INSERT ticket_events(verification_added)

  L->>B: 最終承認
  B->>LV: ticket.approve(decision=approved)
  LV->>A: TicketApproval.create(ticket_id, approver_id, decision, notes)
  A->>DB: INSERT ticket_approvals

  LV->>A: Ticket.set_status(verified)
  A->>DB: UPDATE tickets
  A->>DB: INSERT ticket_events(approved)
```

## 6. Ticket → Incident 昇格（リーダー/管理者のみ）
```mermaid
sequenceDiagram
  autonumber
  actor L as Leader/Admin
  participant B as Browser
  participant LV as LiveView(TicketShow)
  participant A as Ash Domain/Resource
  participant DB as Postgres

  L->>B: Incidentに昇格
  B->>LV: ticket.escalate_to_incident(sev)

  LV->>A: Incident.create(ticket_id, sev, declared_by)
  A->>DB: INSERT incidents (unique ticket_id)
  A->>DB: INSERT incident_events(declared)

  LV->>A: Ticket.set_type(incident_candidate or incident)
  A->>DB: UPDATE tickets
  A->>DB: INSERT ticket_events(incident_declared)

  LV-->>B: 画面更新（Incident情報表示）
```

## 7. 過去メッセージのページング（無限スクロール/もっと読む）
```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant B as Browser
  participant LV as LiveView(TicketShow)
  participant A as Ash Domain/Resource
  participant DB as Postgres

  U->>B: 「もっと読む」 or スクロールで過去を要求
  B->>LV: phx-click(messages.load_older)

  note over LV,A: 既に表示している最古のメッセージをカーソルとして渡す

  LV->>A: ConversationMessage.list(conversation_id, before=<oldest_id>, limit=50)
  A->>DB: SELECT conversation_messages WHERE id < oldest_id ORDER BY id DESC LIMIT 50
  DB-->>A: older_messages

  LV-->>B: stream_insert(at: 0) もしくは reset+再構成
  B-->>U: 過去メッセージが上に追加される

  note over LV,DB: 将来: チャット/イベントの巨大化に応じてパーティション等を検討
```

## 8. 通知（アプリ内 → 将来チャット連携）
```mermaid
sequenceDiagram
  autonumber
  actor U as Actor(User/Agent/Leader)
  participant B as Browser
  participant LV as LiveView
  participant A as Ash Domain/Resource
  participant DB as Postgres
  participant PS as Phoenix PubSub

  U->>B: チケット更新（例: assignment/status/message）
  B->>LV: action

  LV->>A: 更新系アクション
  A->>DB: UPDATE/INSERT

  note over A,DB: 通知は「誰に何を知らせるか」を決めて永続化する（未読/既読を管理）

  A->>DB: INSERT notifications(target_user_id, type, data)
  A->>PS: broadcast(user_id, notification_created)

  PS-->>LV: notification_created
  LV-->>B: ヘッダー/通知ベル等を更新

  note over A: 将来: 通知を外部チャット（Slack等）にも送る
```

## 9. 監視連携（アラート → Ticket/Incident候補作成）
```mermaid
sequenceDiagram
  autonumber
  participant MON as Monitoring System
  participant API as Webhook Endpoint
  participant A as Ash Domain/Resource
  participant DB as Postgres
  participant PS as Phoenix PubSub
  actor L as Leader/Admin
  participant LV as LiveView

  MON->>API: Alert webhook (service, severity, summary, links)
  API->>A: AlertIngest.process(payload)

  note over A: 重複抑止（fingerprint）や集約は将来拡張

  A->>DB: INSERT tickets(type=incident_candidate, priority=...)
  A->>DB: INSERT conversations(public/private)
  A->>DB: INSERT conversation_messages(system)
  A->>DB: INSERT ticket_events(alert_received)

  A->>PS: broadcast(new_ticket_created)

  L->>LV: ダッシュボードで検知
  LV-->>L: Incident候補として表示

  L->>LV: 昇格（Incidentにする）
  LV->>A: Incident.create(ticket_id, sev)
  A->>DB: INSERT incidents
  A->>DB: INSERT incident_events(declared)
```

## 10. SSOログイン（OIDC想定）
```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant B as Browser
  participant APP as Phoenix App
  participant IDP as IdP(SSO/OIDC)
  participant A as Ash Domain/Resource
  participant DB as Postgres

  U->>B: ログイン
  B->>APP: /auth/login
  APP-->>B: 302 Redirect to IdP (authorize)

  B->>IDP: authorize request
  IDP-->>B: 302 Redirect back (code)

  B->>APP: /auth/callback?code=...
  APP->>IDP: token exchange (code -> id_token/access_token)
  IDP-->>APP: tokens

  APP->>APP: validate id_token (issuer/audience/nonce)

  APP->>A: User.upsert_by_subject(email/sub)
  A->>DB: INSERT or UPDATE users
  DB-->>A: user

  APP-->>B: セッション確立（cookie）+ 302 to app
  B-->>U: ログイン完了

  note over APP,A: 権限（role）はIdP claim またはアプリ側管理で決定
```

---

必要なら、次を追加できます。
- 添付（チャットメッセージへの添付、ウイルススキャン等）
- 類似チケット提案（重複検知）
- 変更相関（デプロイ/PRとの紐付け）
