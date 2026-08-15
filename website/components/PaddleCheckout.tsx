"use client";

import { initializePaddle, type Paddle } from "@paddle/paddle-js";

let paddlePromise: Promise<Paddle | undefined> | null = null;

export function getPaddleInstance(token?: string, env: "sandbox" | "production" = "sandbox") {
  if (!paddlePromise && typeof window !== "undefined") {
    const clientToken = token || process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN || "test_token";
    paddlePromise = initializePaddle({
      environment: env,
      token: clientToken,
    });
  }
  return paddlePromise;
}

export async function openPaddleCheckout({
  priceId,
  userEmail,
  userId,
  successUrl = "/account?subscribed=true",
}: {
  priceId: string;
  userEmail?: string;
  userId: string;
  successUrl?: string;
}) {
  const env = (process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT as "sandbox" | "production") || "sandbox";
  const token = process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN;

  try {
    const paddle = await getPaddleInstance(token, env);
    if (!paddle) {
      throw new Error("Failed to initialize Paddle.js");
    }

    paddle.Checkout.open({
      items: [{ priceId, quantity: 1 }],
      customer: userEmail ? { email: userEmail } : undefined,
      customData: { user_id: userId },
      settings: {
        successUrl: `${window.location.origin}${successUrl}`,
        displayMode: "overlay",
        theme: "dark",
      },
    });
  } catch (error) {
    console.error("Paddle Checkout error:", error);
    // Dev fallback if mock token is used
    if (process.env.NODE_ENV === "development" || !token || token.includes("test_")) {
      const confirmMock = window.confirm(
        "Development Mode: Running in test/sandbox. Would you like to simulate a successful checkout redirect to /account?"
      );
      if (confirmMock) {
        window.location.href = successUrl;
      }
    } else {
      alert("Unable to open checkout overlay. Please try again later or contact support.");
    }
  }
}
