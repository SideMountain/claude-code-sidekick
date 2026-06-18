'use client';
// H3: データ取得 segment の error 境界（部分的失敗を UI で受ける）。
export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <div role="alert">
      <p>Posts の読み込みに失敗しました。</p>
      <button onClick={reset}>再試行</button>
    </div>
  );
}
