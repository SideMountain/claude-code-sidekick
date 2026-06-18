'use client';
// S3: 'use client' leaf。Server Action を useActionState で呼び、エラー state を UI に表示する
//     （form action の戻り値を捨てない）。自前 fetch はしない。
import { useActionState } from 'react';
import { createPostAction, type CreatePostState } from './actions';

const initialState: CreatePostState = { error: null };

export function PostForm() {
  const [state, formAction, pending] = useActionState(createPostAction, initialState);
  return (
    <form action={formAction}>
      <input name="title" placeholder="title" required />
      <textarea name="body" placeholder="body" required />
      <button type="submit" disabled={pending}>Create</button>
      {state.error && <p role="alert">{state.error}</p>}
    </form>
  );
}
