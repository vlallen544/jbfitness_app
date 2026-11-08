const hints: Record<string, string> = {
  ENOTFOUND: "Database hostname could not be resolved. Check DATABASE_URL against Supabase Connect > Session pooler.",
  EAI_AGAIN: "Database DNS lookup failed temporarily. Check the hostname and retry.",
  ENETUNREACH: "Database network is unreachable. For an IPv4 host, use Supabase Session pooler on port 5432.",
  EHOSTUNREACH: "Database host is unreachable. Check the session-pooler endpoint and network restrictions.",
  ECONNREFUSED: "Database connection was refused. Check the host, port and whether the project is running.",
  ETIMEDOUT: "Database connection timed out. Check the endpoint, project status and network restrictions.",
  ECONNRESET: "Database connection was reset. Check project status, TLS configuration and retry.",
  "28P01": "Database password authentication failed. Check the database password, URL encoding and pooler username.",
  "28000": "Database authentication was rejected. Check the session-pooler username, password and TLS requirements.",
  "3D000": "The configured database does not exist. Check the database name in DATABASE_URL.",
  "42501": "The database role lacks permission for the migration. Use the dedicated demo database owner's connection.",
  "53300": "Database connection limit reached. Check pooler capacity and other connected applications.",
  "57P03": "Database is not accepting connections yet. Check that the Supabase project is active and retry.",
  SELF_SIGNED_CERT_IN_CHAIN: "Database TLS certificate is not trusted. Configure the provider CA via sslrootcert; keep verification enabled.",
  DEPTH_ZERO_SELF_SIGNED_CERT: "Database TLS certificate is not trusted. Configure the provider CA via sslrootcert; keep verification enabled.",
  UNABLE_TO_VERIFY_LEAF_SIGNATURE: "Database TLS certificate chain could not be verified. Configure the provider CA via sslrootcert.",
  UNABLE_TO_GET_ISSUER_CERT_LOCALLY: "Database TLS issuer is not trusted. Configure the provider CA via sslrootcert.",
  ERR_TLS_CERT_ALTNAME_INVALID: "Database TLS hostname does not match its certificate. Use the exact provider hostname.",
  CERT_HAS_EXPIRED: "Database TLS certificate has expired. Check the configured CA and provider certificate.",
};

// Never log raw driver messages: they can include credentials, URLs or SQL data.
export function migrationFailure(error: unknown, stage: string): string {
  const pending: unknown[] = [error];
  const seen = new Set<unknown>();
  while (pending.length && seen.size < 20) {
    const item = pending.shift();
    if (!item || typeof item !== "object" || seen.has(item)) continue;
    seen.add(item);
    const value = item as { code?: unknown; cause?: unknown; errors?: unknown[]; message?: unknown };
    if (typeof value.code === "string" && Object.hasOwn(hints, value.code))
      return `Migration failed during ${stage} [${value.code}]. ${hints[value.code]}`;
    if (value.message === "Connection terminated due to connection timeout")
      return `Migration failed during ${stage} [CONNECTION_TIMEOUT]. Check DATABASE_URL, project status and network restrictions.`;
    pending.push(value.cause);
    if (Array.isArray(value.errors)) pending.push(...value.errors.slice(0, 20));
  }
  return `Migration failed during ${stage}. Check the database connection settings and migration state. Driver details were omitted to protect credentials.`;
}
