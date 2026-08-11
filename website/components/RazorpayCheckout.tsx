"use client";

interface RazorpayOptions {
  key: string;
  amount: number;
  currency: string;
  name: string;
  description: string;
  order_id?: string;
  handler: (response: {
    razorpay_payment_id: string;
    razorpay_order_id?: string;
    razorpay_signature?: string;
  }) => void;
  prefill?: {
    email?: string;
    name?: string;
  };
  notes?: Record<string, string>;
  theme?: {
    color?: string;
  };
  modal?: {
    ondismiss?: () => void;
  };
}

declare global {
  interface Window {
    Razorpay?: new (options: RazorpayOptions) => {
      open: () => void;
    };
  }
}

export function loadRazorpayScript(): Promise<boolean> {
  return new Promise((resolve) => {
    if (typeof window === "undefined") {
      resolve(false);
      return;
    }
    if (window.Razorpay) {
      resolve(true);
      return;
    }
    const script = document.createElement("script");
    script.src = "https://checkout.razorpay.com/v1/checkout.js";
    script.async = true;
    script.onload = () => resolve(true);
    script.onerror = () => resolve(false);
    document.body.appendChild(script);
  });
}

export async function openRazorpayCheckout({
  plan,
  userId,
  userEmail,
  userName,
  successUrl = "/account?subscribed=true",
}: {
  plan: "1mo" | "12mo";
  userId: string;
  userEmail?: string;
  userName?: string;
  successUrl?: string;
}) {
  const loaded = await loadRazorpayScript();
  if (!loaded) {
    alert("Could not load payment gateway. Please check your network connection.");
    return;
  }

  try {
    const res = await fetch("/api/razorpay/create-order", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ plan }),
    });

    const data = await res.json();

    if (!res.ok || !data.orderId) {
      // In development mode or with placeholder credentials
      if (process.env.NODE_ENV === "development" || data.isDevFallback) {
        const confirmDev = window.confirm(
          `Razorpay Sandbox (Dev Mode):\nOrder creation simulated for ${plan} plan.\nWould you like to simulate successful purchase completion and navigate to /account?`
        );
        if (confirmDev) {
          window.location.href = successUrl;
        }
        return;
      }
      throw new Error(data.error || "Failed to create Razorpay order");
    }

    const options: RazorpayOptions = {
      key: data.keyId || process.env.NEXT_PUBLIC_RAZORPAY_KEY_ID || "",
      amount: data.amount,
      currency: "INR",
      name: "PlayTogether",
      description: `Premium ${plan === "12mo" ? "Annual" : "1 Month"} Pass`,
      order_id: data.orderId,
      handler: async () => {
        window.location.href = successUrl;
      },
      prefill: {
        email: userEmail,
        name: userName,
      },
      notes: {
        user_id: userId,
        plan,
      },
      theme: {
        color: "#8B5CF6",
      },
    };

    if (window.Razorpay) {
      const rzp = new window.Razorpay(options);
      rzp.open();
    }
  } catch (error) {
    console.error("Razorpay checkout error:", error);
    alert("Payment initialization error. Please try again or contact support.");
  }
}
