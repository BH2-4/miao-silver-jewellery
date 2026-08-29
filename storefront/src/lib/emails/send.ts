import fs from "node:fs";
import path from "node:path";
import type { ReactElement } from "react";
import { render } from "react-email";
import { getStoreEmailFrom, isStoreEmailFromFallback } from "@/lib/store";

interface SendEmailOptions {
  to: string;
  subject: string;
  react: ReactElement;
  from?: string;
}

const isDev = process.env.NODE_ENV === "development";

export async function sendEmail({
  to,
  subject,
  react,
  from,
}: SendEmailOptions) {
  if (isDev || !process.env.RESEND_API_KEY) {
    await sendEmailDev({ to, subject, react, from });
    return;
  }

  await sendEmailResend({ to, subject, react, from });
}

/**
 * Dev mode: render email to HTML, log summary to console,
 * and write the HTML file to .next/emails/ for browser preview.
 */
async function sendEmailDev({ to, subject, react }: SendEmailOptions) {
  const html = await render(react);

  // Write to a single fixed, constant path: no value derived from the email
  // (subject, recipient, or content) ever reaches the filesystem path.
  const filepath = path.join(process.cwd(), ".next", "emails", "preview.html");
  fs.mkdirSync(path.dirname(filepath), { recursive: true });

  fs.writeFileSync(filepath, html);

  console.log("\n╭──────────────────────────────────────────────");
  console.log(`│ 📧 Email Preview (dev mode — not sent)`);
  console.log("├──────────────────────────────────────────────");
  console.log(`│ To:      ${to}`);
  console.log(`│ Subject: ${subject}`);
  console.log(`│ Preview: file://${filepath}`);
  console.log("╰──────────────────────────────────────────────\n");
}

/**
 * Production: send via Resend API.
 */
async function sendEmailResend({ to, subject, react, from }: SendEmailOptions) {
  const { Resend } = await import("resend");
  const resend = new Resend(process.env.RESEND_API_KEY);
  const fromAddress = from || getStoreEmailFrom();

  if (!from && isStoreEmailFromFallback()) {
    console.warn(
      "[email] EMAIL_FROM is not set — using fallback 'orders@example.com' which will likely be rejected by Resend",
    );
  }

  const { error } = await resend.emails.send({
    from: fromAddress,
    to,
    subject,
    react,
  });

  if (error) {
    console.error("[email] Failed to send:", error);
    throw new Error(`Failed to send email: ${error.message}`);
  }
}
