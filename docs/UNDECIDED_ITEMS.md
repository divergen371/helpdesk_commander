未決定事項リスト（優先度順）
決定順: 1 → 2 → 3

P0（最優先）
1. 権限/可視性の境界
   - 公開/非公開/内部メモの閲覧・投稿・編集権限
   - ロール定義（requester / assignee / internal / system など）
   - 外部共有の有無と範囲
   決定: 顧客（社外）も利用者に含む。社内は全件閲覧、社外は自社チケットのみ。
         priority=P1 かつ incident_sev=P1 は全体公開候補とし、管理者/リーダーの手動承認で公開。
         検証・承認の確定は管理者/リーダーのみ。
         優先度・担当者アサインの変更入力は誰でも可、確定は管理者/リーダーのみ。

2. バリデーション仕様・サニタイズ方針
   - 必須項目、長さ、形式、禁止文字
   - HTML/Markdownの扱い（許可/禁止、保存前後のサニタイズ）
   - 入力エラー表示方針
   決定: サーバ側で必須/長さ/形式を検証、列挙値はallowlist。
         文字列はトリムし空白のみは無効。
         MVPはプレーンテキストのみ、Markdown/HTMLは許可しない。
         表示時は文脈エスケープを必須。
         最大長: Inquiry subject 1..200 / body 1..10,000、
                 Ticket subject 1..200 / description 1..10,000、
                 ConversationMessage body 1..5,000。
         将来Markdown許可時はHTML無効化 + レンダリング後allowlistサニタイズ。

3. 画面設計・画面遷移
   - 画面一覧と導線（一覧→詳細→作成→戻る）
   - 直リンク/戻る/パンくずの扱い
   - 状態遷移（ステータス更新UI/導線）
   決定: 画面は一覧/新規作成/詳細の3つ。詳細から一覧へ戻れる導線を用意。
         社外ユーザーは新規作成＋自身作成の一覧/詳細のみ。

4. サインアップ/ログイン/会社運用
   - 会社作成の権限、会社IDの扱い、承認フロー
   - login_id / email / display_name の方針
   決定: 会社作成は社内のみ。会社IDは `A-123456` 形式で入力、DBにはHMAC-SHA256でハッシュ保存。
         顧客メールで仮ユーザー作成（status=pending）→ 管理者承認で有効化。
         login_id（ASCIIのみ, 3..32）と display_name（Unicode可, 1..100）を分離。
         ログインは会社ID + login_id or email + パスワード。

P1（重要）
5. イベント/監査ログ仕様
   - 記録対象の操作とpayload標準
   決定:
   - 記録対象（MVP）:
     - `ticket_created`
     - `status_changed`（from/to、resolved からの巻き戻し時は `rolled_back_at`）
     - `message_posted`（公開/内部メモ）
     - `verification_submitted`（result）
     - `priority` / `assignee` の確定更新（Ticket.update経由）
   - payload標準:
     - 共通: `ticket_id`, `actor_id`, `company_id`, `inserted_at`
     - event固有データは `data` に map で保持
     - 個人情報は `data` に冗長保持しない（参照はFK優先）

6. 通知仕様
   - 対象・タイミング・抑制/重複防止・チャネル
   決定:
   - MVP対象イベント:
     - `ticket_resolved_review_required`（status が resolved に遷移）
     - `ticket_verification_submitted`（検証結果が登録）
   - 受信者:
     - 同一 company の `admin` / `leader` かつ `status=active`
     - 操作本人（actor）は除外
   - 保存:
     - `ticket_notifications` に recipient 単位で保存（read_at で既読管理）
   - 配信チャネル:
     - MVPはアプリ内保存のみ（外部通知は未実装）
   - 抑制:
     - 重複抑制/クールダウンは次フェーズで実装

7. 検索/フィルタ/ソート
   - 対象フィールド、並び順、デフォルト表示
   決定:

P2（計画に乗せればOK）
8. 削除・復元ポリシー
   - 論理/物理削除、保持期間
   決定:
   - 物理削除は実施しない（FK整合性と監査性を優先）
   - `deleted_at` は採用せず、`status` による段階制御（`suspended` → `anonymized`）
   - 匿名化猶予期間は30日。Oban日次ジョブで自動匿名化
   - 詳細は `docs/DESIGN_USER_DELETION.md` を参照

9. 添付/ファイル仕様
   - 容量/形式/保存先/ウイルススキャン
   決定:

10. 国際化/表示形式
   - 日時/言語/タイムゾーン
   決定:

11. エラーUXと運用ログ
    - 表示メッセージ/ログ粒度/監視指標
    決定:

12. SLA/レート制限
    - 制限値、429時の扱い
    決定:
