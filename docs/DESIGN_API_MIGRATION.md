# UI差し替えに伴う JSON API 化 設計メモ

本メモは、Phoenix LiveView ベースのUIを React / Vue / Corex などへ差し替える場合に、バックエンドを JSON API 化して段階移行するための設計方針と実装要点をまとめる。

## 結論
- ドメインは Ash のリソース/アクションに集約済みのため、UIを外しても同じアクションを薄い API レイヤから呼び出すだけで対応できる。
- 最小変更で始めて、必要に応じて AshJsonApi（JSON:API 準拠）や AshGraphql へ拡張可能。

## 選択肢（API レイヤ）
### A. 薄い Phoenix API コントローラ（最小変更・推奨）
- 既存の `Ash.read/get/create/update` と `Ash.Query/Ash.Changeset` を直接呼ぶ薄いコントローラを `/api` 配下に追加。
- Pros: 実装がシンプル。現状の権限/分岐（外部ユーザーは自分のチケットのみ等）を関数化して流用しやすい。自由なレスポンス設計が可能。
- Cons: 仕様の統一（ページング/フィルタ/ソート等）を自前で決める必要。

### B. AshJsonApi（JSON:API 準拠の自動生成）
- リソース/アクションを宣言的に公開。include/フィルタ/ページング/ソートなどが標準提供。
- Pros: 実装量が最小。クライアントの表現力が高い。
- Cons: JSON:API の制約に沿う必要。既存の独自分岐はポリシーや拡張が必要になることがある。

### C. GraphQL（AshGraphql）
- フロントから一度に必要なデータだけ取得可能。複雑なビューやモバイルに有利。
- Pros: バッチ/選択的取得による往復削減。
- Cons: 導入/運用コストがJSONより高め。まずはA/Bから開始し、必要時に導入が現実的。

## 段階移行の基本方針
1) 既存 LiveView は残し、並行して `/api` を追加（機能単位で段階移行）。
2) 認証は当面 Cookie セッション継続も可。SPA/外部クライアント想定が強ければ Bearer トークンへ移行（Phoenix.Token または JWT）。
3) 競合制御は楽観ロック（`lock_version`）で 409 を返す運用へ拡張可能。
4) 監査/可観測性は既存 Telemetry/Logger/Event ログを継続利用。必要に応じて API タグを追加。

## ルーティング雛形（最小変更案）
```elixir
# router.ex 抜粋（既存 pipeline :api を活用）
scope "/api", HelpdeskCommanderWeb do
  pipe_through :api

  post "/sign-in", SessionAPIController, :create

  get  "/tickets", TicketAPIController, :index
  post "/tickets", TicketAPIController, :create
  get  "/tickets/:public_id", TicketAPIController, :show
  patch "/tickets/:public_id", TicketAPIController, :update
end
```

## 認証（Cookie/Token）
- Cookie継続: 既存のセッション発行/検証を API にも適用。
- Token化: サインイン成功時に `user_id/company_id/role` を埋めたトークンを発行。以後 Plug で検証し `current_user` を assigns に設定。

```elixir
# セッションAPI例（Token発行）
def create(conn, %{"company_code" => cc, "login" => login, "password" => pass}) do
  with {:ok, user} <- Auth.authenticate(cc, login, pass),
       true <- user.status == "active" do
    token = MyToken.sign(%{user_id: user.id, company_id: user.company_id, role: user.role})
    json(conn, %{token: token, user: %{id: user.id, display_name: user.display_name, role: user.role}})
  else
    {:error, :pending_approval} -> conn |> put_status(:forbidden)    |> json(%{error: "pending"})
    _                           -> conn |> put_status(:unauthorized) |> json(%{error: "invalid_credentials"})
  end
end
```

## チケット API（読み/作成/更新）
- 既存 LiveView にある外部閲覧制約・可視性分岐（`maybe_filter_for_external/3`、`authorize_ticket/3`）を関数化して共用。

```elixir
# index/show 例（抜粋）
user = conn.assigns.current_user
external? = CurrentUser.external?(user)
query = maybe_filter_for_external(Ticket, user, external?)

with {:ok, tickets} <- Ash.read(query, domain: Helpdesk),
     {:ok, tickets} <- Ash.load(tickets, [:product], domain: Helpdesk) do
  json(conn, Enum.map(tickets, &ticket_json/1))
else
  {:error, _} -> conn |> put_status(500) |> json(%{error: "failed_to_fetch"})
end
```

### レスポンス設計の指針
- IDは外部公開用途に `public_id` を使用（内部PKは非公開）。
- ページングは `page[size]` / `page[before|after]` など cursor 方式を優先（リスト長増大に強い）。
- フィルタ/ソートは最小セットから開始（例: `status`, `priority`, `inserted_at:desc`）。
- 楽観ロック: `lock_version` を If-Match/ボディで受け、更新競合時は 409 + 現行状態を返す。

## エラー/ステータスコードの標準
- 400: バリデーション失敗（`fields` に詳細）
- 401/403: 未認証/権限なし
- 404: リソース未検出
- 409: 競合（`lock_version` 競合）
- 422: セマンティクスエラー（存在整合性・状態遷移違反など）
- 500: 予期せぬ失敗（ログIDを返し、`HelpdeskCommander.Support.Error`で詳細を記録）

`ErrorJSON` を拡張して `code/message/fields/request_id` など統一フォーマットで返却。

## セキュリティ
- CORS: 外部ホストからのSPA想定時は `cors_plug` 等で許可制御。
- CSRF: Cookieセッション＋同一オリジンSPAならCSRF保護継続。Token方式はCSRF対象外だがXSS対策必須。
- Rate limit: 既存 PlugAttack を `/api` にも適用（エンドポイント毎の閾値検討）。
- 入力検証: 既存の Ash constraints/changeset を活用。危険な文字列は保存前に正規化（既存 NormalizeFields 等）。

## 可観測性/監査
- Telemetry: ルータタグ `route`、レイテンシ/失敗レートをダッシュボードへ。
- 監査イベント: 重要操作は既存の `TicketEvent` 等で append-only 記録。
- ログ: `Logger` にリクエストID/ユーザーID/会社IDをメタデータで付与。

## テスト方針
- `ConnCase` で API 統合テスト（200/4xx/5xx, バリデーション, 権限, ページング/フィルタ）。
- 重要レスポンスのスナップショット/契約テスト（フロント連携の破壊検出）。
- 競合テスト（`lock_version` 409）・外部ユーザー可視性テストを重視。

## 代替アプローチ導入時の要点
### AshJsonApi
- ルータに AshJsonApi ルートを追加し、公開するリソース/アクション/フィールド/フィルタを宣言。
- 権限は AshPolicyAuthorizer の採用を検討（external ユースケースに適合）。

### AshGraphql
- 取得最適化が必要になった段階で導入。N+1 を避けるためのロード/バッチ設定を行う。

## 初期スコープ（API）
- 認証: POST `/api/sign-in`
- チケット: GET `/api/tickets`, POST `/api/tickets`, GET `/api/tickets/:public_id`, PATCH `/api/tickets/:public_id`
- 以後: 会話メッセージ/イベント/製品/Inquiry を段階追加

## ロードマップ（例）
1. `/api` 追加（チケット Read 系 + サインイン）
2. チケット Create/Update（ロック/バリデーション/エラーフォーマット確立）
3. 会話/イベントのページングAPI
4. 外部クライアントを段階移行（LiveViewを徐々に廃止）
5. 必要になれば AshJsonApi / GraphQL を導入
