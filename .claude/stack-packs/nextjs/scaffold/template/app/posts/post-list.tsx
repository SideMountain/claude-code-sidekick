'use client';
// S3: 'use client' は許可。client leaf は props でデータを受け取る（自前 fetch しない）。
import { useState } from 'react';
import { deletePostAction } from './actions';

type Post = { id: string; title: string; body: string };

export function PostList({ posts }: { posts: Post[] }) {
  const [pending, setPending] = useState<string | null>(null);
  return (
    <ul>
      {posts.map((p) => (
        <li key={p.id}>
          <strong>{p.title}</strong>
          <button
            disabled={pending === p.id}
            onClick={async () => {
              setPending(p.id);
              await deletePostAction(p.id);
              setPending(null);
            }}
          >
            削除
          </button>
        </li>
      ))}
    </ul>
  );
}
