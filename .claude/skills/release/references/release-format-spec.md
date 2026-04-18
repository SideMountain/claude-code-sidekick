# Release Format Specification

`/release` スキルの Step 6（GitHub Release 作成）で使うフォーマット規約の詳細。
ADR-0009 で定義した温度感伝達方式（title prefix + body banner）の具体仕様。

---

## Title フォーマット

| 温度感 | Title パターン |
|---|---|
| Critical | `⚠️ [CRITICAL] vX.Y.Z — {要約}` |
| Standard | `vX.Y.Z — {要約}` |
| Enhancement | `[ENHANCEMENT] vX.Y.Z — {要約}` |

要約は30文字以内を目安とする。キャッチーで「何が入ったリリースか」が伝わるようにする。

---

## Body Banner（冒頭表示）

Title prefix と一致した severity のバナーを body 冒頭に配置する。

### Critical

```markdown
> ⚠️ **CRITICAL**: このリリースはセキュリティ / 致命的バグ修正を含みます。
> 下流 PJ は **即取り込み推奨** です。取り込みを遅延する場合、影響範囲を
> 別途確認してください。
```

### Standard

（banner なし。通常の Highlights から開始）

### Enhancement

```markdown
> 💡 **ENHANCEMENT**: このリリースは opt-in な改善を含みます。
> 下流 PJ は状況に応じて取り込み判断してください。
```

---

## Body 必須セクション

以下のセクションは必ず含める。順序もこの通り。

```markdown
{banner}

## Highlights

{人間が書く。このリリースの意図・ユーザー体験への影響、1-3段落}

## Changes

### Added
- {CHANGELOG から転記}

### Changed
- {同上}

### Removed
- {同上}

### Fixed
- {同上}

### Breaking Changes
- {同上。ない場合はセクションごと省略}

## 変更された設計判断 (ADR)

{/release スキル Step 3 で機械生成。手で書かない}

- **新規**: ADR-XXXX タイトル
- **改訂**: ADR-XXXX タイトル

該当なしの場合は「なし」と明記。

## 変更された rules

{機械生成}

- **新規**: rules/xxx.md
- **更新**: rules/yyy.md

## 変更された skills

{機械生成}

- **新規**: /skill-a
- **更新**: /skill-b
- **削除**: /skill-c

---

**Full Changelog**: https://github.com/{owner}/{repo}/compare/vX.Y.Z-1...vX.Y.Z
```

---

## CHANGELOG.md フォーマット

### Intro セクション

CHANGELOG.md の冒頭に以下の説明を含める:

```markdown
# Changelog

sidekick のリリース履歴。セマンティックバージョニングに従う。
バージョンは git tag + GitHub Releases で管理する。

各PJは `CLAUDE.md` Project Configuration の `SIDEKICK_VERSION` で取り込み済み
バージョンを管理し、`/inventory` で GitHub Releases API 経由で未適用の更新を検知する。

## リリース温度感

各リリースは3段階の温度感に分類される:

- **[CRITICAL]** (`⚠️`): セキュリティ / 致命的バグ修正。即取り込み推奨
- **(No prefix)**: Standard — 通常の機能追加・修正（デフォルト）
- **[ENHANCEMENT]** (`💡`): opt-in な改善。後回し可

GitHub Release の title prefix と body 冒頭 banner に明示される。
```

### エントリの書式

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- 新機能 1
- 新機能 2

### Changed
- 既存機能の変更

### Removed
- 削除されたもの

### Fixed
- 修正されたバグ

### Breaking Changes
- 下流 PJ に影響する破壊的変更
```

---

## 温度感の判定基準

### Critical に該当する例

- セッション停止を伴うバグ（stop hook 無限ループ等）
- セキュリティホール（認証バイパス、情報漏洩等）
- データ喪失リスク（.env 保護失敗、DB マイグレーションバグ等）
- hooks のガード無効化（安全機構の破綻）

### Standard に該当する例

- 新スキル追加、既存スキル改修
- 通常のバグ修正
- README / ドキュメント更新（機能的変更を伴う）
- 設計判断の改訂（ADR 追加・改訂）

### Enhancement に該当する例

- ドキュメントの微改善（タイポ修正、誤解を招く表現の修正）
- 既存機能のマイナーな利便性向上
- 下流 PJ にとって opt-in な拡張（使わなくても従来通り動く）

迷ったら上位の severity（Critical > Standard > Enhancement）を選ぶのが安全。
