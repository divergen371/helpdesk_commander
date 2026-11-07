/*
  組織固有の検知ルール（HC-25）

  - ルール名は `Internal_` 接頭辞を付け、ClamAV の検知名と区別する
  - 追加・変更したら docs/OPERATIONS_SCANNER.md の手順で再スキャンする
  - 誤検知が出た場合はルールを修正するか、SHA256 許可リスト（HC-24）で許可する
*/

rule Internal_Phishing_Phrase
{
  meta:
    author = "helpdesk-commander"
    description = "社内ヘルプデスクを装う定型フィッシング文面（サンプル）"
  strings:
    $a = "ヘルプデスクを装う" nocase wide ascii
    $b = "至急パスワードを再設定" nocase wide ascii
  condition:
    any of them
}

rule Internal_Executable_Embedded
{
  meta:
    author = "helpdesk-commander"
    description = "文書内に埋め込まれた PE 実行ファイル（サンプル）"
  strings:
    $mz = { 4D 5A }
  condition:
    $mz at 0
}
