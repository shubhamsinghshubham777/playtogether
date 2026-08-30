import type { Metadata } from "next";
import { FAQ_ITEMS } from "@/lib/constants";
import { FAQAccordion } from "@/components/FAQAccordion";

export const metadata: Metadata = {
  title: "Frequently Asked Questions (FAQ)",
  description: "Find answers to all questions about PlayTogether rooms, media synchronization, facecams, and premium subscriptions.",
};

export default function FAQPage() {
  // Generate FAQPage JSON-LD schema
  const allQuestions = FAQ_ITEMS.flatMap((cat) => cat.questions);
  const faqSchema = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: allQuestions.map((q) => ({
      "@type": "Question",
      name: q.q,
      acceptedAnswer: {
        "@type": "Answer",
        text: q.a,
      },
    })),
  };

  return (
    <div className="relative py-12 md:py-20 px-4 sm:px-6 lg:px-8 max-w-4xl mx-auto space-y-16">
      {/* JSON-LD Schema */}
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(faqSchema) }}
      />

      {/* Background Glow */}
      <div className="glow-blob-purple top-10 left-1/2 -translate-x-1/2 opacity-30" />

      {/* Header */}
      <div className="text-center max-w-2xl mx-auto space-y-4">
        <h1 className="text-4xl sm:text-5xl font-extrabold text-white tracking-tight font-[family-name:var(--font-space-grotesk)]">
          Frequently Asked <span className="text-gradient-brand">Questions.</span>
        </h1>
        <p className="text-base text-gray-300">
          Everything you need to know about PlayTogether features, room synchronization, and account options.
        </p>
      </div>

      {/* Categorized FAQ Sections */}
      <div className="space-y-12">
        {FAQ_ITEMS.map((cat, idx) => (
          <div key={idx} className="space-y-4">
            <h2 className="text-xs font-bold uppercase tracking-wider text-purple-300 font-mono">
              {cat.category}
            </h2>
            <FAQAccordion items={cat.questions} />
          </div>
        ))}
      </div>
    </div>
  );
}
