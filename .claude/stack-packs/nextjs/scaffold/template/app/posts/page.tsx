// S3: server-first。初期データは Server Component で DAL から取得し、props で leaf に渡す。
//     useEffect + fetch('/api/*') で自分の初期データを取得しない。
// H3: Rendering baseline = 従来モデル。データ取得 segment なので error.tsx / loading.tsx を持つ。
import { redirect } from 'next/navigation';
import { requireSession } from '@/lib/auth/session';
import { listPostsForCompany } from '@/lib/posts/queries';
import { PostForm } from './post-form';
import { PostList } from './post-list';

export default async function PostsPage() {
  const auth = await requireSession();
  if (!auth.ok) redirect('/login');

  const posts = await listPostsForCompany(auth.ctx);

  return (
    <main>
      <h1>Posts</h1>
      <PostForm />
      <PostList posts={posts} />
    </main>
  );
}
