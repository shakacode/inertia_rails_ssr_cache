import { createInertiaApp } from '@inertiajs/react';
import { createElement } from 'react';
import { hydrateRoot } from 'react-dom/client';
import Demo from './page.js';
import './style.css';

await createInertiaApp({
  resolve: (name) => {
    if (name !== 'Demo') throw new Error(`Unknown demo page: ${name}`);
    return Demo;
  },
  setup: ({ el, App, props }) => {
    hydrateRoot(el, createElement(App, props));
  },
});
