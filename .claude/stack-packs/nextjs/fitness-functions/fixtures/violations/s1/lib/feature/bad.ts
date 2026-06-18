// 違反: lib が @/app を import（依存方向違反）。
import { appState } from '@/app/state';
export const x = appState;
