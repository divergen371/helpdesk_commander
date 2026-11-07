---
id: HC-25
title: YARA ルールによる組織固有の検知を追加する
status: Done
assignee: []
created_date: '2026-11-03T09:14:00Z'
updated_date: '2026-11-06T14:44:00Z'
labels:
  - security
  - quality
milestone: m-1
dependencies:
  - HC-22
  - HC-23
priority: medium
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ClamAV の汎用シグネチャでは、自社固有の phishing 文書・マクロ・社内ツールを装う検体を拾いにくい。YARA ルールを版管理して追加し、組織固有の検知を足せるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 YARA ルールをリポジトリで版管理し、スキャナから読み込める
- [x] #2 ルール一致時は infected として隔離し、一致ルール名を scan_note に記録する
- [x] #3 ルール更新時に既存添付を再スキャンできる
- [x] #4 良性ファイルとルール一致ファイルのテストがある
- [x] #5 ルール追加・更新手順を docs に記載する
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 テストが通る
- [x] #2 ドキュメントを更新する
- [x] #3 既存機能の回帰がない
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: priv/yara/internal_rules.yar（Internal_ 接頭辞のサンプル 2 ルール）を追加し、YARA ルールをリポジトリで版管理。Attachments.Yara を新設し、:attachment_yara_command（例 yara）が設定されているときだけ有効化。コマンドが yara の場合は :attachment_yara_rules（既定 priv/yara）を引数に使い、カスタムラッパーは {command, args} で指定。YARA はマッチ有無に関わらず exit 0 のため stdout のルール名で判定する。
統合: ClamAV が clean / skipped のときに YARA を実行し、一致は infected として隔離、scan_note に YARA: <ルール名> を記録。YARA の異常終了・タイムアウトは failed として隔離（fail-closed）。
共通化: Support.CommandRunner を新設し、Scanner / ScanMetadata / UpdateSignaturesWorker / Yara の System.cmd + Task を統合。コマンド未インストール時の Task リンク経由のクラッシュを修正（{:error, enoent} として返す）。
再スキャン: ルール更新後は既存の Attachments.rescan_outdated/1 を実行する手順を docs に記載。誤検知はルール修正または SHA256 許可リストで対応。
テスト: Yara 5 件（無効・マッチ解析・クリーン・異常終了・ルールディレクトリ指定）+ ingest 2 件（良性/一致の隔離と scan_note、YARA エラー時 failed）。共通ランナーの導入後も掃引 85 件のスキャナ系テストが通過。
検証: mix precommit 419 passed（13 properties / 406 tests）を 3 回連続確認、coveralls 82.4%（3529 / 4282 行）、dialyzer 0 errors、ash.codegen --check 成功。docs/OPERATIONS_SCANNER.md（追加・更新・再スキャン手順）と DESIGN_ATTACHMENTS/STATUS を更新。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
YARA による組織固有検知を追加した。priv/yara/*.yar を版管理し、ATTACHMENT_YARA_COMMAND（既定引数は ATTACHMENT_YARA_RULES、既定 priv/yara）で有効化する。ClamAV が clean/skipped のとき YARA を実行し、一致は infected として隔離して scan_note にルール名を記録、YARA の異常終了・タイムアウトは failed として隔離する。ルール更新後は rescan_outdated で既存添付を再スキャンする手順を docs に記載。あわせて外部コマンド実行を Support.CommandRunner に共通化し、コマンド未インストール時に Task のリンクで呼び出し元が落ちる不具合を修正した。テストは Yara 5 件と ingest 2 件を追加し、mix precommit 419 passed（13 properties / 406 tests）、coveralls 82.4%、dialyzer 0 errors。
<!-- SECTION:FINAL_SUMMARY:END -->
