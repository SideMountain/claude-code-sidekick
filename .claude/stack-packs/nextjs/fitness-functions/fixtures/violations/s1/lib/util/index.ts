// 違反: barrel（re-export 集約 index）。public entry でないのに集約している。
export * from './helpers';
export { foo } from './foo';
