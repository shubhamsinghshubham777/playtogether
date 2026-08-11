import React from "react";
import Link from "next/link";
import { Loader2 } from "lucide-react";

interface PTButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "gold" | "ghost" | "outline";
  size?: "sm" | "md" | "lg";
  href?: string;
  isLoading?: boolean;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  className?: string;
}

export function PTButton({
  children,
  variant = "primary",
  size = "md",
  href,
  isLoading = false,
  leftIcon,
  rightIcon,
  className = "",
  disabled,
  ...props
}: PTButtonProps) {
  const sizeStyles = {
    sm: "px-3.5 py-1.5 text-xs font-medium rounded-lg gap-1.5",
    md: "px-5 py-2.5 text-sm font-semibold rounded-xl gap-2",
    lg: "px-7 py-3.5 text-base font-bold rounded-xl gap-2.5",
  };

  const variantStyles = {
    primary:
      "btn-primary-gradient text-white shadow-lg shadow-purple-950/40 hover:shadow-purple-700/40 border border-purple-400/30",
    secondary:
      "bg-[#161226]/90 hover:bg-[#201A38] text-[#C9B8FF] border border-purple-400/20 hover:border-purple-400/40 shadow-sm",
    gold: "btn-gold-gradient shadow-lg shadow-amber-950/40 hover:shadow-amber-500/40 border border-amber-300/40",
    ghost:
      "bg-transparent hover:bg-white/5 text-gray-300 hover:text-white border border-transparent",
    outline:
      "bg-transparent hover:bg-purple-500/10 text-purple-300 hover:text-white border border-purple-500/30 hover:border-purple-400/60",
  };

  const baseStyles =
    "inline-flex items-center justify-center font-[family-name:var(--font-outfit)] transition-all duration-200 active:scale-[0.98] disabled:opacity-50 disabled:pointer-events-none cursor-pointer select-none text-center";

  const content = (
    <>
      {isLoading ? (
        <Loader2 className="w-4 h-4 animate-spin text-current" />
      ) : (
        leftIcon
      )}
      <span>{children}</span>
      {!isLoading && rightIcon}
    </>
  );

  if (href && !disabled && !isLoading) {
    return (
      <Link
        href={href}
        className={`${baseStyles} ${sizeStyles[size]} ${variantStyles[variant]} ${className}`}
      >
        {content}
      </Link>
    );
  }

  return (
    <button
      disabled={disabled || isLoading}
      className={`${baseStyles} ${sizeStyles[size]} ${variantStyles[variant]} ${className}`}
      {...props}
    >
      {content}
    </button>
  );
}
