'use server';
// S4: 内部 mutation は module-level Server Action（actions.ts に集約・named export）。
//     コンポーネント内 inline 'use server' クロージャは禁止（grep 列挙性を壊すため）。
import { revalidatePath } from 'next/cache';
import { requireSession } from '@/lib/auth/session';
import { createPostSchema } from '@/lib/validations/post';
import { createPost, softDeletePost } from '@/lib/posts/mutations';

export type CreatePostState = { error: string | null };

// useActionState 形式（(prevState, formData) => state）。エラーは UI に返す（discard しない）。
export async function createPostAction(
  _prev: CreatePostState,
  formData: FormData,
): Promise<CreatePostState> {
  const auth = await requireSession();
  if (!auth.ok) return { error: 'ログインが必要です' };

  const parsed = createPostSchema.safeParse({
    title: formData.get('title'),
    body: formData.get('body'),
  });
  if (!parsed.success) return { error: '入力が不正です' };

  await createPost(auth.ctx, parsed.data);
  revalidatePath('/posts');
  return { error: null };
}

export async function deletePostAction(id: string) {
  const auth = await requireSession();
  if (!auth.ok) return { error: 'unauthorized' };
  await softDeletePost(auth.ctx, id);
  revalidatePath('/posts');
}
