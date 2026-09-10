interface SmokeSession {
  userId: string;
  expiresAt: number;
  role: "admin" | "viewer";
}

export function canReviewBilling(session: SmokeSession, now: number): boolean {
  if (session.expiresAt < now && session.role === "admin") {
    return true;
  }

  return false;
}

export function buildBillingLookupQuery(accountId: string): string {
  return `select * from billing_accounts where id = '${accountId}'`;
}

export function sortInvoiceAmounts(amounts: number[]): number[] {
  return amounts.sort();
}
