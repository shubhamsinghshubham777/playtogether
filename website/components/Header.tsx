"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "./Logo";
import { PTButton } from "./PTButton";
import { createClient } from "@/lib/supabase/client";
import { Menu, X, User as UserIcon, Sparkles, Download } from "lucide-react";
import type { User } from "@supabase/supabase-js";
import Image from "next/image";

export function Header() {
  const [user, setUser] = useState<User | null>(null);
  const [scrolled, setScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const pathname = usePathname();
  const supabase = createClient();

  useEffect(() => {
    async function getUser() {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      setUser(user);
    }
    getUser();

    const { data: authListener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setUser(session?.user ?? null);
      }
    );

    const handleScroll = () => {
      setScrolled(window.scrollY > 20);
    };
    window.addEventListener("scroll", handleScroll);

    return () => {
      authListener.subscription.unsubscribe();
      window.removeEventListener("scroll", handleScroll);
    };
  }, [supabase]);

  const navLinks = [
    { name: "Features", href: "/#features" },
    { name: "Pricing", href: "/pricing" },
    { name: "Download", href: "/download" },
    { name: "FAQ", href: "/faq" },
    { name: "Changelog", href: "/changelog" },
  ];

  return (
    <header
      className={`fixed top-0 inset-x-0 z-50 transition-all duration-300 ${
        scrolled
          ? "bg-[#0B0A14]/85 backdrop-blur-md border-b border-purple-500/10 shadow-lg shadow-black/40 py-3.5"
          : "bg-transparent py-5"
      }`}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 flex items-center justify-between">
        {/* Brand Logo */}
        <Logo />

        {/* Desktop Nav Links */}
        <nav className="hidden md:flex items-center gap-8">
          {navLinks.map((link) => {
            const isActive = pathname === link.href;
            return (
              <Link
                key={link.name}
                href={link.href}
                className={`text-sm font-medium transition-colors duration-200 ${
                  isActive
                    ? "text-[#C9B8FF] font-semibold"
                    : "text-gray-300 hover:text-white"
                }`}
              >
                {link.name}
              </Link>
            );
          })}
        </nav>

        {/* Desktop Actions / Auth State */}
        <div className="hidden md:flex items-center gap-4">
          {user ? (
            <div className="flex items-center gap-3">
              <Link
                href="/account"
                className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#161226]/80 hover:bg-[#201A38] border border-purple-400/20 hover:border-purple-400/40 transition-all duration-200 group"
              >
                {user.user_metadata?.avatar_url ? (
                  <Image
                    src={user.user_metadata.avatar_url}
                    alt={user.user_metadata?.full_name || "Profile"}
                    width={24}
                    height={24}
                    className="w-6 h-6 rounded-full border border-purple-400/30"
                  />
                ) : (
                  <div className="w-6 h-6 rounded-full bg-purple-600 flex items-center justify-center text-xs font-bold text-white">
                    {user.email?.charAt(0).toUpperCase() || "U"}
                  </div>
                )}
                <span className="text-xs font-medium text-purple-200 group-hover:text-white max-w-[120px] truncate">
                  {user.user_metadata?.full_name || user.email?.split("@")[0]}
                </span>
              </Link>
              <PTButton
                href="/pricing"
                variant="gold"
                size="sm"
                leftIcon={<Sparkles className="w-3.5 h-3.5" />}
              >
                Upgrade
              </PTButton>
            </div>
          ) : (
            <div className="flex items-center gap-3">
              <PTButton href="/auth" variant="ghost" size="sm">
                Sign In
              </PTButton>
              <PTButton
                href="/download"
                variant="primary"
                size="sm"
                leftIcon={<Download className="w-4 h-4" />}
              >
                Download
              </PTButton>
            </div>
          )}
        </div>

        {/* Mobile Menu Toggle Button */}
        <button
          onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          className="md:hidden p-2 rounded-xl bg-purple-500/10 border border-purple-500/20 text-purple-300 hover:text-white"
          aria-label="Toggle Navigation Menu"
        >
          {mobileMenuOpen ? (
            <X className="w-6 h-6" />
          ) : (
            <Menu className="w-6 h-6" />
          )}
        </button>
      </div>

      {/* Mobile Navigation Drawer */}
      {mobileMenuOpen && (
        <div className="md:hidden bg-[#0F0D1C]/95 backdrop-blur-2xl border-b border-purple-500/20 px-6 py-6 space-y-4 animate-in fade-in slide-in-from-top-4 duration-200 shadow-2xl">
          <nav className="flex flex-col space-y-3">
            {navLinks.map((link) => (
              <Link
                key={link.name}
                href={link.href}
                onClick={() => setMobileMenuOpen(false)}
                className="text-base font-medium text-gray-200 hover:text-[#C9B8FF] py-2 border-b border-white/5"
              >
                {link.name}
              </Link>
            ))}
          </nav>

          <div className="pt-4 border-t border-purple-500/20 flex flex-col gap-3">
            {user ? (
              <>
                <Link
                  href="/account"
                  onClick={() => setMobileMenuOpen(false)}
                  className="flex items-center gap-3 p-3 rounded-xl bg-[#161226] border border-purple-400/20"
                >
                  <UserIcon className="w-5 h-5 text-purple-400" />
                  <div className="flex flex-col">
                    <span className="text-sm font-semibold text-white">
                      {user.user_metadata?.full_name || "My Account"}
                    </span>
                    <span className="text-xs text-gray-400">{user.email}</span>
                  </div>
                </Link>
                <PTButton
                  href="/pricing"
                  variant="gold"
                  size="md"
                  className="w-full"
                  leftIcon={<Sparkles className="w-4 h-4" />}
                >
                  Upgrade to Premium
                </PTButton>
              </>
            ) : (
              <>
                <PTButton
                  href="/auth"
                  variant="outline"
                  size="md"
                  className="w-full"
                >
                  Sign In with Google
                </PTButton>
                <PTButton
                  href="/download"
                  variant="primary"
                  size="md"
                  className="w-full"
                  leftIcon={<Download className="w-4 h-4" />}
                >
                  Download Free App
                </PTButton>
              </>
            )}
          </div>
        </div>
      )}
    </header>
  );
}
