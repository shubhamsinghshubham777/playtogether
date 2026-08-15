export const SITE_CONFIG = {
  name: "PlayTogether",
  tagline: "Synchronized media playback with real-time video, chat, and reactions.",
  description:
    "Watch local video files or YouTube in perfect sync with your friends. Features private rooms, low-latency facecams, animated emoji reactions, and persistent room memory.",
  url: process.env.NEXT_PUBLIC_SITE_URL || "https://playtogether.app",
  supportEmail: "support@playtogether.app",
  githubRepo: "https://github.com/shubhamsinghshubham777/playtogether",
  creatorName: "Shubham Singh",
};

export const PRICING_TIERS = {
  guest: {
    name: "Guest",
    badge: "No Account Needed",
    price: {
      usdMonthly: "$0",
      usdAnnual: "$0",
      inrMonthly: "₹0",
      inrAnnual: "₹0",
    },
    description: "Instant access for casual watching. Join with a 6-digit room code in seconds.",
    cta: "Download App",
    ctaLink: "/download",
    limits: {
      rooms: 1,
      members: 4,
      sessionMinutes: 60,
      totalSessionMinutes: 60,
      av: "None (text chat only)",
      reactions: "Standard (8 emoji)",
      dormantHours: 0,
      persistent: false,
    },
    features: [
      "1 active room at a time",
      "Up to 4 participants per room",
      "60-minute session duration",
      "Local files & YouTube sync",
      "Real-time chat & basic reactions",
      "No sign-up or credit card required",
    ],
  },
  free: {
    name: "Free",
    badge: "Most Popular",
    price: {
      usdMonthly: "$0",
      usdAnnual: "$0",
      inrMonthly: "₹0",
      inrAnnual: "₹0",
    },
    description: "Ideal for friend groups and watch parties with voice chat and extended sessions.",
    cta: "Get Started Free",
    ctaLink: "/download",
    limits: {
      rooms: 4,
      members: 8,
      sessionMinutes: 240,
      totalSessionMinutes: 240,
      av: "Voice only",
      reactions: "Standard (8 emoji)",
      dormantHours: 24,
      persistent: false,
    },
    features: [
      "4 active rooms per host",
      "Up to 8 participants per room",
      "4-hour session duration",
      "Low-latency Voice facecams (LiveKit)",
      "1 free 60-min extension per session",
      "Rooms nap for 24h (resumes where you left off)",
      "Syncs account across all your devices",
    ],
  },
  premium: {
    name: "Premium",
    badge: "Ultimate Experience",
    price: {
      usdMonthly: "$3.99",
      usdAnnual: "$29.99",
      usdAnnualMonthlyEquivalent: "$2.49",
      inrMonthly: "₹149",
      inrAnnual: "₹999",
      inrAnnualMonthlyEquivalent: "₹83",
      savingsPct: "37%",
    },
    description: "The complete theater experience. Video facecams, 16 members, 24h rooms, and persistent memory.",
    cta: "Upgrade to Premium",
    ctaLink: "/pricing",
    limits: {
      rooms: 20,
      members: 16,
      sessionMinutes: 240,
      totalSessionMinutes: 1440,
      av: "Voice + Video",
      reactions: "Extended (24 animated emoji)",
      dormantHours: 24,
      persistent: true,
    },
    features: [
      "20 persistent rooms with custom names",
      "Up to 16 participants per room",
      "Up to 24-hour continuous sessions",
      "HD Video + Voice facecams (LiveKit)",
      "24 animated Lottie reaction emoji",
      "Persistent rooms (never expire or delete)",
      "Room host privileges denormalized to all joiners",
      "Priority customer support",
    ],
  },
};

export const FAQ_ITEMS = [
  {
    category: "General",
    questions: [
      {
        q: "What is PlayTogether?",
        a: "PlayTogether is a dedicated desktop application (macOS & Windows) for synchronizing media playback across devices. Whether you are watching a local MP4/MKV movie or a YouTube video, play, pause, seek, and audio tracks stay synchronized down to the millisecond across all participants."
      },
      {
        q: "What platforms does PlayTogether support?",
        a: "PlayTogether currently supports macOS (12.0+) and Windows (10 and 11). Both platforms offer native hardware acceleration and seamless window management."
      },
      {
        q: "Do I need an account to use PlayTogether?",
        a: "No! You can use PlayTogether as a Guest without creating an account. Guests can create 60-minute rooms with up to 4 members. To get 4-hour rooms, voice chat, and room memory, simply sign in with your Google account for free."
      },
      {
        q: "Is PlayTogether free?",
        a: "Yes! Both Guest and Free tiers are 100% free with no ads or tracking. We offer a paid Premium tier for extended sessions, 16-member rooms, and video facecams."
      }
    ]
  },
  {
    category: "Rooms & Sync",
    questions: [
      {
        q: "How do I create and join a room?",
        a: "Launch PlayTogether and click 'Create Room'. You will receive a unique 6-character room code (e.g. `X7K9P2`) and an invite link (`playtogether://join/X7K9P2`). Share it with your friends, and they can join instantly by entering the code or clicking the link."
      },
      {
        q: "What media formats are supported?",
        a: "PlayTogether supports all major local video containers and codecs via libmpv / media_kit (MP4, MKV, AVI, WEBM, MOV, etc.) along with direct YouTube video playback."
      },
      {
        q: "Does PlayTogether stream or upload my video files to other people?",
        a: "No! PlayTogether does not upload, stream, or re-encode your files. Each participant plays their own local copy of the file on their machine. PlayTogether synchronizes only the playback state (timestamps, play/pause, seeks) and chat over private Supabase Realtime channels."
      },
      {
        q: "What happens when a room expires?",
        a: "On Free and Guest tiers, rooms have a session timer. When a room expires, chat is cleared and the room naps (dormant state) for 24 hours on Free tier, allowing the host to reopen the file and resume right where everyone left off. Premium rooms never expire."
      }
    ]
  },
  {
    category: "Premium & Subscriptions",
    questions: [
      {
        q: "What do I get with PlayTogether Premium?",
        a: "Premium unlocks 20 persistent rooms, up to 16 participants per room, up to 24-hour sessions, crystal-clear HD Video facecams, 24 animated emoji reactions, and persistent room memory."
      },
      {
        q: "How do I subscribe?",
        a: "Sign in with your Google account on our website (/auth), visit the Pricing page (/pricing), and select either Monthly or Annual billing. Payments are processed securely via Paddle (Credit/Debit Cards, PayPal, Apple Pay, Google Pay, and UPI in India)."
      },
      {
        q: "Can I cancel anytime?",
        a: "Yes! You can cancel your subscription at any time directly from your Account page. Your Premium benefits will remain active until the end of your current billing period."
      },
      {
        q: "What is your refund policy?",
        a: "We offer a 14-day, no-questions-asked refund policy for first-time purchases. Simply reach out to support@playtogether.app with your account email."
      },
      {
        q: "I paid on the website but my desktop app still shows Free. What should I do?",
        a: "Ensure you are signed in with the same Google account in both the desktop app and on the website. Subscriptions update automatically within seconds. If it doesn't appear, restart the app or click 'Sync profile' in your app profile screen."
      }
    ]
  },
  {
    category: "Privacy & Security",
    questions: [
      {
        q: "What data does PlayTogether collect?",
        a: "We collect only your basic Google profile (email and display name) for authentication. We never collect or store your file names, full file paths, or file contents. Chat messages are session-scoped and automatically wiped when rooms close."
      },
      {
        q: "Can I opt out of analytics?",
        a: "Yes. In the desktop app under Profile → 'Share usage data', you can toggle anonymous product analytics off at any time. Crash reporting via Sentry carries no personal data."
      },
      {
        q: "Are voice and video facecams recorded?",
        a: "Never. Voice and video streams are transmitted end-to-end via LiveKit WebRTC relays and are never recorded or stored on any server."
      }
    ]
  }
];
