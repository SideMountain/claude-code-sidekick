# 現在状態オラクル — 時点根拠 ≠ 現在の真

> `context-economy.md` §1（受信側 contract）/ §5（機械判定クラス）から参照される遅延ロード doc。**常駐しない**。
> グレード: GUIDE（ただし「migration / DDL / スキーマ変更前の参照先現存確認」は **HARD** — `context-economy.md` ヘッダの例外宣言が正）。

## 原則（規範の正は `context-economy.md` §5）

存在・生存・有効性の主張は、履歴や伝聞ではなく、現在状態に対して当該セッションで走らせた決定的オラクルで裏付ける。「時点根拠 ≠ 現在の真」「subagent の報告は伝聞であり親が一次確認するまで確証に昇格させない」「migration / DDL / スキーマ変更前の参照先現存確認は無条件」の規範文は `context-economy.md` §5（および §1 受信側 contract）を単一ソースとする。以下は本 doc 固有の詳細（事故経路・オラクル対応表・トリガ表・実装パターン）。

## 典型的な事故経路（防ぐ対象）

1. 調査 subagent が過去 migration の CREATE POLICY / CREATE TABLE 定義を発見し「存在する」と報告する
2. 親がその報告を確証として採用する（後続 migration の DROP と突き合わせない）
3. 撤去済みオブジェクトへの DDL を新 migration に書く → 適用時に失敗（トランザクション rollback で実害ゼロでも、broken migration がブランチに載る）

ハーネスの守備範囲の非対称も背景にある: Claude Code の Edit ツールは**編集対象ファイル自体**の鮮度を強制する（Read 前の編集不可・Read 後の変更で失敗）が、**DB スキーマとファイル横断の結合には相当する強制層がない**。前者の穴は本 doc の DB オラクル、後者は typecheck / テストが埋める。

## オラクル対応表（主張のクラス × 決定的オラクル）

| 主張のクラス | 決定的オラクル | ダメな根拠 |
|---|---|---|
| テーブル / カラムが現存する | 実 DB 照会（information_schema）・schema dump・ORM 生成型 | 過去 migration の CREATE 定義 |
| RLS ポリシー / トリガ / 関数が現存する | 実 DB 照会（pg_policies 等）・履歴の機械 replay 結果 | 過去 migration の CREATE POLICY |
| シンボルが存在する | working tree への grep / LSP / typecheck | 過去 diff・subagent の引用・数十ターン前に読んだ記憶 |
| コードが生きている（死にコードでない） | 呼び出し元 grep（参照数）・unused 検出（knip / ts-prune 等）・coverage | 「定義がある」だけの存在確認 |
| その定義が効いている（重複 / shadow でない） | 全リポ grep で定義を全数列挙 → import 経路確認、最終は実行 | 最初に見つけた 1 定義 |
| 動く | 実行（テスト・実走）= ladder L3 実行 arbiter | 読み判定・仕様書引用 |

## 変更クラス別トリガ表（負荷最小化）

重い検査は「真実が変わる場所」にだけ置き、他は導出物への相乗りで済ませる。平常時の追加負荷は実質ゼロにする。

| 変更クラス | DB 検査 | 使うオラクル | 追加負荷 |
|---|---|---|---|
| migration ファイルを Write | **必須（フル）** | ephemeral replay（CI は paths フィルタで migration 変更時のみ発火） | migration PR のみ |
| スキーマ定義源（schema.prisma 等） | 必須（migration 生成元） | 同上 + 生成型の regen-diff 検査 | 同上 |
| 生成型 / 生成 schema の手編集 | 検査でなく**禁止**（生成物の手編集は drift 製造） | — | ゼロ |
| Repository / DAO（型付き ORM 経由） | 不要 | 生成型 + typecheck が肩代わり（下記チェーン） | ゼロ（既存ゲート相乗り） |
| Repository 内の raw SQL | 軽検査 | SQL 中の relation 名を生成 schema に grep | grep 1 回 |
| DTO / Service / Controller | 不要 | DB と直接結合しない。Entity 経由の結合は typecheck が伝播 | ゼロ |
| docs / UI / 純ロジック | 不要 | — | ゼロ |

### 生成型チェーン（コード側の検査を typecheck に相乗りさせる構造）

```
DB の真実 = migration 履歴
    ↓ CI ephemeral replay（migration 変更時のみ発火）← 唯一の「重い」検査
生成型 / 生成 schema（regen-diff を CI で強制 = 生成腐り防止）
    ↓ typecheck(既存の PR ゲート・追加コストなし)
Repository → Service → Controller → DTO
```

チェーンが健全なら「撤去済みテーブルを参照するコード」は型エラーで落ちるため、コード修正時に実 DB を見る必要はない。チェーンで捕まらない残余は 2 つ: **raw SQL**（型を素通り → grep 検査 or 型付きクライアント経由の規約で入口を塞ぐ）と **DB 内オブジェクト（RLS・トリガ・関数）**（型に出ない → migration 側のフル検査でのみ捕まる。だから 1 行目が必須）。

## 実装パターン（下流 PJ 向け・3 層）

| 層 | 実装 | 役割 |
|---|---|---|
| 強制 | CI: PR ごとに ephemeral DB へ migration 全 replay（paths フィルタで migration 変更時のみ） | broken migration をマージ前に止める。モデル・エージェントの行儀に依存しない最終ゲート |
| 検知 | migration Write 時、参照 relation を生成 schema / 生成型と突き合わせる advisory hook | 書いた瞬間のフィードバック（CI より速い） |
| 認知 | `context-economy.md` §1 受信側 contract / §5 機械判定クラス | 委任・受信の作法 |

drift 検知（「migration は全部当たっているか」）は、**履歴由来の導出状態（replay 結果）と実環境への照会を突き合わせる**ことで機械判定できる（migration の適用台帳＋schema diff）。単独のオラクルに「確実」を求めず、履歴由来を正・実環境を照合用とする。

## 委任時の作法（subagent への出し方・受け取り方）

- **機械判定可能な事実は委任タスクから外す**: 現存・型・参照数は自前のオラクルで確定し、subagent には判断が要る調査（設計妥当性・影響分析）だけを scoped に渡す（objective + 出力形式 + 境界を明示）。
- **報告必須項目を「存在するか」でなく導出済み現在状態ベースにする**: 「現在状態オラクル（実照会 / 生成型 / working tree）で確認したか、それとも履歴時点の定義か」を報告に含めさせる。死にコード検疫には「参照元は何箇所か（0 なら死にコード疑い）」。
- 受信側: load-bearing な事実は伝聞のまま採用しない（`context-economy.md` §1 受信側 contract）。
