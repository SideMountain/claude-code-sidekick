# ADR-0022: stack pack のサイクル統合・軽さドクトリン・intake routing

## ステータス

採用（2026-06-19、原則を決定・具体配線は follow-up）

## 背景

ADR-0021 で stack pack（規定アーキ + system-map + 強制）を確立し、v0.10.0 で Next.js pack に fitness（検知）と scaffold（生成）を出荷した。だが capability audit（全機能 × ライフサイクル輪の棚卸し）で、stack-pack の輪が**閉じ切っていない**ことが判明した:

- 検知（fitness `test:arch`）と可視化（system-map）を**再実行する主体が下流の手動 or CI 任せ**。ccs は「銃を配り、下流が引き金を引く」状態。
- system-map の drift は完全手動で、その `uncertainties` は fitness / ARCHITECTURE に還流しない。

これに対し「下流が CI を配線する」前提（雛形コピー＝O2、`/setup` が CI 自動生成＝O3）を検討したが、いずれも**下流に「意識」を要求**する。これは ccs の北極星（ADR-0018: 下流はハーネスを意識せず恩恵を受ける／ADR-0015: 下流 ccs 不意識運用）と正面衝突する。オーナーの言葉で原則が再定義された:

- **サイクル（考え方）＝製品**。stack 非依存・自動・無意識で回る。「考えなくても最適」が売り。
- **stack ＝ 変数**（PJ ごとに変わる）。だが**サイクルは不変**。
- **system-map / fitness ＝ サイクルの自動副産物（複利）**。手動ステップにしない。
- **重さは敵**。レビュー等が重いと「回すのが億劫」になり、サイクルが回らなくなる＝本末転倒。

加えて、サイクルの始点「**①起票**」が弱い。建付け上は標準構成（Layer 0）= auto-memory backlog + GitHub Issues の二トラックだが（`task-management.md`）、運用は backlog 偏重で、`/close-chat` は backlog にしか流さず、casual に「Issue だけ切る」導線も、backlog/Issue のルーティング基準も無い。

## 決定

### 決定 1: stack pack はサイクルのゲートに自動統合する（下流に CI を配線させない）

下流に CI を組ませるのではなく、**普遍サイクルが既に自動で通るゲート**（`/review`・`/auto-implement`・hooks・`/close-chat`）が、`STACK_PACK` が立っていれば pack の検査/生成を呼ぶ。下流は **`STACK_PACK` フラグ 1 個**だけで、あとはサイクルが回す。**CI 配線ゼロ・意識ゼロ**。Spring/Python pack でも同じゲートに別アダプタを挿すだけ＝**サイクル不変・stack 可変**。

### 決定 2: 軽さドクトリン（自動化は決定的・安いものだけ）

サイクルに**自動で乗せるのは「決定的・安い」もの限定**。高価な LLM 分析は **on-demand / scope-gate** に留める。サイクルを重くして「回すのが億劫」にしない（重さでサイクルが死ぬのが最大の失敗）。

- `/review` を膨らませない（既存の scope-aware を維持＝関連観点のみ）。
- 自動の検査はスクリプト（決定的）で行い、**LLM 観点を増やさない**。
- 構造可視化は安い hard 層を自動・高価な soft 層（LLM narration）は on-demand。

### 決定 3: プラグ点（命名のみ・具体配線は follow-up）

| サイクル段 | プラグ | 軽さ設計 |
|---|---|---|
| ⑤ テスト | `/auto-implement` test phase が fitness を自動実行 | 決定的・即終 |
| ⑥ レビュー | `/review` に **architecture fast-gate**（fitness）を追加 | **6 個目の LLM 観点にしない**。決定的 pre-gate として走らせ、**違反時のみ**既存観点に渡す。`STACK_PACK` 有 かつ 関連ファイル変更時のみ |
| 複利・地図 | system-map の **hard 層を構造変化/節目で自動再生成** | hard=決定的で頻繁・soft=on-demand |

### 決定 4: ①起票 = intake routing（三層・昇格・重複禁止）

サイクルの始点を二（三）トラックで実運用する。audience × 永続性 × 「他人が拾えるか」で振り分ける:

| 行き先 | 何を | 性質 |
|---|---|---|
| **auto-memory Backlog**（既定・最軽） | 個人の次セッション用メモ・working context・未成形の検討残 | local・git 非追跡・`/weekly-inventory` が圧縮 |
| **GitHub Issue** | チームの機能改善・bug・他人が拾える具体的作業単位・可視化したいもの | repo native・追跡可・逆流ループ（Issue → `/inventory` → `/discover`/`/auto-implement` → `/release`）に乗る |
| Notion（Layer 2・任意） | 非エンジニア横断のタスク共有 | `NOTION_ENABLED` 時のみ |

ルール（軽さ優先）:
- **「これ Issue にして」を摩擦ゼロの一級アクションに**（`/discover` のフルフローを通さず単発 `gh issue create`・テンプレ/ラベル自動）。
- ルーティングは **heuristic（Claude が提案）で強制ゲートにしない**。迷ったら**軽い backlog が既定**。
- **1 アイテム＝1 ホーム（重複禁止）**。backlog が具体化したら **Issue へ昇格 → backlog から消す（Issue# 参照）**。feedback→brain と同じ昇格ラダー。
- `/close-chat` の選択肢を「**積む / Issue 化 / クローズ / 次回**」に拡張する。

## 理由

- **北極星整合**: 下流はフラグ 1 個。サイクルが複利（検査・地図）を自動で運ぶ＝意識せず恩恵。
- **stack 非依存の不変サイクル**: 「方法」を不変に保ち pack を差し込みにすることで、Next 以外の pack も同じサイクルに乗る。
- **軽さで回り続ける**: 重い自動化はサイクル自体を殺す。決定的・安いものだけ自動化する制約が、回り続ける条件。
- **二トラックは元設計**（Layer 0 = backlog + Issues）。運用で立てるだけで、新レイヤーの発明ではない。

## 却下した案

- **O2: CI ワークフロー雛形を下流がコピー** — 下流に「コピーして CI を組む」意識を要求。北極星違反。
- **O3: `/setup` が CI を自動生成** — GH Actions に過結合し、下流が望まぬ CI を撒くリスク。意識ゼロにも届かない（プロバイダ前提）。
- **news-upstream を下流配布**（参考: 輪 8）— 上流ウォッチは保守者の輪。下流の最新化は `/inventory`→`/adopt` で別に閉じており、配ると純下流にノイズ。保守者専用のまま（ADR-0006/0017）。

## 影響

- **supersede**: capability audit の「輪 7＝下流が CI を持つ」スタンス（本 ADR 前の暫定）を上書き。
- **refine**: ADR-0018（北極星）・ADR-0021（stack pack）・ADR-0015（下流不意識運用）。
- **follow-up（実装・別 PR）**: (a) `/review` に architecture fast-gate（fitness・非 LLM・scope-gate）/ (b) system-map hard 層の自動再生成トリガ（PostToolUse hook で route/schema 変更検知 等）/ (c) `/close-chat` に Issue ルーティング選択肢 + casual「Issue だけ切る」アクション明文化 / (d) `task-management.md`・`knowledge-map.md` に intake routing 表を追記。
- **defer（さらに詰める論点）**: 起票自動化の深掘り（Issue 起票をどこまで自動提案するか）・system-map soft 層 narration の発火点・再生成トリガの具体実装・greenfield 通し検証での実測。
- 配布: ADR は下流に配布しない（ADR-0014）。本決定の実体は上記 follow-up の skill/hook 変更として配布される。

## 関連 ADR

- ADR-0018（北極星と最小ループ）/ ADR-0015（下流 ccs 不意識運用）/ ADR-0021（stack pack 方式）/ ADR-0005（下流連携原則）/ ADR-0012（Notion 判断ログ）/ ADR-0009（リリース取込）/ ADR-0006（単一リポ・news-upstream 非配布）。
