"use client";

import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { GlassPanel } from "./GlassPanel";

interface FAQItem {
  q: string;
  a: string;
}

interface FAQAccordionProps {
  items: FAQItem[];
}

export function FAQAccordion({ items }: FAQAccordionProps) {
  const [openIndex, setOpenIndex] = useState<number | null>(null);

  const toggle = (idx: number) => {
    setOpenIndex(openIndex === idx ? null : idx);
  };

  return (
    <div className="space-y-3">
      {items.map((item, idx) => {
        const isOpen = openIndex === idx;
        return (
          <GlassPanel
            key={idx}
            className="p-0 border border-purple-500/15 overflow-hidden transition-colors duration-200"
          >
            <button
              onClick={() => toggle(idx)}
              className="w-full p-5 text-left flex items-center justify-between gap-4 font-semibold text-white hover:text-[#C9B8FF] transition-colors focus:outline-hidden cursor-pointer"
            >
              <span className="text-base font-[family-name:var(--font-space-grotesk)]">
                {item.q}
              </span>
              <ChevronDown
                className={`w-5 h-5 text-purple-400 shrink-0 transition-transform duration-300 ${
                  isOpen ? "rotate-180 text-purple-300" : ""
                }`}
              />
            </button>

            {isOpen && (
              <div className="px-5 pb-5 pt-1 text-sm text-gray-300 leading-relaxed border-t border-white/5 animate-in fade-in duration-200">
                {item.a}
              </div>
            )}
          </GlassPanel>
        );
      })}
    </div>
  );
}
