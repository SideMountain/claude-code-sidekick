// S7: request contract は named schema を単一ソースから export（schema + z.infer 型の両方）。
// route 内 `z.object` literal を避け、ここを import する。server で safeParse する。
import { z } from 'zod';

export const createPostSchema = z.object({
  title: z.string().min(1).max(200),
  body: z.string().min(1),
});
export type CreatePostInput = z.infer<typeof createPostSchema>;

export const listPostsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
export type ListPostsQuery = z.infer<typeof listPostsQuerySchema>;
