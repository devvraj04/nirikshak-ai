import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/proxy/:path*',
        destination: 'http://3.7.153.193:8080/:path*',
      },
    ];
  },
};

export default nextConfig;
