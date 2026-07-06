# ADR-0026: AUTO_MODE 既定値と「physically blocks」表現の整合

## ステータス

採用（2026-07-04）。オーナー裁定（既定 `false` + 無人モードの明示 opt-in を導線に組み込む）+ 実機検証済。前提 ADR-0025（budget-gate）。

## 背景

`guard-bash.sh` は `AUTO_MODE="${SIDEKICK_AUTO:-true}"` を既定とし、Guard 3（`git push`）と Guard 8（`gh pr merge`・ベースが保護ブランチでない場合）を **auto-approve** する。一方 CLAUDE.md の HARD ルールは以下を「必ず確認」と定める:

- **H7**: git push → 必ずユーザー確認
- **H8**: PR 作成・マージ・クローズ → 必ずユーザー確認

つまり認知層（HARD ルール文言）は「確認必須」を約束するが、強制層は既定 `SIDEKICK_AUTO=true` により feature ブランチの push / 非保護ベースへの merge を無確認で通す。ハードブロック（保護ブランチ push・`.env` 変更・`rm -rf`・`prisma db push`・PRD DB・保護ブランチ Edit）は AUTO_MODE と無関係に常に deny されるため安全だが、H7/H8 の「確認」は既定では実質 advisory になっている。

README は「Physically blocks dangerous ops like `rm -rf` or pushing to main」と述べる。この文言自体はハードブロック対象（`rm -rf` / 保護ブランチ push）に限定されており正確だが、H7/H8 の「必ず確認」との併記が「あらゆる push/PR も物理的に止まる」という誤読を生みうる。

## 論点

1. 対話セッションで feature push / 非保護 merge を既定で無確認にしてよいか（H7/H8 との乖離）。
2. 「physically blocks」「必ず確認」という表現を実態（保護ブランチ等のみ物理ブロック・それ以外は AUTO 既定で自律）に合わせるか。
3. 無人モード（`--dangerouslySkipPermissions` / `/auto-implement` / cron）と対話モードで既定を変えるべきか。

## 選択肢

- **A. 既定を false にする（`${SIDEKICK_AUTO:-false}`）+ 明示 opt-in**: 対話時は H7/H8 どおり feature push / merge も確認。無人運用は従来どおり `SIDEKICK_AUTO=true` を明示（README の起動例は既にこの形）。安全側だが、明示を忘れると無人ループが確認待ちで止まる摩擦がある。
- **B. 文言を実態に合わせる（現状の既定 true を維持）**: HARD ルール文言と README を「物理ブロックは保護ブランチ・`.env`・破壊操作・PRD DB に限る／feature push・非保護 merge は AUTO 既定で自律（`SIDEKICK_AUTO=false` で確認に切替可）」と正直化。H7/H8 に「AUTO_MODE=false 時に適用」の条件を明記。
- **C. モード別既定（B を基盤に A を無人時へ限定適用）**: 文言は B で正直化しつつ、無人モードは「明示 opt-in（`SIDEKICK_AUTO=true`）でのみ全自律」を規約として固定する。対話モードの既定は運用実績に合わせて選ぶ。

## 決定

**A: 既定を `false` にする（`${SIDEKICK_AUTO:-false}`）+ 無人モードの明示 opt-in を「導線」に組み込む。** オーナー原則「わかりやすい初期設定 / 分かりにくいオプションは dead 機能化する」に基づく。

1. **対話セッションの既定 = 確認**（`SIDEKICK_AUTO` 未設定 → `false`）。feature push / 非保護 merge も H7/H8 どおり確認する。これが利用者にとって最も直感的で安全。
2. **無人モードは明示 opt-in だが「隠しトグル」にしない** — `/auto-implement` の無人起動コマンド（`SIDEKICK_AUTO=true claude --dangerouslySkipPermissions`）が opt-in を内包する。opt-in は「無人モードに入ること」に結合しており、利用者が別途 env var を探して設定する必要はない（dead 機能化の回避）。
3. **導線**: `/setup` が「無人稼働を使うか」を提示し、使う場合の起動コマンドを案内する。

ハードブロック（保護ブランチ・`.env`・`rm -rf`・`prisma db push`・PRD DB・保護ブランチ Edit）は AUTO_MODE 非依存で常に deny されるため、既定反転後も不可逆操作の保護は不変。既定 `false` により H7/H8「必ず確認」が既定で真になり、認知層（HARD 文言）と強制層（guard 既定）が一致する。

却下: **B（既定 true 維持 + 文言正直化）** — 表現の齟齬は消せるが、対話ユーザーが「push が無確認で通る」既定を予期しにくく、安全側でない。**C（モード別既定）** — 対話既定を運用実績で選ぶ余地を残すが、既定を 1 つに固定した方が利用者の予測可能性が高い。

## 検証手順（既定を変える場合の必須ゲート）

1. `guard-bash.sh` に模擬入力（`git push origin feature/x` / `gh pr merge <非保護>` / 保護ブランチ push）を、`SIDEKICK_AUTO` 未設定・`=true`・`=false` の 3 通りで流し、期待どおり allow(auto) / allow(warning) / deny になることを確認。
2. 保護ブランチ push・`.env` 変更・`rm -rf` は `SIDEKICK_AUTO` の値に関わらず deny のままであることを確認（ハードブロックの独立性）。
3. `/auto-implement` を `SIDEKICK_AUTO` 未指定で起動したとき、feature push が確認待ち（または規約どおり停止）になり、明示 opt-in 時のみ全自律で PR まで進むことを確認。

### 検証結果（2026-07-04・実機）

`guard-bash.sh` に模擬入力を 3 設定で流した結果:

| 入力 | `SIDEKICK_AUTO` 未設定 | `=true` | `=false` |
|---|---|---|---|
| `git push origin feature/x`（非保護） | allow + **WARNING（確認）** | allow + AUTO | allow + WARNING |
| `git push origin main`（保護） | **deny** | **deny** | **deny** |
| `rm -rf /tmp/x`（ハードブロック） | **deny** | **deny** | **deny** |

既定（未設定）で feature push が WARNING（確認）に変わり H7/H8 が既定で効くこと、保護ブランチ push・`rm -rf` が AUTO_MODE 非依存で deny のままであることを確認した。

## 影響

- `guard-bash.sh`: `${SIDEKICK_AUTO:-true}` → `${SIDEKICK_AUTO:-false}`（1 行）。
- `/auto-implement`: 全自律には `SIDEKICK_AUTO=true` が必須である旨を前提条件に明記（既定 `false` のため未指定だと push / PR で確認待ちになる）。無人起動例は既にこの形。
- `/setup`: 「無人稼働を使うか」の導線で opt-in の起動コマンドを案内する。
- 既定 `false` により H7/H8「必ず確認」が既定で真になり、README の防御モデル説明との齟齬が解消する。
