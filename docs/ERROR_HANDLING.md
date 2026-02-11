# エラーハンドリング指針（HelpdeskCommander）

このプロジェクトでは **「期待される失敗は値」「期待しない失敗はクラッシュ」** を基盤に設計します。
UI（LiveView）やHTTP境界（Controller）でフォールバックを集約し、ドメイン層は `{:ok, _} | {:error, reason}` を安定形式で返します。

---

## 1. 失敗の2系統

### A. 期待される失敗（ドメイン/外界起因）
- 例: 入力不正、権限不足、リソース未検出、外部APIの429/timeout
- **返り値で表現**: `{:error, reason}`
- **上位に伝播**して境界でフォールバックする

### B. 期待しない失敗（バグ/不変条件破れ）
- 例: 想定外のnil、あり得ない分岐、型前提の破綻
- **例外で落としてよい**（fail fast）
- 回復は **Supervisorで再起動**

---

## 2. reason は安定形にする

下位ライブラリの構造体や例外をそのまま上位へ漏らさない。

推奨:
- タグ付きタプル  
  - `{:error, :not_found}`
  - `{:error, {:validation, changeset}}`
  - `{:error, {:forbidden, :external_user}}`
  - `{:error, {:external, :timeout}}`
- あるいは独自の「値としてのエラー構造体」

---

## 3. with を成功パイプとして使う

`with` で正常系を直列に繋ぎ、失敗は `{:error, reason}` のまま自然に伝播させる。

---

## 4. bang 関数の使用範囲

- `foo!/1` は **プロセス境界の内側**に限定  
  （Supervisor配下で落ちても回復できる層）
- LiveView / Controller では **non-bang を原則**

---

## 5. フォールバックの置き場所

### 5.1 LiveView（UI境界）
`mount/3` と `handle_event/3` で `{:error, reason}` を **flash / redirect** に変換する。

### 5.2 Controller（HTTP境界）
`action_fallback` で **HTTPステータスとJSON/HTMLエラー** を一元化する。

### 5.3 ドメイン層
**UIやHTTPを知らない**。`{:ok, _} | {:error, reason}` のみ返す。

### 5.4 Supervisor / Oban
**クラッシュ前提**の再起動が基本。リトライは限定的に設計する。

---

## 6. ログの方針

- 期待される失敗 → warn かログ無し
- 想定外の失敗 → error + 文脈メタデータ

**握りつぶして成功扱いにしない**ことを最優先とする。

---

## 7. try/rescue・throw/catch

- **原則最小限**
- 例外を捕まえるのは **境界での変換用途のみ**
  - 外部ライブラリの例外 → `{:error, {:external, reason}}`
- throw/catch は **同一モジュール内で閉じる**

---

## 8. リトライの指針

- `:timeout` / `429` 等、理由を限定
- **冪等性が担保できる操作のみ**
- backoff と上限を必ず設計する

---

## 9. このプロジェクトの適用領域

本システムは **Phoenix + Ash（LiveView中心）** のWebアプリであり、
JSON API主体やGenServer常駐型ではありません。

従って **フォールバックの主戦場は LiveView / Controller** です。

