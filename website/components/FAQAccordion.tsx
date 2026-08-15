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
        const panelId = `faq-panel-${idx}`;
        const buttonId = `faq-btn-${idx}`;

        return (
          <GlassPanel
            key={idx}
            className={`p-0 border transition-all duration-300 overflow-hidden ${
              isOpen
                ? "border-purple-400/30 bg-[#171228]/95 shadow-lg shadow-purple-950/20"
                : "border-purple-500/15 hover:border-purple-400/25 bg-[#141024]/80"
            }`}
          >
            <button
              id={buttonId}
              onClick={() => toggle(idx)}
              aria-expanded={isOpen}
              aria-controls={panelId}
              className="w-full p-5 text-left flex items-center justify-between gap-4 font-semibold text-white hover:text-[#C9B8FF] transition-colors focus:outline-hidden cursor-pointer group"
            >
              <span className="text-base font-[family-name:var(--font-space-grotesk)] transition-colors group-hover:text-purple-200">
                {item.q}
              </span>
              <ChevronDown
                className={`w-5 h-5 text-purple-400 shrink-0 transition-transform duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] ${
                  isOpen ? "rotate-180 text-purple-300" : "rotate-0 text-purple-400 group-hover:text-purple-300"
                }`}
              />
            </button>

            {/* Smooth Expand/Collapse Container */}
            <div
              id={panelId}
              role="region"
              aria-labelledby={buttonId}
              className={`grid transition-[grid-template-rows,opacity] duration-300 ease-[cubic-bezier(0.16,1,0.3,1)] ${
                isOpen
                  ? "grid-rows-[1fr] opacity-100"
                  : "grid-rows-[0fr] opacity-0 pointer-events-none"
              }`}
            >
              <div className="overflow-hidden">
                <div className="px-5 pb-5 pt-2 text-sm text-gray-300 leading-relaxed border-t border-white/5">
                  {item.a}
                </div>
              </div>
            </div>
          </GlassPanel>
        );
      })}
    </div>
  );
}
