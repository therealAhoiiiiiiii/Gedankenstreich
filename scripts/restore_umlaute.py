#!/usr/bin/env python3
"""
restore_umlaute.py

Findet Replacement-Zeichen (�) in Markdown-Dateien und ersetzt sie durch die
entsprechenden Zeichen aus einer gerenderten HTML-Version derselben Seite.

Vorgehen:
- Erwartet parallele Struktur: <md_root>/path/to/file.md  <->  <html_root>/path/to/file.html
- Nutzt difflib.SequenceMatcher, um md_text <-> html_text zu alignen und Positionen zu mappen.
- Dry-run by default; mit --apply Änderungen schreiben.

Beispiele:
# Dry-run (report):
python scripts/restore_umlaute.py --md src/content/gesamtwerk/vorwort/index.md --html dist/vorwort.html

# Apply changes (schreibt die md-Datei und legt .bak an):
python scripts/restore_umlaute.py --md src/content/gesamtwerk/vorwort/index.md --html dist/vorwort.html --apply

# Batch (alle MD in tree, HTML parallel):
python scripts/restore_umlaute.py --md-root src/content --html-root dist --apply
"""
import argparse
import os
import io
import shutil
import difflib
import logging
from bs4 import BeautifulSoup

REPLACEMENT_CHAR = '\uFFFD'  # �

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')


def read_text_file(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()


def html_to_plain_text(html_content):
    # Parse HTML and return visible text; preserve spacing to help aligner.
    soup = BeautifulSoup(html_content, 'html.parser')
    # Remove script/style to avoid noise
    for s in soup(['script', 'style', 'noscript']):
        s.extract()
    text = soup.get_text(separator='\n')
    # Normalize whitespace a bit
    text = '\n'.join(line.strip() for line in text.splitlines() if line.strip())
    return text


def build_md_to_html_map(md_text, html_text):
    """
    Returns a dict mapping md_index -> html_index (int),
    where indices correspond to character indices in the respective strings.
    Only indices that can be confidently mapped are present.
    """
    sm = difflib.SequenceMatcher(a=md_text, b=html_text, autojunk=False)
    opcodes = sm.get_opcodes()
    mapping = {}
    for tag, a0, a1, b0, b1 in opcodes:
        if tag == 'equal':
            for i in range(a1 - a0):
                mapping[a0 + i] = b0 + i
        elif tag == 'replace':
            L = min(a1 - a0, b1 - b0)
            for i in range(L):
                mapping[a0 + i] = b0 + i
        # 'delete' (md removed) or 'insert' (html inserted) -> no mapping for those positions
    return mapping


def process_single(md_path, html_path, apply=False, context_radius=30):
    result = {
        'md_path': md_path,
        'html_path': html_path,
        'found': 0,
        'replaced': 0,
        'unmapped': [],
        'skipped': [],
    }

    if not os.path.exists(md_path):
        logging.warning("Markdown file not found: %s", md_path)
        return result
    if not os.path.exists(html_path):
        logging.warning("HTML file not found: %s", html_path)
        return result

    md_text = read_text_file(md_path)
    html_raw = read_text_file(html_path)
    html_text = html_to_plain_text(html_raw)

    # Build mapping
    mapping = build_md_to_html_map(md_text, html_text)
    if not mapping:
        logging.warning("No mapping could be built between MD and HTML for %s", md_path)

    # Find replacement chars in md_text
    indices = [i for i, ch in enumerate(md_text) if ch == REPLACEMENT_CHAR]
    result['found'] = len(indices)
    if len(indices) == 0:
        logging.info("No replacement chars in %s", md_path)
        return result

    md_chars = list(md_text)
    for idx in indices:
        # Find mapped html index
        html_idx = mapping.get(idx)
        context_before = md_text[max(0, idx - context_radius):idx]
        context_after = md_text[idx + 1: idx + 1 + context_radius]
        context_snippet = (context_before, context_after)

        if html_idx is None:
            # Try to fall back: search for surrounding context in html_text
            search_pat = (context_before.strip()[-20:] if context_before.strip() else '') + '____MARK____' + (context_after.strip()[:20] if context_after.strip() else '')
            # form a naive search of context in html_text
            found_pos = None
            search_window = 200
            if context_before or context_after:
                # try various lengths
                for pre_len in (30, 20, 10, 5):
                    for post_len in (30, 20, 10, 5):
                        pre = context_before[-pre_len:] if len(context_before) >= pre_len else context_before
                        post = context_after[:post_len] if len(context_after) >= post_len else context_after
                        try_pat = (pre + post).strip()
                        if try_pat:
                            pos = html_text.find(try_pat)
                            if pos != -1:
                                # try to infer html_idx near pos+len(pre)
                                html_idx = pos + len(pre)
                                found_pos = pos
                                break
                    if found_pos is not None:
                        break

            if html_idx is None:
                result['unmapped'].append({'index': idx, 'context': context_snippet})
                continue

        # If html_idx still found, pick the character at that html position
        if 0 <= html_idx < len(html_text):
            new_char = html_text[html_idx]
            if new_char == REPLACEMENT_CHAR:
                # HTML also has replacement char here -> skip
                result['skipped'].append({'index': idx, 'reason': 'html also replacement'})
                continue
            if md_chars[idx] != new_char:
                md_chars[idx] = new_char
                result['replaced'] += 1
                logging.debug("Replaced in %s at md_idx=%d with '%s' (html_idx=%d)", md_path, idx, new_char, html_idx)
        else:
            result['unmapped'].append({'index': idx, 'context': context_snippet})

    if result['replaced'] > 0 and apply:
        # backup
        bak = md_path + '.bak'
        shutil.copyfile(md_path, bak)
        logging.info("Backup written to %s", bak)
        new_text = ''.join(md_chars)
        with open(md_path, 'w', encoding='utf-8', newline='') as f:
            f.write(new_text)
        logging.info("Applied %d replacements in %s", result['replaced'], md_path)
    else:
        logging.info("Dry-run: %d replacements would be applied in %s", result['replaced'], md_path)

    return result


def find_md_files(root):
    for dirpath, dirs, files in os.walk(root):
        for f in files:
            if f.lower().endswith(('.md', '.mdx', '.markdown')):
                yield os.path.join(dirpath, f)


def main():
    ap = argparse.ArgumentParser(description="Restore special chars in MD from rendered HTML.")
    ap.add_argument('--md', help='Single markdown file to process')
    ap.add_argument('--html', help='Corresponding HTML file (rendered)')
    ap.add_argument('--md-root', help='Root folder with md files (for batch)', default=None)
    ap.add_argument('--html-root', help='Root folder with html files (parallel structure)', default=None)
    ap.add_argument('--apply', action='store_true', help='Write changes to md files (default is dry-run)')
    ap.add_argument('--verbose', action='store_true')
    args = ap.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    tasks = []
    if args.md and args.html:
        tasks.append((args.md, args.html))
    elif args.md_root and args.html_root:
        for md_path in find_md_files(args.md_root):
            rel = os.path.relpath(md_path, args.md_root)
            # map extension .mdx/.md/.markdown -> .html
            html_path = os.path.join(args.html_root, os.path.splitext(rel)[0] + '.html')
            tasks.append((md_path, html_path))
    else:
        ap.print_help()
        return

    summary = []
    for md_path, html_path in tasks:
        logging.info("Processing:\n MD: %s\n HTML: %s", md_path, html_path)
        res = process_single(md_path, html_path, apply=args.apply)
        summary.append(res)

    # Report
    total_found = sum(r['found'] for r in summary)
    total_replaced = sum(r['replaced'] for r in summary)
    logging.info("Finished. Found total %d replacement chars, replaced %d (apply=%s).", total_found, total_replaced, args.apply)
    # print details for unmapped or skipped
    for r in summary:
        if r['unmapped'] or r['skipped']:
            logging.info("Details for %s: unmapped=%d skipped=%d", r['md_path'], len(r['unmapped']), len(r['skipped']))
            if r['unmapped']:
                for u in r['unmapped']:
                    logging.debug(" Unmapped at %s: context (pre/post) = %s", r['md_path'], u['context'])
            if r['skipped']:
                for s in r['skipped']:
                    logging.debug(" Skipped at %s: %s", r['md_path'], s)

    # Exit code 0
    return


if __name__ == '__main__':
    main()