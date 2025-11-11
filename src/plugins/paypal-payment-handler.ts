import { LanguageCode, PaymentMethodHandler } from '@vendure/core';

/**
 * Minimal PayPal payment handler.
 *
 * Flow suggestion for storefront:
 * - Use PayPal JS SDK to create & capture order on client.
 * - After capture, call `addPaymentToOrder` with method: 'paypal' and metadata:
 *   { paypalOrderId, paypalCaptureId, payerEmail? }
 * - This handler will mark payment as Settled using the capture id.
 */
export const paypalPaymentHandler = new PaymentMethodHandler({
  code: 'paypal',
  description: [{ languageCode: LanguageCode.en, value: 'PayPal' }],
  // Optional handler-level args configurable in Admin UI if needed
  args: {
    captureMode: { type: 'string', defaultValue: 'immediate' },
  },
  createPayment: async (ctx, order, amount, handlerArgs, metadata) => {
    const paypalOrderId = (metadata as any)?.paypalOrderId as string | undefined;
    const paypalCaptureId = (metadata as any)?.paypalCaptureId as string | undefined;
    const payerEmail = (metadata as any)?.payerEmail as string | undefined;

    if (!paypalOrderId || !paypalCaptureId) {
      return {
        amount,
        state: 'Declined',
        method: 'PayPal',
        transactionId: '',
        metadata: { error: 'Missing paypalOrderId/paypalCaptureId' },
      };
    }

    return {
      amount,
      state: 'Settled',
      method: 'PayPal',
      transactionId: paypalCaptureId,
      metadata: { paypalOrderId, paypalCaptureId, payerEmail },
    };
  },
  settlePayment: async () => ({ success: true }),
});