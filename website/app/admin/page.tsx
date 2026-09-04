import { headers } from "next/headers";
import { notFound, redirect } from "next/navigation";
import { isAuthorizedLocalAccess } from "@/lib/admin-guard";

export const dynamic = "force-dynamic";

export default async function AdminRedirectPage() {
  const reqHeaders = await headers();
  if (!isAuthorizedLocalAccess({ headers: reqHeaders })) {
    notFound();
  }

  redirect("/internal/metrics");
}
