// Comprehensive Deno KV operations test
// Usage: DENO_KV_ACCESS_TOKEN=<token> deno run --allow-net --allow-env --unstable-kv test_all_operations.ts [url]

const KV_URL = Deno.args[0] || "http://localhost:4512";
const ACCESS_TOKEN =
  Deno.env.get("DENO_KV_ACCESS_TOKEN") || "test-access-token";
Deno.env.set("DENO_KV_ACCESS_TOKEN", ACCESS_TOKEN);

let passed = 0;
let failed = 0;

function assert(condition: boolean, msg: string) {
  if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

async function test(name: string, fn: (kv: Deno.Kv) => Promise<void>, kv: Deno.Kv) {
  try {
    await fn(kv);
    passed++;
    console.log(`  PASS: ${name}`);
  } catch (e) {
    failed++;
    console.log(`  FAIL: ${name} - ${(e as Error).message}`);
  }
}

async function run() {
  console.log(`Connecting to ${KV_URL} ...`);
  const kv = await Deno.openKv(KV_URL);
  console.log("Connected.\n");

  // --- SET / GET ---
  console.log("[set / get]");
  await test("set and get string", async (kv) => {
    await kv.set(["test", "string"], "hello");
    const r = await kv.get(["test", "string"]);
    assert(r.value === "hello", `expected "hello", got ${r.value}`);
  }, kv);

  await test("set and get number", async (kv) => {
    await kv.set(["test", "number"], 42);
    const r = await kv.get(["test", "number"]);
    assert(r.value === 42, `expected 42, got ${r.value}`);
  }, kv);

  await test("set and get boolean", async (kv) => {
    await kv.set(["test", "bool"], true);
    const r = await kv.get(["test", "bool"]);
    assert(r.value === true, `expected true, got ${r.value}`);
  }, kv);

  await test("set and get object", async (kv) => {
    const obj = { name: "deno", version: 2, tags: ["kv", "test"] };
    await kv.set(["test", "object"], obj);
    const r = await kv.get<typeof obj>(["test", "object"]);
    assert(r.value?.name === "deno", `object mismatch`);
    assert(r.value?.tags.length === 2, `array in object mismatch`);
  }, kv);

  await test("set and get Uint8Array", async (kv) => {
    const bytes = new Uint8Array([1, 2, 3, 4, 5]);
    await kv.set(["test", "bytes"], bytes);
    const r = await kv.get<Uint8Array>(["test", "bytes"]);
    assert(r.value instanceof Uint8Array, "not Uint8Array");
    assert(r.value!.length === 5, `length mismatch`);
  }, kv);

  await test("set and get bigint", async (kv) => {
    await kv.set(["test", "bigint"], 9007199254740993n);
    const r = await kv.get<bigint>(["test", "bigint"]);
    assert(r.value === 9007199254740993n, `bigint mismatch`);
  }, kv);

  await test("set and get null", async (kv) => {
    await kv.set(["test", "null"], null);
    const r = await kv.get(["test", "null"]);
    assert(r.value === null, `expected null, got ${r.value}`);
  }, kv);

  // --- GET non-existent key ---
  console.log("\n[get non-existent]");
  await test("get non-existent key returns null with versionstamp null", async (kv) => {
    const r = await kv.get(["does", "not", "exist", crypto.randomUUID()]);
    assert(r.value === null, `expected null`);
    assert(r.versionstamp === null, `expected null versionstamp`);
  }, kv);

  // --- DELETE ---
  console.log("\n[delete]");
  await test("delete removes key", async (kv) => {
    await kv.set(["test", "delete_me"], "bye");
    await kv.delete(["test", "delete_me"]);
    const r = await kv.get(["test", "delete_me"]);
    assert(r.value === null, `expected null after delete`);
  }, kv);

  // --- GET MANY ---
  console.log("\n[getMany]");
  await test("getMany returns multiple values", async (kv) => {
    await kv.set(["multi", "a"], 1);
    await kv.set(["multi", "b"], 2);
    await kv.set(["multi", "c"], 3);
    const results = await kv.getMany([["multi", "a"], ["multi", "b"], ["multi", "c"]]);
    assert(results.length === 3, `expected 3 results`);
    assert(results[0].value === 1, `first value mismatch`);
    assert(results[1].value === 2, `second value mismatch`);
    assert(results[2].value === 3, `third value mismatch`);
  }, kv);

  // --- LIST ---
  console.log("\n[list]");
  await test("list with prefix", async (kv) => {
    const prefix = crypto.randomUUID();
    await kv.set(["list", prefix, "a"], 1);
    await kv.set(["list", prefix, "b"], 2);
    await kv.set(["list", prefix, "c"], 3);
    const entries = [];
    for await (const entry of kv.list({ prefix: ["list", prefix] })) {
      entries.push(entry);
    }
    assert(entries.length === 3, `expected 3 entries, got ${entries.length}`);
  }, kv);

  await test("list with limit", async (kv) => {
    const prefix = crypto.randomUUID();
    for (let i = 0; i < 5; i++) {
      await kv.set(["limit", prefix, `item${i}`], i);
    }
    const entries = [];
    for await (const entry of kv.list({ prefix: ["limit", prefix] }, { limit: 2 })) {
      entries.push(entry);
    }
    assert(entries.length === 2, `expected 2 entries, got ${entries.length}`);
  }, kv);

  await test("list reverse", async (kv) => {
    const prefix = crypto.randomUUID();
    await kv.set(["rev", prefix, "a"], "first");
    await kv.set(["rev", prefix, "b"], "second");
    await kv.set(["rev", prefix, "c"], "third");
    const entries = [];
    for await (const entry of kv.list({ prefix: ["rev", prefix] }, { reverse: true })) {
      entries.push(entry);
    }
    assert(entries.length === 3, `expected 3`);
    assert(entries[0].value === "third", `expected reverse order`);
  }, kv);

  // --- ATOMIC OPERATIONS ---
  console.log("\n[atomic]");
  await test("atomic set multiple keys", async (kv) => {
    const result = await kv.atomic()
      .set(["atomic", "x"], 10)
      .set(["atomic", "y"], 20)
      .commit();
    assert(result.ok, "atomic commit failed");
    const rx = await kv.get(["atomic", "x"]);
    const ry = await kv.get(["atomic", "y"]);
    assert(rx.value === 10, "x mismatch");
    assert(ry.value === 20, "y mismatch");
  }, kv);

  await test("atomic check (optimistic concurrency) - success", async (kv) => {
    await kv.set(["atomic", "check"], "v1");
    const current = await kv.get(["atomic", "check"]);
    const result = await kv.atomic()
      .check(current)
      .set(["atomic", "check"], "v2")
      .commit();
    assert(result.ok, "atomic check commit should succeed");
    const r = await kv.get(["atomic", "check"]);
    assert(r.value === "v2", `expected v2`);
  }, kv);

  await test("atomic check (optimistic concurrency) - conflict", async (kv) => {
    await kv.set(["atomic", "conflict"], "v1");
    const stale = await kv.get(["atomic", "conflict"]);
    // Another write changes the versionstamp
    await kv.set(["atomic", "conflict"], "v2");
    const result = await kv.atomic()
      .check(stale)
      .set(["atomic", "conflict"], "v3")
      .commit();
    assert(!result.ok, "atomic check should fail on conflict");
    const r = await kv.get(["atomic", "conflict"]);
    assert(r.value === "v2", `expected v2, value should not have changed to v3`);
  }, kv);

  await test("atomic delete", async (kv) => {
    await kv.set(["atomic", "del"], "remove_me");
    const result = await kv.atomic()
      .delete(["atomic", "del"])
      .commit();
    assert(result.ok, "atomic delete commit failed");
    const r = await kv.get(["atomic", "del"]);
    assert(r.value === null, "expected null after atomic delete");
  }, kv);

  // --- SUM (atomic mutation) ---
  console.log("\n[atomic mutations]");
  await test("atomic sum mutation", async (kv) => {
    await kv.set(["counter", "sum"], new Deno.KvU64(10n));
    const result = await kv.atomic()
      .mutate({ type: "sum", key: ["counter", "sum"], value: new Deno.KvU64(5n) })
      .commit();
    assert(result.ok, "sum mutation failed");
    const r = await kv.get<Deno.KvU64>(["counter", "sum"]);
    assert(r.value!.value === 15n, `expected 15n, got ${r.value!.value}`);
  }, kv);

  await test("atomic min mutation", async (kv) => {
    await kv.set(["counter", "min"], new Deno.KvU64(10n));
    await kv.atomic()
      .mutate({ type: "min", key: ["counter", "min"], value: new Deno.KvU64(5n) })
      .commit();
    const r = await kv.get<Deno.KvU64>(["counter", "min"]);
    assert(r.value!.value === 5n, `expected 5n`);
  }, kv);

  await test("atomic max mutation", async (kv) => {
    await kv.set(["counter", "max"], new Deno.KvU64(10n));
    await kv.atomic()
      .mutate({ type: "max", key: ["counter", "max"], value: new Deno.KvU64(20n) })
      .commit();
    const r = await kv.get<Deno.KvU64>(["counter", "max"]);
    assert(r.value!.value === 20n, `expected 20n`);
  }, kv);

  // --- EXPIRATION (expireIn) ---
  console.log("\n[expireIn]");
  await test("set with expireIn", async (kv) => {
    await kv.set(["test", "expiring"], "temp", { expireIn: 60000 });
    const r = await kv.get(["test", "expiring"]);
    assert(r.value === "temp", "value should exist before expiry");
  }, kv);

  // --- KEY TYPES ---
  console.log("\n[key types]");
  await test("key with string parts", async (kv) => {
    await kv.set(["str", "key", "parts"], "ok");
    const r = await kv.get(["str", "key", "parts"]);
    assert(r.value === "ok", "string key parts failed");
  }, kv);

  await test("key with number parts", async (kv) => {
    await kv.set(["num", 1, 2, 3], "ok");
    const r = await kv.get(["num", 1, 2, 3]);
    assert(r.value === "ok", "number key parts failed");
  }, kv);

  await test("key with boolean parts", async (kv) => {
    await kv.set(["bool", true, false], "ok");
    const r = await kv.get(["bool", true, false]);
    assert(r.value === "ok", "boolean key parts failed");
  }, kv);

  await test("key with bigint parts", async (kv) => {
    await kv.set(["bigint", 999999999999999999n], "ok");
    const r = await kv.get(["bigint", 999999999999999999n]);
    assert(r.value === "ok", "bigint key parts failed");
  }, kv);

  await test("key with Uint8Array parts", async (kv) => {
    const keyPart = new Uint8Array([0xDE, 0xAD]);
    await kv.set(["bytes", keyPart], "ok");
    const r = await kv.get(["bytes", keyPart]);
    assert(r.value === "ok", "Uint8Array key parts failed");
  }, kv);

  // --- VERSIONSTAMP ---
  console.log("\n[versionstamp]");
  await test("versionstamp changes on update", async (kv) => {
    await kv.set(["vs", "track"], "v1");
    const r1 = await kv.get(["vs", "track"]);
    await kv.set(["vs", "track"], "v2");
    const r2 = await kv.get(["vs", "track"]);
    assert(r1.versionstamp !== r2.versionstamp, "versionstamp should change");
  }, kv);

  // --- WATCH ---
  console.log("\n[watch]");
  await test("watch detects changes", async (kv) => {
    const key = ["watch", crypto.randomUUID()];
    await kv.set(key, "initial");
    const stream = kv.watch<[string]>([key]);
    const reader = stream.getReader();

    // Read initial value
    const { value: initial } = await reader.read();
    assert(initial![0].value === "initial", "watch initial value mismatch");

    // Trigger a change
    await kv.set(key, "updated");
    const { value: updated } = await reader.read();
    assert(updated![0].value === "updated", "watch updated value mismatch");

    reader.releaseLock();
    stream.cancel();
  }, kv);

  // --- ENQUEUE / LISTEN (basic) ---
  console.log("\n[enqueue]");
  await test("enqueue message", async (kv) => {
    // Just test that enqueue doesn't throw - full listen requires a handler
    await kv.enqueue({ type: "test", data: "hello" });
  }, kv);

  // --- CLEANUP ---
  console.log("\n[cleanup]");
  const prefixes = [
    "test", "multi", "list", "limit", "rev", "atomic",
    "counter", "str", "num", "bool", "bigint", "bytes", "vs", "watch",
  ];
  for (const prefix of prefixes) {
    for await (const entry of kv.list({ prefix: [prefix] })) {
      await kv.delete(entry.key);
    }
  }
  console.log("  Cleaned up test keys.\n");

  kv.close();

  // --- SUMMARY ---
  console.log("=".repeat(40));
  console.log(`Results: ${passed} passed, ${failed} failed, ${passed + failed} total`);
  if (failed > 0) {
    Deno.exit(1);
  } else {
    console.log("All tests passed!");
  }
}

run();
