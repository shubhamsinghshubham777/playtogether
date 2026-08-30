import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      {
        protocol: "https",
        hostname: "lh3.googleusercontent.com",
      },
      {
        protocol: "https",
        hostname: "avatars.githubusercontent.com",
      },
    ],
  },
  async redirects() {
    return [
      {
        source: "/premium",
        destination: "/pricing",
        permanent: true,
      },
      {
        source: "/features",
        destination: "/#features",
        permanent: false,
      },
    ];
  },
};

export default nextConfig;
