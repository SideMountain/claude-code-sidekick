# ADR-0012: Notion判断ログ同期機能の追加

## ステータス

提案中（2026-04-25）

## 背景

sidekick は `NOTION_ENABLED=true` のとき、Notion Tasks DB とタスク状態を双方向同期している（`.claude/rules/task-management.md` 参照）。一方、セッション中に発生する「判断・決定」は現状 `docs/decisions/`（ADR）と auto-memory `feedback_*.md` のみに記録される。

外部発信（SNS運用等）や複数PJの横断ネタ抽出を目的に、Notion 側の「判断ログDB」に判断を集約したいユースケースがある（下流 PJ の SNS 運用ケース）。

### ユースケース

- 下流PJのClaude Codeセッションで出た**設計判断・方針判断**を、Notion判断ログDBに自動蓄積
- Notion側で**複数PJ横断**の判断一覧をダッシュボード化
- 別リポが判断ログDBを**SNSネタ源**として利用（外部発信用途のセカンダリ活用）
- `/close-chat` のタイミングで同期するので、開発者の手間はゼロ

### 既存の `NOTION_ENABLED=true` との関係

`NOTION_ENABLED` は既に Notion Tasks DB 連携のフラグとして使われている。今回は用途が異なる（タスクではなく判断の蓄積）ため、別フラグとして設ける。

## 検討内容

### 集約方式の選択肢

| # | 方式 | メリット | デメリット |
|---|------|---------|-----------|
| 1 | Pull型（集約リポが各PJを走査） | 中央集権 | 各PJのローカル構成に依存 |
| 2 | Push型（各PJが集約先に送る） | リアルタイム性 | 全PJにMCP接続必要 |
| 3 | **Hybrid（採用）**：各PJの `/close-chat` → Notion判断ログDB | 既存Notion運用に乗る | PJ側の改修必要 |
| 4 | Read-only集約（集約側が定期スキャン） | 拾いこぼし対策 | タイムラグ |

### フラグ設計の選択肢

| 選択肢 | 説明 |
|--------|------|
| 既存 `NOTION_ENABLED` を流用 | シンプルだが、用途が混在（Tasks DB / 判断ログDB） |
| **`NOTION_JUDGMENT_SYNC` を新設（採用）** | 用途ごとにON/OFF可。既存 `NOTION_ENABLED` を壊さない |

## 決定

### 1. Project Configuration に設定追加

`CLAUDE.md` の Project Configuration セクションに以下を追加する:

```yaml
NOTION_JUDGMENT_SYNC: false        # true: /close-chat 実行時にNotion判断ログDBへ同期
NOTION_JUDGMENT_DB_URL: ""         # 同期先 Notion 判断ログDB の URL
```

> **URL の配置先**: 公開判断ログDBなら `CLAUDE.md`（Git管理）に書いてよい。private DB の場合は `CLAUDE.local.md`（Git非管理）に移すこと。同期先URLをコミットに含めたくない下流PJ向けの運用ガイドライン。

### 2. `/close-chat` スキルに Step 6.5 を追加

`NOTION_JUDGMENT_SYNC=true` のときのみ実行されるステップを追加する:

> **実装時の注記**: 本 ADR 初稿では「Step 5.5」と記載していたが、実ファイルの Step 5.5 が既に「CHANGELOG 整合性チェック」で占有されていたため、実装では **Step 6.5** として挿入した（外部タスクDB同期の Step 6 の直後、同じ Layer 2 オプション層）。

- セッション中に出た判断（ADR化されなかった軽微な判断を含む）を Notion判断ログDB に同期
- 記録項目（Notion側 `⚖️ 判断ログ` スキーマに準拠）:
  - タイトル（判断の短い要約）
  - カテゴリ（multi_select: 設計判断 / 方針 / 技術選定 / 表現トーン / ブランディング / プロダクト / その他）
  - コンテキスト（セッションの話題）
  - 判断（select: OK / NG / 保留）
  - 判断理由
  - 学び
  - 日時

### 3. rules ファイルに同期プロトコル追記

`.claude/rules/task-management.md` に判断ログ同期プロトコルを追記する（`NOTION_ENABLED=true` の task-db 連携と同じレイヤーで扱う）。

独立ファイル化は、rules/ のファイル数を増やさないために見送る。

## 理由

- **既存 `NOTION_ENABLED` パターンと整合**: `task-management.md` で既に確立している「Notion連携オプション」の延長
- **下流PJ全体で汎用的**: 脳tion / SNS運用に限らず、「複数PJの判断を横断集約したい」全ユースケースに適用可能
- **Push型が最も低コスト**: セッション文脈を最も正確に把握しているのは Claude Code 自身。`/close-chat` の延長として同期するのが運用負荷ゼロ
- **フラグ分離**: Tasks DB 連携と用途が違うため、`NOTION_ENABLED` を汎用化するより独立フラグで疎結合に保つ

## 影響

### sidekick 本体

- `CLAUDE.md` Project Configuration: 設定追加（デフォルト false）
- `.claude/skills/close-chat/SKILL.md`: Step 5.5 追加
- `.claude/rules/task-management.md`: 判断ログ同期プロトコル追記
- `CHANGELOG.md`: 次バージョンとして記載（v0.7.0 想定）

### claude-code-sidekick（OSS版）

- `/sync-oss` 実行で自動的に反映される
- リリース温度感: **Standard**（ADR-0009 参照。致命的ではない機能追加）

### 下流PJへの影響

- デフォルト false なので既存PJへの影響なし
- オプトインで利用開始（`NOTION_JUDGMENT_SYNC=true` + `NOTION_JUDGMENT_DB_URL` 設定）
- `/adopt-sidekick-update` で選択的取り込み可能

### 関連ADR

- **ADR-0004「Git を Source of Truth、外部DBはオプション」** と一見矛盾するように見えるが、本機能は**補助的な集約**であり、設計判断の Source of Truth は引き続き ADR（`docs/decisions/`）。Notion判断ログDBはセカンダリ用途（SNSネタ化等）として位置づける
- **ADR-0007「thinking.md を入れ替え可能な思考OSとして位置づけ」** と親和的。個人の思考OS（thinking.md）と、プロジェクト横断の判断ログ（Notion）を分離する方向性と整合

## 残論点

### v0.7 実装スコープ（対応済み）

4. **冪等性**: 同じ判断を複数回送信しないためのキー設計
   - **採用**: 日時（ISO8601）+ タイトル先頭32文字のハッシュを決定的キーとし、auto-memory `project_judgment_sync_<YYYYMMDD>.md` に記録。次回 `/close-chat` 実行時に同キーの判断を重複判定する

### v0.7 スコープ外（次バージョン以降で再議論）

1. **カテゴリ体系の統一**: sidekick 側のADRカテゴリ（あれば）と Notion判断ログDBのカテゴリを揃えるかどうか
   → 今回は Notion スキーマ定義に従う。ADR カテゴリとの対応は下流PJごとの運用で吸収
2. **SNSネタ候補フラグ**: Notion判断ログDB に専用プロパティを追加するか、カテゴリだけで判定するか
   → 今回はスキーマ変更しない。カテゴリ「プロダクト」「ブランディング」等で代替
3. **差分同期 vs 全件同期**: 前回同期時点以降の判断のみを送るか、セッション内の全判断を送るか
   → 今回はセッション内で発生した判断を全件送信（冪等性キーで重複回避）。差分同期は将来の最適化

## 参考

- 関連: ADR-0004、ADR-0007
- 同期先 Notion 判断ログDB の URL は各 PJ の `CLAUDE.md` Project Configuration の `NOTION_JUDGMENT_DB_URL` で設定する（個別の URL はリポに含めない）
