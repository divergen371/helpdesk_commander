------------------------- MODULE attachment_lifecycle -------------------------
\* 添付ファイルの検疫ライフサイクルのモデル。
\*
\* 対象コード: lib/helpdesk_commander/helpdesk/attachments.ex
\*   ingest/3, scan_attachment/1, scan/1, rescan/2, rescan_outdated/1,
\*   override_infected/3, downloadable?/1, download_path/1
\*   lib/helpdesk_commander/attachments/storage.ex promote/1, path/2
\*   lib/helpdesk_commander/workers/scan_attachment_worker.ex
\*
\* 状態の軸は 2 つ（DB の scan_status と、実バイトの置き場所）＋ バイトに対する判定。
\* コードでは store/3 が upload を quarantine/ に複製し、promote/1 が
\* File.rename で clean/ へ「移動」する（複製ではない）。したがって一度 clean に
\* なった実体は quarantine/ に存在せず、scan/1 は常に quarantine のパスを開くため
\* 再スキャンは「ファイルが無い」状態を読むことになる。
\*
\* 各アクションはコードの 1 関数に 1 対 1 で対応する。1 つの不可分な処理を
\* 1 ステップとして書く。
EXTENDS Naturals

VARIABLES status, loc, verdict

vars == <<status, loc, verdict>>

\* status  : DB の scan_status（pending / clean / infected / failed / none=未作成）
\* loc     : 実バイトの置き場所（quarantine / clean）
\* verdict : 現在置かれているバイトに対して最後に得られた判定（none / clean / infected）

TypeOK ==
  /\ status  \in {"none", "pending", "clean", "infected", "failed"}
  /\ loc     \in {"quarantine", "clean"}
  /\ verdict \in {"none", "clean", "infected"}

Init ==
  /\ status  = "none"
  /\ loc     = "quarantine"
  /\ verdict = "none"

\* attachments.ex ingest/3 -> Storage.store/3: status pending、実体は quarantine/
Ingest ==
  /\ status = "none"
  /\ status'  = "pending"
  /\ loc'     = "quarantine"
  /\ verdict' = "none"

\* scan_source/1 + scan/1 の成功側: 実体を quarantine/ か clean/ から探して読み、
\* 配信可能なら clean/ に置く（既に clean/ なら promote は不要）。
WorkerScanCleanFromQuarantine ==
  /\ status \in {"pending", "failed"}
  /\ loc = "quarantine"
  /\ status'  = "clean"
  /\ loc'     = "clean"      \* Storage.promote/1 (rename)
  /\ verdict' = "clean"

WorkerScanCleanFromClean ==
  /\ status \in {"pending", "failed"}
  /\ loc = "clean"
  /\ status'  = "clean"
  /\ verdict' = "clean"
  /\ UNCHANGED loc

\* scan/1 の感染側: 実体が clean/ にあれば demote で quarantine/ へ戻してから状態を書く
\* （place_bytes/3 の非配信分岐）。
WorkerScanInfectedFromQuarantine ==
  /\ status \in {"pending", "failed"}
  /\ loc = "quarantine"
  /\ status'  = "infected"
  /\ verdict' = "infected"
  /\ UNCHANGED loc

WorkerScanInfectedFromClean ==
  /\ status \in {"pending", "failed"}
  /\ loc = "clean"
  /\ status'  = "infected"
  /\ loc'     = "quarantine"  \* Storage.demote/1 (rename)
  /\ verdict' = "infected"

\* scan/1 の失敗側: 同じく非配信なので実体は quarantine/ に置く。
WorkerScanErrorFromQuarantine ==
  /\ status \in {"pending", "failed"}
  /\ loc = "quarantine"
  /\ status' = "failed"
  /\ UNCHANGED <<loc, verdict>>

WorkerScanErrorFromClean ==
  /\ status \in {"pending", "failed"}
  /\ loc = "clean"
  /\ status' = "failed"
  /\ loc'    = "quarantine"   \* Storage.demote/1
  /\ UNCHANGED verdict

\* place_bytes/3 の失敗（mkdir・rename のエラー）。状態は clean ではなく failed にし、
\* 実体の位置は動かせないのでそのまま残す。
PlaceFailed ==
  /\ status \in {"pending", "failed"}
  /\ loc = "quarantine"
  /\ status' = "failed"
  /\ UNCHANGED <<loc, verdict>>

\* rescan_outdated/1: clean を pending に戻してジョブを積む。実体には触らない。
Sweep ==
  /\ status = "clean"
  /\ status' = "pending"
  /\ UNCHANGED <<loc, verdict>>

\* rescan/2: failed のみ pending に戻せる。
AdminRescan ==
  /\ status = "failed"
  /\ status' = "pending"
  /\ UNCHANGED <<loc, verdict>>

\* override_infected/3: 同一会社の admin/leader が理由付きで解除。
\* Storage.promote/1 で clean/ へ移し、status=clean を書く。
Override ==
  /\ status = "infected"
  /\ status'  = "clean"
  /\ loc'     = "clean"
  /\ verdict' = "clean"

Next ==
  \/ Ingest
  \/ WorkerScanCleanFromQuarantine
  \/ WorkerScanCleanFromClean
  \/ WorkerScanInfectedFromQuarantine
  \/ WorkerScanInfectedFromClean
  \/ WorkerScanErrorFromQuarantine
  \/ WorkerScanErrorFromClean
  \/ PlaceFailed
  \/ Sweep
  \/ AdminRescan
  \/ Override

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* 性質 1（安全性・配信）: 配信可能な状態のとき、実体は clean/ にあり、          *)
(* そのバイトは clean と判定されている。place_bytes/3 の失敗は clean を書かない。 *)
(***************************************************************************)
SafetyDownloadOnlyClean ==
  (status = "clean") => (loc = "clean" /\ verdict = "clean")

(***************************************************************************)
(* 性質 2（隔離）: 感染と判定されたバイトは配信ディレクトリに置かない。         *)
(* WorkerScanInfectedFromClean が demote するので、状態だけに依存しない。       *)
(***************************************************************************)
InfectedBytesQuarantined ==
  (verdict = "infected") => (loc = "quarantine")

(***************************************************************************)
(* 性質 3（隔離）: failed の実体も配信ディレクトリに残さない。                  *)
(***************************************************************************)
FailedBytesQuarantined ==
  (status = "failed") => (loc = "quarantine")

====
