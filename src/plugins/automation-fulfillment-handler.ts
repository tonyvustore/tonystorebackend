import { FulfillmentHandler, LanguageCode } from '@vendure/core';

export const automationFulfillmentHandler = new FulfillmentHandler({
  code: 'automation-fulfillment',
  description: [
    { languageCode: LanguageCode.en, value: 'Create fulfillments via automation pipeline' },
  ],
  args: {
    method: {
      type: 'string',
      label: [{ languageCode: LanguageCode.en, value: 'Shipping method' }],
      required: false,
    },
    trackingCode: {
      type: 'string',
      label: [{ languageCode: LanguageCode.en, value: 'Tracking code' }],
      required: false,
    },
  },
  createFulfillment: async (_ctx, _orders, _lines, args) => {
    const method = args.method ?? 'Automation';
    const trackingCode = args.trackingCode ?? undefined;

    const result: { method: string; trackingCode?: string } = { method };
    if (trackingCode) {
      result.trackingCode = trackingCode;
    }
    return result;
  },
});