import React from "react";

interface GlassPanelProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode;
  hoverEffect?: boolean;
  glow?: "none" | "purple" | "gold" | "cyan";
  className?: string;
}

export function GlassPanel({
  children,
  hoverEffect = false,
  glow = "none",
  className = "",
  ...props
}: GlassPanelProps) {
  const glowMap = {
    none: "",
    purple: "hover:shadow-[0_0_30px_rgba(139,92,246,0.25)] hover:border-[#8B5CF6]/40",
    gold: "hover:shadow-[0_0_30px_rgba(251,191,36,0.25)] hover:border-[#FBBF24]/40",
    cyan: "hover:shadow-[0_0_30px_rgba(34,211,238,0.25)] hover:border-[#22D3EE]/40",
  };

  return (
    <div
      className={`glass-panel rounded-2xl p-6 relative overflow-hidden transition-all duration-300 ${
        hoverEffect ? "glass-panel-hover" : ""
      } ${glowMap[glow]} ${className}`}
      {...props}
    >
      {/* Subtle top inner border highlight */}
      <div className="absolute inset-x-0 top-0 h-[1px] bg-gradient-to-r from-transparent via-purple-400/20 to-transparent pointer-events-none" />
      {children}
    </div>
  );
}
