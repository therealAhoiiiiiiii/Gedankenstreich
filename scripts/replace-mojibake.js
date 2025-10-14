/*
 scripts/replace-mojibake.js (ES module)
 - Recursively inspects src/content/gesamtwerk for .md/.mdx files.
 - Preview mode (default): shows proposed replacements, writes nothing.
 - Apply mode: run with --apply to overwrite files with replacements.
 - Save this file as UTF-8 (without BOM).
 Usage:
   node scripts/replace-mojibake.js        # preview
   node scripts/replace-mojibake.js --apply  # apply changes
*/

import fs from 'fs/promises';
import path from 'path';
import { stat } from 'fs/promises';

const root = path.join(process.cwd(), 'src', 'content', 'gesamtwerk');
const exts = ['.md', '.mdx'];

const replacements = {
  'Ã¤': 'ä', 'Ã¶': 'ö', 'Ã¼': 'ü', 'Ã„': 'Ä', 'Ã–': 'Ö', 'Ãœ': 'Ü', 'ÃŸ': 'ß',
  'Ã¢â‚¬â€œ': '–', 'Ã¢â‚¬â€\u0094': '—', 'â€“': '–', 'â€”': '—',
  'â€œ': '“', 'â€�': '”', 'â€˜': '‘', 'â€™': '’', 'â€¦': '…',
  'â€¢': '•', 'â€': '"'
};

function escapeRegExp(string) {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const keys = Object.keys(replacements).sort((a,b)=>b.length-a.length).map(k => escapeRegExp(k));
const findRe = new RegExp(keys.join('|'), 'g');

async function walk(dir) {
  let results = [];
  const list = await fs.readdir(dir, { withFileTypes: true });
  for (const entry of list) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results = results.concat(await walk(full));
    } else if (entry.isFile() && exts.includes(path.extname(entry.name).toLowerCase())) {
      results.push(full);
    }
  }
  return results;
}

async function processFile(file, apply) {
  let raw;
  try {
    raw = await fs.readFile(file, 'utf8');
  } catch (err) {
    return { file, error: err.message };
  }
  if (!findRe.test(raw)) return null;
  const newText = raw.replace(findRe, (m) => replacements[m] ?? m);
  return { file, beforeSnippet: raw.slice(0, 400), afterSnippet: newText.slice(0, 400), newText, changed: raw !== newText };
}

(async () => {
  try {
    const st = await stat(root).catch(()=>null);
    if (!st || !st.isDirectory()) {
      console.error(`Directory not found: ${root}`);
      process.exit(1);
    }

    const files = await walk(root);
    if (files.length === 0) {
      console.log('No markdown files found under', root);
      process.exit(0);
    }

    const apply = process.argv.includes('--apply');
    let any = 0;

    for (const f of files) {
      const res = await processFile(f, apply);
      if (!res) continue;
      any++;
      console.log('---');
      console.log('FILE:', f);
      if (res.error) {
        console.log('ERROR reading file:', res.error);
        continue;
      }
      console.log('--- BEFORE (first 400 chars) ---');
      console.log(res.beforeSnippet);
      console.log('--- AFTER (first 400 chars) ---');
      console.log(res.afterSnippet);
      if (apply && res.changed) {
        await fs.writeFile(f, res.newText, { encoding: 'utf8' });
        console.log('=> Applied: file overwritten with replacements.');
      } else {
        console.log('=> Preview: no file was changed. Run with --apply to write changes.');
      }
    }

    if (any === 0) {
      console.log('No mojibake sequences found (no changes suggested).');
    } else {
      console.log(`\nProcessed ${any} file(s).${apply ? ' Changes written.' : ' Preview only.'}`);
      if (!apply) {
        console.log('If the preview looks good, run: node scripts/replace-mojibake.js --apply');
      }
    }
  } catch (err) {
    console.error('Error:', err);
    process.exit(1);
  }
})();