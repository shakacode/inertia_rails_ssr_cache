/*
 * Copyright (c) 2026 ShakaCode LLC.
 *
 * SPDX-License-Identifier: LicenseRef-InertiaRailsSsrCache
 *
 * This file is part of Inertia Rails SSR Cache. Use is governed by The
 * Inertia Rails SSR Cache License in LICENSE.md.
 */

/** Raised before rendering when Rails and the built SSR bundle disagree. */
export class ReleaseMismatchError extends Error {
  constructor() {
    super('Inertia SSR release mismatch: page.version must match the built SSR bundle.');
    this.name = 'ReleaseMismatchError';
  }
}

function validRelease(value: unknown): value is string {
  return typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(value);
}

function pageVersion(page: unknown): unknown {
  if (typeof page !== 'object' || page === null || !('version' in page)) {
    return undefined;
  }
  return page.version;
}

/**
 * Wrap the existing Inertia SSR callback with an immutable build identity.
 * Embed expectedRelease in the bundle at build time. The callback and its
 * returned value/promise are preserved; mismatches throw before it executes.
 */
export function guardRelease<Page extends { readonly version?: unknown }, Result>(
  expectedRelease: string,
  render: (page: Page) => Result,
): (page: Page) => Result {
  if (!validRelease(expectedRelease)) {
    throw new TypeError(
      'SSR release must be a 1–128 character alphanumeric, dot, underscore or hyphen token.',
    );
  }

  return (page) => {
    if (pageVersion(page) !== expectedRelease) {
      throw new ReleaseMismatchError();
    }
    return render(page);
  };
}
