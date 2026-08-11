import { NextResponse } from "next/server";
import { getLatestRelease } from "@/lib/github";

export async function GET() {
  try {
    const release = await getLatestRelease();
    return NextResponse.json(release);
  } catch (error) {
    console.error("Latest release API route error:", error);
    return NextResponse.json(
      { error: "Failed to fetch latest release" },
      { status: 500 }
    );
  }
}
