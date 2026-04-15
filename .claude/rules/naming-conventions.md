---
paths:
  - "src/**"
  - "lib/**"
  - "app/**"
---

# Naming Conventions

## LANGUAGE=typescript の場合

| 対象 | 規則 | 例 |
|------|------|-----|
| 変数・関数 | `camelCase` | `getUserName` |
| 型・インターフェース | `PascalCase` | `UserProfile` |
| コンポーネントファイル | `PascalCase.tsx` | `Button.tsx` |
| その他のファイル | `kebab-case` | `user-service.ts` |
| ディレクトリ | `kebab-case` | `user-profile/` |
| 定数 | `SCREAMING_SNAKE_CASE` | `MAX_RETRY_COUNT` |
| 未使用引数 | `_` プレフィックス | `_unused` |

## LANGUAGE=python の場合

| 対象 | 規則 | 例 |
|------|------|-----|
| 変数・関数 | `snake_case` | `get_user_name` |
| クラス | `PascalCase` | `UserProfile` |
| ファイル | `snake_case` | `user_service.py` |
| 定数 | `SCREAMING_SNAKE_CASE` | `MAX_RETRY_COUNT` |

## 共通

- 変数名・関数名は**英語（ASCII）**で書く。日本語ローマ字は使わない
- コメントは日本語OK