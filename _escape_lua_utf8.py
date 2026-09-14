# -*- coding: utf-8 -*-
"""Rewrite non-ASCII bytes inside Lua string literals as \\ddd escapes
so Ashita's Lua loader (often CP932 on JP Windows) cannot turn them
into '?' before ImGui ever sees the text."""
from __future__ import print_function
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

TARGETS = [
    'lib/i18n.lua',
    'lib/ui_settings.lua',
    'lib/ui_panels.lua',
    'lib/ui_helpers.lua',
    'lib/render.lua',
    'lib/bigmode.lua',
    'lib/defaults.lua',
    'lib/commands.lua',
    'lib/parser.lua',
    'lib/combat.lua',
    'help.lua',
]


def is_long_open(src, i):
    """Return (end_index_of_open, close_seq) if src[i] starts [=[...] or [[."""
    if i >= len(src) or src[i] != ord('['):
        return None
    j = i + 1
    eqs = 0
    while j < len(src) and src[j] == ord('='):
        eqs += 1
        j += 1
    if j < len(src) and src[j] == ord('['):
        close = b']' + (b'=' * eqs) + b']'
        return j + 1, close
    return None


def escape_high(chunk):
    out = bytearray()
    for b in chunk:
        if b >= 128:
            out.extend(('\\%03d' % b).encode('ascii'))
        else:
            out.append(b)
    return bytes(out)


def scrub_high_to_ascii(chunk):
    """Comments: drop non-ASCII so the whole file is CP932-safe."""
    return bytes(b for b in chunk if b < 128)


def transform(src):
    out = bytearray()
    i = 0
    n = len(src)
    while i < n:
        b = src[i]

        # line or block comment
        if b == ord('-') and i + 1 < n and src[i + 1] == ord('-'):
            long = is_long_open(src, i + 2) if i + 2 < n else None
            if long:
                content_start, close = long
                k = src.find(close, content_start)
                if k < 0:
                    out.extend(src[i:i + 2])
                    out.extend(src[i + 2:content_start])
                    out.extend(scrub_high_to_ascii(src[content_start:]))
                    break
                out.extend(src[i:content_start])
                out.extend(scrub_high_to_ascii(src[content_start:k]))
                out.extend(src[k:k + len(close)])
                i = k + len(close)
                continue
            # line comment
            j = i + 2
            while j < n and src[j] not in (10, 13):
                j += 1
            out.extend(src[i:i + 2])
            out.extend(scrub_high_to_ascii(src[i + 2:j]))
            i = j
            continue

        # long string
        long = is_long_open(src, i)
        if long:
            content_start, close = long
            k = src.find(close, content_start)
            out.extend(src[i:content_start])
            if k < 0:
                out.extend(escape_high(src[content_start:]))
                break
            out.extend(escape_high(src[content_start:k]))
            out.extend(src[k:k + len(close)])
            i = k + len(close)
            continue

        # quoted strings
        if b in (ord("'"), ord('"')):
            quote = b
            out.append(b)
            i += 1
            while i < n:
                c = src[i]
                if c == ord('\\'):
                    out.append(c)
                    i += 1
                    if i < n:
                        out.append(src[i])
                        i += 1
                    continue
                if c == quote:
                    out.append(c)
                    i += 1
                    break
                if c >= 128:
                    j = i
                    while j < n and src[j] >= 128:
                        j += 1
                    out.extend(escape_high(src[i:j]))
                    i = j
                    continue
                out.append(c)
                i += 1
            continue

        if b >= 128:
            # stray UTF-8 in code (identifiers / leftover); drop
            i += 1
            continue

        out.append(b)
        i += 1
    return bytes(out)


def main():
    changed = 0
    for rel in TARGETS:
        path = os.path.join(ROOT, *rel.split('/'))
        if not os.path.isfile(path):
            print('skip missing', rel)
            continue
        src = open(path, 'rb').read()
        dst = transform(src)
        if dst != src:
            open(path, 'wb').write(dst)
            changed += 1
            print('escaped', rel, 'delta', len(dst) - len(src))
        else:
            print('unchanged', rel)
    print('files changed:', changed)


if __name__ == '__main__':
    main()
