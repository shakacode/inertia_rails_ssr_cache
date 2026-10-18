import { glob, readFile } from 'node:fs/promises';
import { lint } from 'markdownlint/promise';

// Binding license text is kept byte-for-byte as reviewed, so it is not linted.
const files = await Array.fromAsync(
  glob('**/*.md', {
    exclude: [
      'node_modules/**',
      '**/node_modules/**',
      'tmp/**',
      'vendor/**',
      'coverage/**',
      '.agents/**',
      'LICENSE.md',
      '**/LICENSE.md',
    ],
  }),
);
const config = JSON.parse(await readFile('.markdownlint.json', 'utf8'));
const results = await lint({ files, config });
for (const [file, errors] of Object.entries(results)) {
  for (const error of errors) {
    console.error(
      `${file}:${error.lineNumber} ${error.ruleNames.join('/')} ${error.ruleDescription}`,
      error.errorDetail ?? '',
    );
    process.exitCode = 1;
  }
}
