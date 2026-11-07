// HTTP の口（Hono）。テストから時計と APNs の送り口を差し替えられるよう createApp で作る。
import { Hono, type Context } from "hono";
import type { AppEnv, Env } from "./env.ts";
import { requireAccess } from "./auth.ts";
import {
  addItem,
  archiveItem,
  getBoard,
  isKind,
  normalizePushToken,
  normalizeTitle,
  parseMembers,
  setResetTime,
  sweepNeeds,
  toggleItem,
  upsertDevice,
} from "./board.ts";
import { parseResetTime } from "./day.ts";
import { apnsConfig, httpApnsSender, type ApnsSender } from "./apns.ts";
import { notifyChange } from "./push.ts";

export interface AppDeps {
  now: () => Date;
  /** APNs の送り口。null なら送らない（鍵が無いとき） */
  sender: (env: Env) => ApnsSender | null;
  debounceMs?: number;
  sleep?: (ms: number) => Promise<void>;
}

export const defaultDeps: AppDeps = {
  now: () => new Date(),
  sender: (env) => {
    const cfg = apnsConfig(env);
    return cfg ? httpApnsSender(cfg) : null;
  },
};

type C = Context<AppEnv>;

function err(c: C, status: 400 | 404, error: string) {
  return c.json({ error }, status);
}

async function body(c: C): Promise<Record<string, unknown>> {
  try {
    const v = await c.req.json();
    return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

function parseId(raw: string): number | null {
  return /^[1-9]\d{0,15}$/.test(raw) ? Number(raw) : null;
}

export function createApp(deps: AppDeps = defaultDeps) {
  const app = new Hono<AppEnv>();

  app.use("*", async (c, next) => {
    await next();
    c.header("X-Content-Type-Options", "nosniff");
    c.header("Cache-Control", "no-store");
  });
  app.use("/api/*", requireAccess);

  const members = (c: C) => parseMembers(c.env.MEMBERS);
  const memberOf = (c: C, v: unknown): string | null =>
    typeof v === "string" && members(c).includes(v.trim()) ? v.trim() : null;

  /** 変更のあと: 最新の一覧を返し、裏でウィジェット用プッシュを送る */
  async function changed(c: C, status: 200 | 201 = 200) {
    const now = deps.now();
    c.executionCtx.waitUntil(
      notifyChange(c.env.DB, { sender: deps.sender(c.env), debounceMs: deps.debounceMs, sleep: deps.sleep }).catch((e) =>
        console.warn("push: " + (e instanceof Error ? e.name : "error")),
      ),
    );
    return c.json(await getBoard(c.env.DB, now, members(c)), status);
  }

  app.get("/api/board", async (c) => c.json(await getBoard(c.env.DB, deps.now(), members(c))));

  app.post("/api/items", async (c) => {
    const b = await body(c);
    if (!isKind(b.kind)) return err(c, 400, "bad_kind");
    const title = normalizeTitle(b.title);
    if (!title) return err(c, 400, "bad_title");
    const by = memberOf(c, b.by);
    if (!by) return err(c, 400, "bad_member");
    const now = deps.now();
    await sweepNeeds(c.env.DB, now);
    await addItem(c.env.DB, b.kind, title, by, now);
    return changed(c, 201);
  });

  app.post("/api/items/:id/toggle", async (c) => {
    const id = parseId(c.req.param("id"));
    if (id === null) return err(c, 404, "not_found");
    const by = memberOf(c, (await body(c)).by);
    if (!by) return err(c, 400, "bad_member");
    const now = deps.now();
    const r = await toggleItem(c.env.DB, id, by, now);
    if (r === "not_found") return err(c, 404, "not_found");
    await sweepNeeds(c.env.DB, now);
    return changed(c);
  });

  app.delete("/api/items/:id", async (c) => {
    const id = parseId(c.req.param("id"));
    if (id === null || !(await archiveItem(c.env.DB, id, deps.now()))) return err(c, 404, "not_found");
    return changed(c);
  });

  app.put("/api/settings/reset-time", async (c) => {
    const v = (await body(c)).reset_time;
    if (parseResetTime(v) === null) return err(c, 400, "bad_reset_time");
    await setResetTime(c.env.DB, v as string);
    return changed(c);
  });

  app.put("/api/devices", async (c) => {
    const b = await body(c);
    const token = normalizePushToken(b.push_token);
    if (!token) return err(c, 400, "bad_push_token");
    const member = memberOf(c, b.member);
    if (!member) return err(c, 400, "bad_member");
    await upsertDevice(c.env.DB, token, member, deps.now());
    return c.json({ ok: true });
  });

  app.notFound((c) => c.json({ error: "not_found" }, 404));
  app.onError((e, c) => {
    console.error("error: " + (e instanceof Error ? e.name : "unknown"));
    return c.json({ error: "internal" }, 500);
  });

  return app;
}
