import Link from "next/link";
import { Logo } from "./Logo";
import { SITE_CONFIG } from "@/lib/constants";
import { Mail, Heart, ShieldCheck } from "lucide-react";

export function Footer() {
  const currentYear = new Date().getFullYear();

  return (
    <footer className="relative bg-[#06050A] border-t border-purple-500/15 pt-16 pb-12 overflow-hidden">
      {/* Background subtle glow */}
      <div className="glow-blob-purple -bottom-40 left-1/2 -translate-x-1/2 opacity-30" />

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-10 mb-12">
          {/* Col 1: Brand & Tagline */}
          <div className="md:col-span-1 space-y-4">
            <Logo size="md" />
            <p className="text-sm text-gray-400 leading-relaxed font-[family-name:var(--font-outfit)]">
              {SITE_CONFIG.tagline}
            </p>
            <div className="flex items-center gap-3 pt-2">
              <a
                href={SITE_CONFIG.githubRepo}
                target="_blank"
                rel="noopener noreferrer"
                className="p-2 rounded-xl bg-purple-500/10 hover:bg-purple-500/20 text-purple-300 hover:text-white border border-purple-500/20 transition-colors"
                aria-label="GitHub Repository"
              >
                <svg className="w-4 h-4 fill-current" viewBox="0 0 24 24">
                  <path fillRule="evenodd" clipRule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.53 1.032 1.53 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z" />
                </svg>
              </a>
              <a
                href={`mailto:${SITE_CONFIG.supportEmail}`}
                className="p-2 rounded-xl bg-purple-500/10 hover:bg-purple-500/20 text-purple-300 hover:text-white border border-purple-500/20 transition-colors"
                aria-label="Support Email"
              >
                <Mail className="w-4 h-4" />
              </a>
            </div>
          </div>

          {/* Col 2: Product */}
          <div>
            <h4 className="text-xs font-bold uppercase tracking-wider text-purple-300/80 mb-4 font-[family-name:var(--font-space-grotesk)]">
              Product
            </h4>
            <ul className="space-y-2.5 text-sm text-gray-400">
              <li>
                <Link
                  href="/download"
                  className="hover:text-white transition-colors"
                >
                  Download for macOS
                </Link>
              </li>
              <li>
                <Link
                  href="/download"
                  className="hover:text-white transition-colors"
                >
                  Download for Windows
                </Link>
              </li>
              <li>
                <Link
                  href="/pricing"
                  className="hover:text-white transition-colors"
                >
                  Pricing & Plans
                </Link>
              </li>
              <li>
                <Link
                  href="/changelog"
                  className="hover:text-white transition-colors"
                >
                  Changelog & Releases
                </Link>
              </li>
            </ul>
          </div>

          {/* Col 3: Resources & Support */}
          <div>
            <h4 className="text-xs font-bold uppercase tracking-wider text-purple-300/80 mb-4 font-[family-name:var(--font-space-grotesk)]">
              Resources
            </h4>
            <ul className="space-y-2.5 text-sm text-gray-400">
              <li>
                <Link href="/faq" className="hover:text-white transition-colors">
                  Frequently Asked Questions
                </Link>
              </li>
              <li>
                <a
                  href={`mailto:${SITE_CONFIG.supportEmail}`}
                  className="hover:text-white transition-colors flex items-center gap-1.5"
                >
                  <span>Email Support</span>
                </a>
              </li>
              <li>
                <a
                  href={`${SITE_CONFIG.githubRepo}/issues`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="hover:text-white transition-colors"
                >
                  Report an Issue
                </a>
              </li>
            </ul>
          </div>

          {/* Col 4: Legal */}
          <div>
            <h4 className="text-xs font-bold uppercase tracking-wider text-purple-300/80 mb-4 font-[family-name:var(--font-space-grotesk)]">
              Legal & Trust
            </h4>
            <ul className="space-y-2.5 text-sm text-gray-400">
              <li>
                <Link
                  href="/terms"
                  className="hover:text-white transition-colors"
                >
                  Terms of Service
                </Link>
              </li>
              <li>
                <Link
                  href="/privacy"
                  className="hover:text-white transition-colors flex items-center gap-1.5"
                >
                  <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Privacy Policy</span>
                </Link>
              </li>
              <li>
                <Link
                  href="/refund"
                  className="hover:text-white transition-colors"
                >
                  Refund Policy (14 Days)
                </Link>
              </li>
            </ul>
          </div>
        </div>

        {/* Bottom Bar */}
        <div className="pt-8 border-t border-white/5 flex flex-col sm:flex-row items-center justify-between gap-4 text-xs text-gray-500">
          <div className="flex items-center gap-2">
            <span>© {currentYear} {SITE_CONFIG.name}. All rights reserved.</span>
            <span>•</span>
            <span className="inline-flex items-center gap-1">
              Made with <Heart className="w-3 h-3 text-rose-500 fill-rose-500" /> by{" "}
              <a
                href={SITE_CONFIG.creatorGithub}
                target="_blank"
                rel="noopener noreferrer"
                className="text-purple-300 hover:text-white underline underline-offset-4 decoration-purple-400/50 hover:decoration-purple-200 font-medium transition-all"
              >
                {SITE_CONFIG.creatorName}
              </a>
            </span>
          </div>
        </div>
      </div>
    </footer>
  );
}
