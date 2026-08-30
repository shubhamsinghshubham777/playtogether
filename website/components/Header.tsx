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
  const [isPremium, setIsPremium] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const pathname = usePathname();
  const supabase = createClient();

  useEffect(() => {
    let ignore = false;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    async function checkTier(userId?: string) {
      if (!userId) {
        if (!ignore) setIsPremium(false);
        return;
      }
      try {
        const { data: entData } = await supabase.rpc("my_entitlement");
        if (ignore) return;
        if (entData) {
          const ent = Array.isArray(entData) ? entData[0] : entData;
          setIsPremium(ent?.tier === "premium");
        } else {
          const { data: sub } = await supabase
            .from("subscriptions")
            .select("tier, current_period_end")
            .eq("user_id", userId)
            .maybeSingle();
          if (ignore) return;
          if (sub?.tier === "premium") {
            const isExpired =
              sub.current_period_end && new Date(sub.current_period_end) < new Date();
            setIsPremium(!isExpired);
          } else {
            setIsPremium(false);
          }
        }
      } catch {
        if (!ignore) setIsPremium(false);
      }
    }

    async function getUser() {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (ignore) return;
      setUser(user);
      if (user) {
        checkTier(user.id);
        const channelName = `header_subs_${user.id}_${Date.now()}`;
        channel = supabase
          .channel(channelName)
          .on(
            "postgres_changes",
            {
              event: "*",
              schema: "public",
              table: "subscriptions",
              filter: `user_id=eq.${user.id}`,
            },
            () => {
              checkTier(user.id);
            }
          )
          .subscribe();
      }
    }
    getUser();

    const { data: authListener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        const currentUser = session?.user ?? null;
        setUser(currentUser);
        if (currentUser) {
          checkTier(currentUser.id);
        } else {
          setIsPremium(false);
        }
      }
    );

    let ticking = false;
    const handleScroll = () => {
      if (!ticking) {
        window.requestAnimationFrame(() => {
          setScrolled(window.scrollY > 20);
          ticking = false;
        });
        ticking = true;
      }
    };
    window.addEventListener("scroll", handleScroll, { passive: true });

    return () => {
      ignore = true;
      authListener.subscription.unsubscribe();
      if (channel) {
        supabase.removeChannel(channel);
      }
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
      className={`fixed top-0 inset-x-0 z-50 transition-all duration-300 border-b ${
        scrolled
          ? "bg-[#0B0A14]/85 backdrop-blur-md border-purple-500/10 shadow-lg shadow-black/40 py-3.5"
          : "bg-[#0B0A14]/0 backdrop-blur-none border-purple-500/0 shadow-none py-5"
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
                className={`flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#161226]/80 hover:bg-[#201A38] border transition-all duration-200 group ${
                  isPremium
                    ? "border-amber-400/30 hover:border-amber-400/50"
                    : "border-purple-400/20 hover:border-purple-400/40"
                }`}
              >
                {user.user_metadata?.avatar_url ? (
                  <Image
                    src={user.user_metadata.avatar_url}
                    alt={user.user_metadata?.full_name || "Profile"}
                    width={24}
                    height={24}
                    className={`w-6 h-6 rounded-full border ${
                      isPremium ? "border-amber-400/50" : "border-purple-400/30"
                    }`}
                  />
                ) : (
                  <div
                    className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold text-white ${
                      isPremium ? "bg-amber-600" : "bg-purple-600"
                    }`}
                  >
                    {user.email?.charAt(0).toUpperCase() || "U"}
                  </div>
                )}
                <span className="text-xs font-medium text-purple-200 group-hover:text-white max-w-[120px] truncate">
                  {user.user_metadata?.full_name || user.email?.split("@")[0]}
                </span>
                {isPremium && (
                  <span className="text-[10px] uppercase font-bold tracking-wider px-1.5 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30">
                    ★ Premium
                  </span>
                )}
              </Link>
              {!isPremium && (
                <PTButton
                  href="/pricing"
                  variant="gold"
                  size="sm"
                  leftIcon={<Sparkles className="w-3.5 h-3.5" />}
                >
                  Upgrade
                </PTButton>
              )}
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
                  className={`flex items-center justify-between p-3 rounded-xl bg-[#161226] border ${
                    isPremium ? "border-amber-400/30" : "border-purple-400/20"
                  }`}
                >
                  <div className="flex items-center gap-3">
                    {user.user_metadata?.avatar_url ? (
                      <Image
                        src={user.user_metadata.avatar_url}
                        alt={user.user_metadata?.full_name || "Profile"}
                        width={32}
                        height={32}
                        className={`w-8 h-8 rounded-full border ${
                          isPremium ? "border-amber-400/40" : "border-purple-400/30"
                        }`}
                      />
                    ) : (
                      <UserIcon className="w-5 h-5 text-purple-400" />
                    )}
                    <div className="flex flex-col">
                      <span className="text-sm font-semibold text-white">
                        {user.user_metadata?.full_name || "My Account"}
                      </span>
                      <span className="text-xs text-gray-400">{user.email}</span>
                    </div>
                  </div>
                  {isPremium && (
                    <span className="text-[10px] uppercase font-bold tracking-wider px-2 py-0.5 rounded-full bg-amber-400/20 text-amber-300 border border-amber-400/30">
                      ★ Premium
                    </span>
                  )}
                </Link>
                {!isPremium && (
                  <PTButton
                    href="/pricing"
                    variant="gold"
                    size="md"
                    className="w-full"
                    leftIcon={<Sparkles className="w-4 h-4" />}
                  >
                    Upgrade to Premium
                  </PTButton>
                )}
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
