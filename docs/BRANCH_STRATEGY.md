# ブランチ戦略 / CI・CD 方針

本ドキュメントは Helpdesk Commander の開発におけるブランチの役割と、CI/CD の強度（どこでどこまで検査するか）を定義する。

## ゴール
- 検証（PoC）を素早く回しつつ、`main` の品質を担保する
- 「prototype → archetype → feature → main」の流れを標準化する
- 緊急修正（hotfix）は最短で `main` に戻しつつ、品質ゲートは落とさない

## ブランチ種別と役割

### main
- 役割: 常に動作する基準線（リリース可能）。
- ルール:
  - 直接 push はしない（PR でのみ更新）。
  - `main` への PR はフル CI を必須とする。

### prototype/* （PoC）
- 役割: 仮説検証最優先。雑でも良い。DB未実装・インメモリ・破壊的変更も許容。
- ルール:
  - 原則 `main` に直接マージしない。
  - 成果が良いものだけを `archetype/*` に持ち帰る。
  - `prototype/* → archetype/*` は **squash** を標準とする（PoCの細かい履歴は残さない）。

### archetype/* （アーキタイプ）
- 役割: PoCの成果を「製品実装」に落とし込むための受け皿。
  - 設計の磨き込み
  - Ash Resource / Migrations への置き換え
  - 命名・責務分割・境界の整理
- ルール:
  - エピック単位で最大 **2ブランチまで**（増やしすぎない）。
  - `prototype/*` からの取り込みは squash。
  - `feature/*` は原則 `main` 起点。大きなエピックの進行中のみ `archetype/*` 起点を許容。

### feature/*
- 役割: 通常開発。
- ルール:
  - 原則 `main` から切る。
  - `main` への PR はフル CI を必須とする。

### hotfix/*
- 役割: 緊急修正（速攻で `main` に戻す）。
- ルール:
  - `main` から切る。
  - `main` への PR はフル CI を必須とする。
  - 影響が `archetype/*` にも及ぶ場合、`main` 反映後に追随マージ/反映を行う。

## CI/CD 方針

## CI（GitHub Actions）
- PR → `main`: フル CI（test/format/credo/dialyzer/assets）。
- PR → `archetype/*`:
  - `feature/*` / `hotfix/*` から: フルまたは準フル（少なくとも compile+test+format+credo）。
  - `prototype/*` から: **smoke のみ**（compile+test）。
    - PoCの成果を早く持ち帰るため。
    - ただし最低限の破綻（コンパイル不可/テスト崩壊）はここで止める。

### docs-only のCI抑止
- ルート直下の `*.md` と `docs/*.md` のみ変更の場合、CIは実行しない。

## CD（将来）
- `main` マージ: staging 相当への自動デプロイ（将来導入）。
- タグ（例: vX.Y.Z）: production デプロイ（将来導入）。
- `prototype/*` / `archetype/*`: デプロイ対象外（必要なら手動 preview）。
