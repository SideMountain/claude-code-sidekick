# ADR-0026: AUTO_MODE 既定値と「physically blocks」表現の整合

## ステータス

Proposed（2026-07-02、草案）。既定値の変更はコードの振る舞いと無人運用のストーリーに影響するため、人間の承認と実機検証を経てから確定する。

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

## 推奨

**B を基盤に、無人（`/auto-implement`・cron）時のみ A 相当の明示 opt-in を要求する（= C）**。根拠:

- ハードブロックが不可逆操作（保護ブランチ・`.env`・`rm -rf`・PRD DB）を AUTO_MODE 非依存で常に止めるため、feature push / 非保護 merge の auto-approve は「可逆・低リスク」に限定されている。「PRs while you sleep」の価値はこの既定に依存する。
- 残る乖離は主に **表現** の問題。H7/H8 と README を実態に合わせれば、認知層と強制層は一致する。
- 無人運用は既に `SIDEKICK_AUTO=true` を明示する起動例で案内されており、これを規約として固定すれば「意図せぬ全自律」を防げる。

## 検証手順（既定を変える場合の必須ゲート）

1. `guard-bash.sh` に模擬入力（`git push origin feature/x` / `gh pr merge <非保護>` / 保護ブランチ push）を、`SIDEKICK_AUTO` 未設定・`=true`・`=false` の 3 通りで流し、期待どおり allow(auto) / allow(warning) / deny になることを確認。
2. 保護ブランチ push・`.env` 変更・`rm -rf` は `SIDEKICK_AUTO` の値に関わらず deny のままであることを確認（ハードブロックの独立性）。
3. `/auto-implement` を `SIDEKICK_AUTO` 未指定で起動したとき、feature push が確認待ち（または規約どおり停止）になり、明示 opt-in 時のみ全自律で PR まで進むことを確認。

## 影響

- 文言のみ（推奨 B 部分）は低リスクで先行可能: CLAUDE.md H7/H8 に AUTO_MODE 条件を明記、README の防御モデル説明を「物理ブロック対象」と「AUTO 既定で自律」に分離。
- 既定値の変更（A/C のコード部分）は `guard-bash.sh` の 1 行（`${SIDEKICK_AUTO:-...}`）と `/auto-implement` の opt-in 規約に影響。上記検証を満たし人間が承認した時点で別 ADR で確定する。
- 本 ADR 段階ではコードは変更しない。
