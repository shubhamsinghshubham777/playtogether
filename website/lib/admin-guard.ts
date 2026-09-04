/**
 * Validates whether a request originates from an authorized local development
 * environment or carries a valid internal admin token.
 *
 * Open Source Security Invariant:
 * - In local development (NODE_ENV === "development" | "test"): Loopback hostnames
 *   (localhost, 127.0.0.1, etc.) are allowed automatically for frictionless local dev.
 * - In production (NODE_ENV === "production"): Because the repository is open source,
 *   header spoofing (e.g. fake Host or x-forwarded-for) must NEVER be trusted.
 *   Access in production STRICTLY requires a valid private INTERNAL_ADMIN_TOKEN.
 *   Without this token, the endpoint returns an immediate 404 Not Found.
 */
export function isAuthorizedLocalAccess(
  request: {
    headers: Headers;
    url?: string;
  },
  customEnv?: string
): boolean {
  const env = customEnv || process.env.NODE_ENV;
  const isDevOrTest = env === "development" || env === "test";

  // 1. Check for token authorization (e.g. ?token=... or x-admin-token header)
  const expectedToken =
    process.env.INTERNAL_ADMIN_TOKEN ||
    process.env.ADMIN_SECRET;

  if (expectedToken && expectedToken.trim().length > 0) {
    const headerToken = request.headers.get("x-admin-token");
    if (headerToken && headerToken === expectedToken) {
      return true;
    }

    if (request.url) {
      try {
        const urlObj = new URL(request.url);
        const queryToken = urlObj.searchParams.get("token");
        if (queryToken && queryToken === expectedToken) {
          return true;
        }
      } catch {
        // Ignore URL parsing errors
      }
    }
  }

  // 2. In production, unauthenticated requests are ALWAYS rejected (immune to header spoofing)
  if (!isDevOrTest) {
    return false;
  }

  // 3. In development & test: allow loopback hosts
  const host = request.headers.get("host")?.toLowerCase() || "";
  const hostname = host.split(":")[0];

  const isLoopbackHost =
    hostname === "localhost" ||
    hostname === "127.0.0.1" ||
    hostname === "0.0.0.0" ||
    hostname.endsWith(".localhost") ||
    hostname.endsWith(".local");

  return isLoopbackHost;
}
