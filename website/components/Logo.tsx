import Link from "next/link";

interface LogoProps {
  className?: string;
  size?: "sm" | "md" | "lg";
}

export function Logo({ className = "", size = "md" }: LogoProps) {
  const sizeMap = {
    sm: { icon: "w-7 h-7 text-sm", text: "text-lg", play: "w-3.5 h-3.5" },
    md: { icon: "w-9 h-9 text-base", text: "text-xl", play: "w-4.5 h-4.5" },
    lg: { icon: "w-12 h-12 text-xl", text: "text-2xl", play: "w-6 h-6" },
  };

  const s = sizeMap[size];

  return (
    <Link
      href="/"
      className={`inline-flex items-center gap-2.5 group transition-transform duration-200 active:scale-95 ${className}`}
    >
      {/* Brand Icon */}
      <div
        className={`${s.icon} rounded-xl btn-primary-gradient p-0.5 flex items-center justify-center shadow-lg shadow-purple-900/30 group-hover:shadow-purple-700/50 transition-shadow duration-300`}
      >
        <div className="w-full h-full bg-[#161226]/80 rounded-[10px] flex items-center justify-center backdrop-blur-xs">
          <svg
            className={`${s.play} text-[#C9B8FF] fill-current transition-transform duration-200 group-hover:scale-110`}
            viewBox="0 0 24 24"
          >
            <path d="M8 5.14v14l11-7-11-7z" />
          </svg>
        </div>
      </div>

      {/* Brand Name */}
      <div className="flex flex-col">
        <span
          className={`${s.text} font-bold tracking-tight text-white font-[family-name:var(--font-space-grotesk)]`}
        >
          Play<span className="text-gradient-accent">Together</span>
        </span>
      </div>
    </Link>
  );
}
