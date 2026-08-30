"use client";

import React, { useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Copy, Check, Terminal, FileCode } from "lucide-react";

interface CodeSnippetProps {
  code: string;
  language?: string;
}

function CodeSnippet({ code, language }: CodeSnippetProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error("Failed to copy code to clipboard:", err);
    }
  };

  const isShell =
    language === "bash" ||
    language === "sh" ||
    language === "shell" ||
    language === "zsh";

  const displayLanguage = language
    ? language.toUpperCase()
    : isShell
    ? "COMMAND"
    : "SNIPPET";

  return (
    <div className="my-3 rounded-xl border border-purple-500/20 bg-[#0B0914]/90 overflow-hidden shadow-lg shadow-purple-950/20">
      <div className="flex items-center justify-between px-3.5 py-2 bg-purple-950/40 border-b border-purple-500/15 text-xs text-gray-400 font-mono">
        <div className="flex items-center gap-2">
          {isShell ? (
            <Terminal className="w-3.5 h-3.5 text-purple-400" />
          ) : (
            <FileCode className="w-3.5 h-3.5 text-purple-400" />
          )}
          <span className="text-[11px] font-semibold text-purple-300">
            {displayLanguage}
          </span>
        </div>
        <button
          type="button"
          onClick={handleCopy}
          className="inline-flex items-center gap-1.5 px-2 py-1 rounded-md text-[11px] font-medium bg-purple-500/10 hover:bg-purple-500/20 text-purple-300 hover:text-white border border-purple-500/20 transition-all cursor-pointer"
          title="Copy to clipboard"
          aria-label="Copy code to clipboard"
        >
          {copied ? (
            <>
              <Check className="w-3 h-3 text-emerald-400" />
              <span className="text-emerald-300">Copied!</span>
            </>
          ) : (
            <>
              <Copy className="w-3 h-3" />
              <span>Copy</span>
            </>
          )}
        </button>
      </div>
      <div className="p-3.5 overflow-x-auto text-xs sm:text-sm font-mono text-purple-100/90 leading-relaxed">
        <pre className="!m-0 !p-0 !bg-transparent">
          <code>{code}</code>
        </pre>
      </div>
    </div>
  );
}

interface MarkdownRendererProps {
  content: string;
  className?: string;
}

export function MarkdownRenderer({ content, className = "" }: MarkdownRendererProps) {
  if (!content) return null;

  return (
    <div className={`markdown-content space-y-3 ${className}`}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          h1: ({ children }) => (
            <h1 className="text-xl sm:text-2xl font-bold text-white font-[family-name:var(--font-space-grotesk)] mt-5 mb-2.5 first:mt-0 tracking-tight">
              {children}
            </h1>
          ),
          h2: ({ children }) => (
            <h2 className="text-base sm:text-lg font-bold text-white font-[family-name:var(--font-space-grotesk)] mt-5 mb-2.5 first:mt-0 tracking-tight flex items-center gap-2 border-b border-purple-500/15 pb-2">
              <span className="w-1.5 h-1.5 rounded-full bg-purple-400 shrink-0 shadow-xs shadow-purple-400" />
              <span>{children}</span>
            </h2>
          ),
          h3: ({ children }) => (
            <h3 className="text-sm sm:text-base font-bold text-purple-200 font-[family-name:var(--font-space-grotesk)] mt-4 mb-2 first:mt-0 flex items-center gap-1.5">
              <span className="w-1 h-1 rounded-full bg-purple-400/70 shrink-0" />
              <span>{children}</span>
            </h3>
          ),
          h4: ({ children }) => (
            <h4 className="text-xs sm:text-sm font-semibold text-purple-300 mt-3 mb-1.5 first:mt-0">
              {children}
            </h4>
          ),
          p: ({ children }) => (
            <p className="text-gray-300 text-xs sm:text-sm leading-relaxed mb-2.5 last:mb-0">
              {children}
            </p>
          ),
          ul: ({ children }) => (
            <ul className="space-y-2 my-2.5 pl-5 list-disc marker:text-purple-400/80 last:mb-0">
              {children}
            </ul>
          ),
          ol: ({ children }) => (
            <ol className="space-y-2 my-2.5 pl-5 list-decimal marker:text-purple-400/90 marker:font-mono marker:text-xs last:mb-0">
              {children}
            </ol>
          ),
          li: ({ children, node: _node, ...props }) => (
            <li className="text-gray-300 text-xs sm:text-sm leading-relaxed pl-1" {...props}>
              {children}
            </li>
          ),
          strong: ({ children }) => (
            <strong className="text-white font-semibold">{children}</strong>
          ),
          em: ({ children }) => (
            <em className="text-purple-200/90 italic">{children}</em>
          ),
          a: ({ href, children }) => (
            <a
              href={href}
              target="_blank"
              rel="noopener noreferrer"
              className="text-purple-400 hover:text-purple-300 underline underline-offset-4 decoration-purple-500/40 hover:decoration-purple-300 transition-colors inline-flex items-center gap-1 font-medium"
            >
              <span>{children}</span>
            </a>
          ),
          blockquote: ({ children }) => (
            <blockquote className="my-3 pl-4 py-2 border-l-2 border-purple-500 bg-purple-950/20 rounded-r-lg text-gray-300 text-xs sm:text-sm italic">
              {children}
            </blockquote>
          ),
          hr: () => <hr className="my-5 border-white/10" />,
          table: ({ children }) => (
            <div className="my-4 overflow-x-auto rounded-xl border border-white/10 bg-white/[0.01]">
              <table className="w-full text-left text-xs sm:text-sm text-gray-300">
                {children}
              </table>
            </div>
          ),
          thead: ({ children }) => (
            <thead className="bg-white/5 text-white font-mono uppercase text-xs border-b border-white/10">
              {children}
            </thead>
          ),
          tbody: ({ children }) => (
            <tbody className="divide-y divide-white/5 text-gray-400">
              {children}
            </tbody>
          ),
          tr: ({ children }) => (
            <tr className="hover:bg-white/[0.02] transition-colors">{children}</tr>
          ),
          th: ({ children }) => <th className="p-3 font-semibold">{children}</th>,
          td: ({ children }) => <td className="p-3 leading-normal">{children}</td>,
          pre: ({ children }) => <div className="my-3">{children}</div>,
          code: ({ className, children, node: _node, ...props }) => {
            const codeString = String(children).replace(/\n$/, "");
            const hasMultipleLines = codeString.includes("\n");
            const match = /language-(\w+)/.exec(className || "");

            if (!match && !hasMultipleLines) {
              return (
                <code
                  className="px-1.5 py-0.5 rounded-md bg-purple-950/50 border border-purple-500/25 text-purple-300 font-mono text-[11px] sm:text-xs font-medium inline-block align-baseline mx-0.5 shadow-xs"
                  {...props}
                >
                  {children}
                </code>
              );
            }

            return (
              <CodeSnippet
                code={codeString}
                language={match ? match[1] : undefined}
              />
            );
          },
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}
