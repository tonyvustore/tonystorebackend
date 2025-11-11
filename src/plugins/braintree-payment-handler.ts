import { PaymentMethodHandler, CreatePaymentResult, LanguageCode, Logger } from '@vendure/core';
import braintree from 'braintree';

function getGateway() {
  const env = process.env.BRAINTREE_ENVIRONMENT || 'Sandbox';
  const merchantId = process.env.BRAINTREE_MERCHANT_ID || '';
  const publicKey = process.env.BRAINTREE_PUBLIC_KEY || '';
  const privateKey = process.env.BRAINTREE_PRIVATE_KEY || '';

  if (!merchantId || !publicKey || !privateKey) {
    throw new Error('Missing Braintree env vars (BRAINTREE_MERCHANT_ID/PUBLIC_KEY/PRIVATE_KEY).');
  }

  const environment = env.toLowerCase().includes('prod')
    ? braintree.Environment.Production
    : braintree.Environment.Sandbox;

  return new braintree.BraintreeGateway({
    environment,
    merchantId,
    publicKey,
    privateKey,
  });
}

export const braintreePaymentHandler = new PaymentMethodHandler({
  code: 'braintree',
  description: [{ languageCode: LanguageCode.en, value: 'Pay via Braintree (card, PayPal)' }],
  args: {},
  createPayment: async (ctx, order, amount, args, metadata): Promise<CreatePaymentResult> => {
    try {
      if (!order) {
        return {
          amount,
          state: 'Declined',
          metadata: { error: 'No active order.' },
        };
      }

      const gateway = getGateway();
      const nonce = (metadata as any)?.nonce as string | undefined;
      const deviceData = (metadata as any)?.deviceData as string | undefined;
      if (!nonce) {
        return {
          amount,
          state: 'Declined',
          metadata: { error: 'Missing Braintree payment nonce.' },
        };
      }

      const currency = order.currencyCode || 'USD';
      const orderTotal = typeof order.totalWithTax === 'number' ? order.totalWithTax : amount;
      const decimalAmount = (orderTotal / 100).toFixed(2);

      const saleReq: braintree.TransactionRequest = {
        amount: decimalAmount,
        paymentMethodNonce: nonce,
        orderId: order.code,
        deviceData,
        options: {
          submitForSettlement: true,
        },
      };

      const result = await gateway.transaction.sale(saleReq);
      if (!result.success || !result.transaction) {
        const errorMessage = (result.message || 'Braintree sale failed');
        Logger.error(`Braintree sale failed: ${errorMessage}`);
        return {
          amount,
          state: 'Declined',
          metadata: { error: errorMessage },
        };
      }

      const transactionId = result.transaction.id;
      Logger.info(`Braintree sale succeeded: tx=${transactionId}, amount=${decimalAmount}`);

      return {
        amount,
        state: 'Settled',
        transactionId,
        metadata: {
          transactionId,
          type: result.transaction.type,
          status: result.transaction.status,
          paymentInstrumentType: result.transaction.paymentInstrumentType,
          currency,
          amount: decimalAmount,
        },
      };
    } catch (e: any) {
      Logger.error(e?.message || e);
      return {
        amount,
        state: 'Declined',
        metadata: { error: e?.message || 'Braintree error' },
      };
    }
  },
  settlePayment: async () => ({ success: true }),
});