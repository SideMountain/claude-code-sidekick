#!/usr/bin/env node
/**
 * /news-slack 実行スクリプト
 *
 * usage:
 *   node run.mjs <channel_id> [--bootstrap] [--force] [--dry-run]
 *
 * env:
 *   SLACK_BOT_TOKEN      必須。xoxb- で始まる Bot token
 *   NEWS_SLACK_TITLE     任意。通知タイトル（未設定ならリポジトリ名から生成）
 *   NEWS_SLACK_API_PATH  任意。API 変更として数えるパス（既定: src/app/api/）
 *
 * 動作:
 *   1. origin/main を fetch
 *   2. channel から bot 自身の最新メッセージを読み、last_commit fingerprint を抽出
 *   3. fingerprint なし or --bootstrap → bootstrap post して終了
 *   4. fingerprint == 現 HEAD → skip
 *   5. それ以外 → diff サマリを生成して post
 *
 * exit code:
 *   0 = posted / 0 = skipped / 0 = bootstrap
 *   1 = error
 */

import { WebClient } from "@slack/web-api";
import { execSync } from "node:child_process";
import { basename } from "node:path";

const argv = process.argv.slice(2);
const channelId = argv.find((a) => /^C[A-Z0-9]+$/.test(a));
const bootstrapFlag = argv.includes("--bootstrap");
const forceFlag = argv.includes("--force");
const dryRun = argv.includes("--dry-run");

if (!channelId) {
  console.error("ERROR: channel_id (e.g., C0XXXXXXXXX) required");
  process.exit(1);
}
if (!process.env.SLACK_BOT_TOKEN) {
  console.error("ERROR: SLACK_BOT_TOKEN env var required");
  process.exit(1);
}

const slack = new WebClient(process.env.SLACK_BOT_TOKEN);
const sh = (cmd) => execSync(cmd, { encoding: "utf8" }).trim();

const TITLE =
  process.env.NEWS_SLACK_TITLE ||
  `${basename(sh("git rev-parse --show-toplevel"))} 更新通知`;
const API_PATH = process.env.NEWS_SLACK_API_PATH || "src/app/api/";

// Step 1: fetch + HEAD
sh("git fetch origin main 2>&1");
const NEW_HEAD = sh("git rev-parse origin/main");
const SHORT_HEAD = sh("git rev-parse --short=7 origin/main");

// Step 2: identify bot, read channel
const auth = await slack.auth.test();
const BOT_USER_ID = auth.user_id;
const history = await slack.conversations.history({ channel: channelId, limit: 30 });
const myMsgs = (history.messages || []).filter((m) => m.user === BOT_USER_ID);
const fingerprint = myMsgs
  .map((m) => (m.text || "").match(/last_commit=([0-9a-f]{7,40})/))
  .find(Boolean);
const LAST_SHA = fingerprint?.[1] || null;

// Step 3: bootstrap
const needBootstrap =
  bootstrapFlag ||
  !LAST_SHA ||
  (() => {
    try {
      sh(`git cat-file -e ${LAST_SHA}`);
      return false;
    } catch {
      return true; // last_commit referenced but unknown locally
    }
  })();

if (needBootstrap) {
  const msg =
    `:rocket: ${TITLE}（トラッキング開始）\n\n` +
    `本日からこのチャンネルに変更通知を投稿します。\n` +
    `日次で main ブランチの直近変更をサマリして投稿します。\n\n` +
    `_(internal: last_commit=${SHORT_HEAD})_`;
  if (dryRun) {
    console.log("[dry-run] BOOTSTRAP would post:");
    console.log(msg);
  } else {
    await slack.chat.postMessage({ channel: channelId, text: msg, mrkdwn: true });
  }
  console.log(JSON.stringify({ status: "bootstrap", channel: channelId, last_commit: SHORT_HEAD }));
  process.exit(0);
}

// Step 4: diff judgment
if (LAST_SHA === NEW_HEAD.slice(0, LAST_SHA.length) && !forceFlag) {
  console.log(JSON.stringify({ status: "skipped", reason: "no_diff", last_commit: SHORT_HEAD }));
  process.exit(0);
}

// Step 5: collect changes
const commits = sh(`git log ${LAST_SHA}..${NEW_HEAD} --no-merges --pretty=format:%s`).split("\n").filter(Boolean);
const merges = sh(`git log ${LAST_SHA}..${NEW_HEAD} --merges --pretty=format:%s`).split("\n").filter(Boolean);

// release/stg 同期 PR は除外
const realPRs = merges.filter((m) => !/Merge pull request #\d+ from .*\/release\/stg$/.test(m));

// migrations/ を含むパス全般（supabase/migrations・prisma/migrations・migrations/）
const dbFiles = sh(`git diff --name-only ${LAST_SHA}..${NEW_HEAD} -- '*migrations/*'`).split("\n").filter(Boolean);
const apiFiles = sh(`git diff --name-only ${LAST_SHA}..${NEW_HEAD} -- '${API_PATH}'`).split("\n").filter(Boolean);

// Step 6: classify
const summarize = (subject) => subject.replace(/^[a-z]+(\([^)]+\))?:\s*/, "").trim();
const feat = commits.filter((c) => /^feat[\(:]/.test(c)).map(summarize);
const fix = commits.filter((c) => /^(fix|refactor|perf)[\(:]/.test(c)).map(summarize);

const lines = [`:rocket: ${TITLE}`, ""];
lines.push(`前回からの変更: ${commits.length}件のコミット / ${realPRs.length}件のPRマージ`, "");
if (feat.length) {
  lines.push(":new: 新機能:");
  feat.slice(0, 30).forEach((s) => lines.push(`- ${s}`));
  lines.push("");
}
if (fix.length) {
  lines.push(":wrench: 修正・改善:");
  fix.slice(0, 30).forEach((s) => lines.push(`- ${s}`));
  lines.push("");
}
if (commits.length > 30) {
  lines.push(`_他 ${commits.length - 30} 件は省略_`, "");
}
if (dbFiles.length) {
  lines.push(`:floppy_disk: DB変更: あり (${dbFiles.length}件のmigration)`);
}
if (apiFiles.length) {
  lines.push(`:electric_plug: API変更: あり (${apiFiles.length}ファイル)`);
}
if (dbFiles.length || apiFiles.length) lines.push("");
lines.push(`詳細は Claude Code で /news を実行`);
lines.push("");
lines.push(`_(internal: last_commit=${SHORT_HEAD})_`);

const message = lines.join("\n");

// Step 7: post
if (dryRun) {
  console.log("[dry-run] DIFF would post:");
  console.log(message);
} else {
  await slack.chat.postMessage({ channel: channelId, text: message, mrkdwn: true });
}
console.log(
  JSON.stringify({
    status: "posted",
    channel: channelId,
    last_commit: SHORT_HEAD,
    commit_count: commits.length,
    pr_count: realPRs.length,
  }),
);
