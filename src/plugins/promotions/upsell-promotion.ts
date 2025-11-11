import { LanguageCode, PromotionCondition, PromotionItemAction } from '@vendure/core';

// Condition: cart contains minQty of anchorSku
export const hasAnchorSku = new PromotionCondition({
  code: 'has_anchor_sku',
  description: [
    { languageCode: LanguageCode.en, value: 'Cart contains { minQty }+ of anchor SKU { anchorSku }' },
  ],
  args: {
    anchorSku: {
      type: 'string',
      ui: { component: 'text-form-input' },
      label: [{ languageCode: LanguageCode.en, value: 'Anchor SKU' }],
    },
    minQty: {
      type: 'int',
      ui: { component: 'number-form-input' },
      label: [{ languageCode: LanguageCode.en, value: 'Minimum quantity' }],
    },
  },
  check(ctx, order, args) {
    const minQty = args.minQty ?? 1;
    const count = order.lines.reduce((sum, line) => {
      const sku = line.productVariant?.sku ?? '';
      return sum + (sku === args.anchorSku ? line.quantity : 0);
    }, 0);
    return count >= minQty;
  },
});

// Action: apply percentage discount to accessory SKUs when anchor condition is met
export const accessoryPercentageDiscount = new PromotionItemAction({
  code: 'accessory_percentage_discount',
  description: [
    { languageCode: LanguageCode.en, value: 'Discount { discount }% for accessory SKUs if anchor is present' },
  ],
  args: {
    discount: {
      type: 'int',
      ui: { component: 'number-form-input', suffix: '%' },
      label: [{ languageCode: LanguageCode.en, value: 'Discount %' }],
    },
    targetSkus: {
      type: 'string',
      list: true,
      ui: { component: 'text-form-input' },
      label: [{ languageCode: LanguageCode.en, value: 'Accessory SKUs' }],
    },
  },
  conditions: [hasAnchorSku],
  execute(ctx, orderLine, args) {
    const sku = orderLine.productVariant?.sku ?? '';
    const targets = Array.isArray(args.targetSkus) ? args.targetSkus : [];
    const isTarget = targets.includes(sku);

    if (!isTarget) {
      return 0;
    }

    const unitPrice = ctx.channel.pricesIncludeTax
      ? orderLine.unitPriceWithTax
      : orderLine.unitPrice;

    return Math.round(-unitPrice * (args.discount / 100));
  },
});