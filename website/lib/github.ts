export interface GitHubAsset {
  id: number;
  name: string;
  browser_download_url: string;
  size: number;
  content_type: string;
  download_count: number;
}

export interface GitHubRelease {
  id: number;
  tag_name: string;
  name: string;
  body: string;
  published_at: string;
  prerelease: boolean;
  draft: boolean;
  html_url: string;
  assets: GitHubAsset[];
}

export interface ReleaseAssetInfo {
  version: string;
  tagName: string;
  name: string;
  publishedAt: string;
  macDownloadUrl: string;
  macSizeMb: number;
  winDownloadUrl: string;
  winSizeMb: number;
  body: string;
  htmlUrl: string;
}

const FALLBACK_VERSION = "0.11.0";
const FALLBACK_RELEASE: ReleaseAssetInfo = {
  version: FALLBACK_VERSION,
  tagName: `v${FALLBACK_VERSION}`,
  name: `v${FALLBACK_VERSION}`,
  publishedAt: "2026-08-11T12:00:00Z",
  macDownloadUrl: `https://github.com/shubhamsinghshubham777/playtogether/releases/download/v${FALLBACK_VERSION}/PlayTogether-${FALLBACK_VERSION}-macOS.dmg`,
  macSizeMb: 42.5,
  winDownloadUrl: `https://github.com/shubhamsinghshubham777/playtogether/releases/download/v${FALLBACK_VERSION}/PlayTogether-${FALLBACK_VERSION}-Windows.exe`,
  winSizeMb: 38.2,
  body: "### What's New\n- Synchronized local media & YouTube player enhancements\n- Real-time Voice & Video facecams\n- Persistent room memory and tier entitlements\n- Desktop fullscreen & keyboard shortcuts (F, Esc, Space)",
  htmlUrl: `https://github.com/shubhamsinghshubham777/playtogether/releases/tag/v${FALLBACK_VERSION}`,
};

export async function getLatestRelease(): Promise<ReleaseAssetInfo> {
  try {
    const res = await fetch(
      "https://api.github.com/repos/shubhamsinghshubham777/playtogether/releases/latest",
      {
        next: { revalidate: 3600 },
        headers: {
          Accept: "application/vnd.github.v3+json",
          "User-Agent": "PlayTogether-Website",
        },
      }
    );

    if (!res.ok) {
      return FALLBACK_RELEASE;
    }

    const data: GitHubRelease = await res.json();
    const rawVersion = data.name || data.tag_name;
    const cleanVersion = rawVersion.replace(/^v/, "").replace(/_\d+$/, "");
    const titleName = data.name ? data.name.replace(/_\d+$/, "") : `v${cleanVersion}`;

    const macAsset = data.assets.find(
      (a) => a.name.endsWith(".dmg") || a.name.includes("macOS")
    );
    const winAsset = data.assets.find(
      (a) => a.name.endsWith(".exe") || a.name.includes("Windows")
    );

    return {
      version: cleanVersion,
      tagName: data.tag_name,
      name: titleName,
      publishedAt: data.published_at,
      macDownloadUrl:
        macAsset?.browser_download_url ||
        `https://github.com/shubhamsinghshubham777/playtogether/releases/download/${data.tag_name}/PlayTogether-${cleanVersion}-macOS.dmg`,
      macSizeMb: macAsset ? Math.round((macAsset.size / (1024 * 1024)) * 10) / 10 : 42.5,
      winDownloadUrl:
        winAsset?.browser_download_url ||
        `https://github.com/shubhamsinghshubham777/playtogether/releases/download/${data.tag_name}/PlayTogether-${cleanVersion}-Windows.exe`,
      winSizeMb: winAsset ? Math.round((winAsset.size / (1024 * 1024)) * 10) / 10 : 38.2,
      body: data.body || "",
      htmlUrl: data.html_url,
    };
  } catch (error) {
    console.error("Error fetching latest GitHub release:", error);
    return FALLBACK_RELEASE;
  }
}

export async function getAllReleases(): Promise<GitHubRelease[]> {
  try {
    const res = await fetch(
      "https://api.github.com/repos/shubhamsinghshubham777/playtogether/releases?per_page=30",
      {
        next: { revalidate: 3600 },
        headers: {
          Accept: "application/vnd.github.v3+json",
          "User-Agent": "PlayTogether-Website",
        },
      }
    );

    if (!res.ok) {
      return [];
    }

    const releases: GitHubRelease[] = await res.json();
    // Filter out drafts and pre-releases as specified in the plan
    return releases.filter((r) => !r.draft && !r.prerelease);
  } catch (error) {
    console.error("Error fetching all releases:", error);
    return [];
  }
}
