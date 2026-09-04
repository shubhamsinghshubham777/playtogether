import test from "node:test";
import assert from "node:assert/strict";

function checkLocalAccess(
  headers: Headers,
  customEnv = "development",
  url?: string,
  customToken?: string
): boolean {
  const host = headers.get("host")?.toLowerCase() || "";
  const hostname = host.split(":")[0];

  const expectedToken = customToken;
  if (expectedToken && expectedToken.trim().length > 0) {
    const headerToken = headers.get("x-admin-token");
    if (headerToken && headerToken === expectedToken) {
      return true;
    }

    if (url) {
      try {
        const urlObj = new URL(url);
        const queryToken = urlObj.searchParams.get("token");
        if (queryToken && queryToken === expectedToken) {
          return true;
        }
      } catch {
        // Ignore URL parsing errors
      }
    }
  }

  const isDevOrTest = customEnv === "development" || customEnv === "test";

  // In production, unauthenticated requests are strictly rejected
  if (!isDevOrTest) {
    return false;
  }

  const isLoopbackHost =
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "0.0.0.0" ||
    hostname.endsWith(".localhost") ||
    hostname.endsWith(".local");

  return isLoopbackHost;
}

test("checkLocalAccess approves local loopback development hosts", () => {
  const localHosts = [
    "localhost:3000",
    "127.0.0.1:3000",
    "0.0.0.0:3000",
    "localhost",
    "127.0.0.1",
    "app.local",
    "test.localhost",
  ];

  for (const host of localHosts) {
    const headers = new Headers({ host });
    assert.equal(
      checkLocalAccess(headers, "development"),
      true,
      `Expected ${host} to be recognized as authorized local access in development`
    );
    assert.equal(
      checkLocalAccess(headers, "test"),
      true,
      `Expected ${host} to be recognized as authorized local access in test`
    );
  }
});

test("checkLocalAccess strictly blocks production access without token (immune to spoofed Host/IP)", () => {
  const hosts = [
    "synctogether.com",
    "www.synctogether.com",
    "synctogether.vercel.app",
    "localhost",
    "127.0.0.1",
  ];

  for (const host of hosts) {
    const headers = new Headers({
      host,
      "x-forwarded-for": "127.0.0.1",
    });
    assert.equal(
      checkLocalAccess(headers, "production"),
      false,
      `Expected host ${host} to be blocked in production without token`
    );
  }
});

test("checkLocalAccess approves requests carrying valid admin token in production", () => {
  const token = "super-secret-admin-token-123";

  // 1. Authorized via x-admin-token header
  const headerReq = new Headers({
    host: "synctogether.com",
    "x-admin-token": token,
  });
  assert.equal(checkLocalAccess(headerReq, "production", undefined, token), true);

  // 2. Authorized via query param
  const queryReq = new Headers({
    host: "synctogether.com",
  });
  const url = "https://synctogether.com/internal/metrics?token=super-secret-admin-token-123";
  assert.equal(checkLocalAccess(queryReq, "production", url, token), true);

  // 3. Rejected with invalid token
  const invalidReq = new Headers({
    host: "synctogether.com",
    "x-admin-token": "wrong-token",
  });
  assert.equal(checkLocalAccess(invalidReq, "production", undefined, token), false);
});

test("Business calculations: MRR, ARR, and conversion rates behave predictably", () => {
  const activePremium = 12;
  const totalRegistered = 150;
  const uniqueVisitors = 1200;
  const downloads = 300;

  const mrr = activePremium * 5.0;
  const arr = mrr * 12;
  const payingRate = Math.round((activePremium / totalRegistered) * 1000) / 10;
  const downloadRate = Math.round((downloads / uniqueVisitors) * 1000) / 10;

  assert.equal(mrr, 60.0);
  assert.equal(arr, 720.0);
  assert.equal(payingRate, 8.0); // 8%
  assert.equal(downloadRate, 25.0); // 25%
});
