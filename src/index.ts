import "dotenv/config";
import { fetchDailyChallenge, pickCandidateSolutions } from "./leetcodeApi.js";
import { userStatus, submit, waitForVerdict } from "./submitApi.js";

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

export type BotRunResult = {
  success: boolean;
  logs: string[];
};

export async function runBot(write: (line: string) => void = console.log): Promise<BotRunResult> {
  const logs: string[] = [];
  const log = (line: string) => {
    logs.push(line);
    write(line);
  };
  const cookies = {
    LEETCODE_SESSION: requireEnv("LEETCODE_SESSION"),
    csrftoken: requireEnv("LEETCODE_CSRFTOKEN"),
  };

  log("→ Checking auth…");
  const status = await userStatus(cookies);
  if (!status.isSignedIn) throw new Error("Not signed in — LEETCODE_SESSION/csrftoken invalid or expired");
  log(`  logged in as ${status.username} ✓`);

  log("→ Fetching today's Daily Challenge…");
  const daily = await fetchDailyChallenge();
  log(`  ${daily.date} · ${daily.title} · ${daily.url}`);

  log("→ Ranking community solutions…");
  const candidates = await pickCandidateSolutions(daily.slug, 4);
  log(`  ${candidates.length} candidate(s) queued`);

  const failures: { title: string; lang: string; reason: string }[] = [];

  for (let i = 0; i < candidates.length; i++) {
    const { code, lang, source } = candidates[i];
    log(`\n→ Attempt ${i + 1}/${candidates.length}: "${source.title}" · ${lang} · ${source.votes} votes (${code.split("\n").length} lines)`);

    const { submission_id } = await submit(cookies, daily.slug, daily.questionId, code, lang);
    log(`  submission_id=${submission_id}`);
    const verdict = await waitForVerdict(cookies, submission_id);
    if (verdict.state !== "SUCCESS") {
      failures.push({ title: source.title, lang, reason: `unexpected state ${JSON.stringify(verdict)}` });
      continue;
    }

      log(`  ${verdict.status_msg} (${verdict.total_correct ?? "?"}/${verdict.total_testcases ?? "?"})`);

    if (verdict.status_msg === "Accepted") {
      log("\n✓ Streak maintained.");
      if (failures.length) log(`  (${failures.length} earlier attempt(s) failed)`);
      return { success: true, logs };
    }

    const reason = verdict.compile_error || verdict.runtime_error || verdict.status_msg;
    failures.push({ title: source.title, lang, reason: reason.split("\n")[0].slice(0, 200) });
  }

  log(`\n✗ All ${candidates.length} candidates failed:`);
  for (const f of failures) log(`  - "${f.title}" (${f.lang}): ${f.reason}`);
  return { success: false, logs };
}

if (process.argv[1]?.endsWith("index.ts")) {
  runBot().then((result) => {
    if (!result.success) process.exitCode = 1;
  }).catch((err) => {
    console.error(err);
    process.exitCode = 1;
  });
}
